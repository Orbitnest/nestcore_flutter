import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment configuration service
/// Loads configuration from .env file or environment variables
class EnvConfig {
  static bool _initialized = false;

  /// The default NestCore API base URL — used when no override is provided
  static const String kBaseUrl = 'https://api.nestcore.io';

  /// The Android emulator host alias — replaces localhost/127.0.0.1 so the
  /// emulator can reach the host machine's loopback interface.
  static const String kAndroidEmulatorHost = '10.0.2.2';

  /// Initialize the environment configuration
  /// Must be called before using any environment variables
  static Future<void> initialize({String? envFileName}) async {
    if (_initialized) return;

    try {
      await dotenv.load(fileName: envFileName ?? '.env');
    } catch (_) {
      // No/unreadable .env asset (e.g. key passed to NestCoreClient.create).
      // Reads below go through [_env], which tolerates an unloaded dotenv.
    }
    _initialized = true;
  }

  /// Read a dotenv value; null when no `.env` was loaded (dotenv.env throws then).
  static String? _rawEnv(String key) =>
      dotenv.isInitialized ? dotenv.env[key] : null;

  /// Read a `NESTCORE_*` setting, falling back to the legacy `ORBITNEST_*`
  /// name (pre-1.9.0 `.env` files) when the new one is unset or empty.
  /// [key] is the suffix after the prefix, e.g. `ANON_KEY`.
  static String? _env(String key) {
    final value = _rawEnv('NESTCORE_$key');
    if (value != null && value.isNotEmpty) return value;
    return _rawEnv('$_legacyEnvPrefix$key');
  }

  /// Prefix of the pre-rename env variable names, still read as a fallback.
  static const String _legacyEnvPrefix = 'ORBITNEST_';

  /// Check if environment is initialized
  static bool get isInitialized => _initialized;

  /// Resolve a URL so that `localhost` / `127.0.0.1` is replaced with
  /// `10.0.2.2` when running on an Android emulator in debug mode.
  ///
  /// This is a no-op on physical devices, iOS, or release builds.
  static String resolveUrl(String url) {
    if (kDebugMode && !kIsWeb) {
      try {
        if (Platform.isAndroid) {
          return url
              .replaceAll('http://localhost', 'http://$kAndroidEmulatorHost')
              .replaceAll('https://localhost', 'https://$kAndroidEmulatorHost')
              .replaceAll('http://127.0.0.1', 'http://$kAndroidEmulatorHost')
              .replaceAll('https://127.0.0.1', 'https://$kAndroidEmulatorHost');
        }
      } catch (_) {
        // Platform check failed (e.g. web) — return url unchanged
      }
    }
    return url;
  }

  /// Get NestCore base URL.
  ///
  /// Uses [kBaseUrl] (`https://api.nestcore.io`) by default.
  /// Can be overridden via the `NESTCORE_API_URL` env variable in `.env`
  /// (the legacy `ORBITNEST_API_URL` is still read when it is unset)
  /// — useful when pointing at a local development server.
  ///
  /// When running on an Android emulator in debug mode any `localhost` /
  /// `127.0.0.1` value is automatically rewritten to `10.0.2.2` so the
  /// emulator can reach the host machine.
  static String get baseUrl {
    // Allow an env-var override for local development
    final envUrl = _env('API_URL');
    final raw = (envUrl != null && envUrl.isNotEmpty) ? envUrl : kBaseUrl;
    return resolveUrl(_enforceSecureScheme(raw));
  }

  /// Reject a cleartext `http://` base URL unless the host is loopback.
  ///
  /// Localhost/127.0.0.1 over http is allowed for local development. Any other
  /// `http://` host would transmit the apikey and bearer tokens in cleartext,
  /// so we warn loudly and fall back to the secure [kBaseUrl] default.
  static String _enforceSecureScheme(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.scheme != 'http') return url; // https / ws-less / etc. are fine

    final host = uri.host;
    final isLoopback = host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == kAndroidEmulatorHost;
    if (isLoopback) return url; // cleartext loopback is acceptable for dev

    debugPrint(
      'NestCore SECURITY WARNING: NESTCORE_API_URL "$url" uses cleartext '
      'http:// for a non-loopback host. Credentials would be sent unencrypted. '
      'Falling back to the secure default "$kBaseUrl". Use https://.',
    );
    return kBaseUrl;
  }

  /// Get anonymous key
  static String get anonKey {
    _ensureInitialized();
    final key = _env('ANON_KEY');
    if (key == null || key.isEmpty) {
      throw Exception('NESTCORE_ANON_KEY is required in .env file');
    }
    return key;
  }

  /// Decode and return the project slug embedded in the anon key JWT payload.
  ///
  /// The JWT anon key always contains `project_slug` in its payload, so we
  /// never need it as a separate env var.
  static String get projectSlug {
    return decodeProjectSlugFromJwt(anonKey);
  }

  /// Check if debug mode is enabled
  static bool get isDebugMode {
    _ensureInitialized();
    final debug = _env('DEBUG');
    return debug?.toLowerCase() == 'true';
  }

  /// Get API timeout in milliseconds (3 minutes default)
  static int get apiTimeout {
    _ensureInitialized();
    final timeout = _env('API_TIMEOUT');
    return int.tryParse(timeout ?? '180000') ?? 180000; // 3 minutes default
  }

  /// Decode the `project_slug` field from a JWT token payload.
  ///
  /// JWTs are structured as `header.payload.signature` where each section is
  /// base64url-encoded. We only need the payload — no secret required.
  static String decodeProjectSlugFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        throw Exception('Invalid JWT format');
      }

      // Base64url decode the payload section
      String payload = parts[1];
      // Normalise base64url → base64 by adding padding
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');

      final decoded = utf8.decode(base64.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;

      final slug = json['project_slug'] as String?;
      if (slug == null || slug.isEmpty) {
        throw Exception(
          'project_slug not found in NESTCORE_ANON_KEY JWT payload',
        );
      }
      return slug;
    } catch (e) {
      throw Exception('Failed to decode project slug from NESTCORE_ANON_KEY: $e');
    }
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      throw Exception(
        'EnvConfig not initialized. Call EnvConfig.initialize() first.',
      );
    }
  }

  /// Get all environment variables as a map (for debugging)
  static Map<String, String> get allVars {
    _ensureInitialized();
    return dotenv.isInitialized ? Map.from(dotenv.env) : {};
  }
}
