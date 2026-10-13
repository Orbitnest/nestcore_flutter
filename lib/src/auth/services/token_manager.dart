import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../models/session.dart';
import '../../constants/constants.dart';
import '../../utils/logger.dart';

/// Manages authentication tokens and session persistence
class TokenManager {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  final String? _projectSlug;
  final String? _apiKey;
  static const int _refreshThresholdMinutes = 5;
  // Cache tokens in memory for faster access
  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  // Set while a sign-out is in flight. The /auth/signout request goes through
  // onRequest → getAccessToken; if the token is expired a proactive refresh
  // would add an event to the AuthBloc that is already blocked processing the
  // sign-out — a deadlock. While signing out we skip the refresh entirely.
  bool _isSigningOut = false;


  TokenManager({String? projectSlug, String? apiKey})
    : _projectSlug = projectSlug,
      _apiKey = apiKey;

  // ── Session-expiry signal ──────────────────────────────────────────────────
  //
  // Broadcasts when the server has rejected our session AFTER a token refresh
  // has already been attempted. Subscribers (typically the host app's auth
  // bloc) should treat this as the authoritative signal to force the user
  // back to the sign-in flow. Fired exactly once per logical expiry — callers
  // should not de-dup themselves.
  final StreamController<void> _sessionExpiredController =
      StreamController<void>.broadcast();
  bool _sessionExpiredFired = false;

  /// Stream that emits when the session has been definitively rejected by the
  /// server (e.g. a 401 that even a refresh attempt could not recover). Use
  /// this to trigger a force-logout in the host application.
  Stream<void> get onSessionExpired => _sessionExpiredController.stream;

  /// Called by [AuthInterceptor] after a 401 where the refresh-retry also
  /// failed. Fires the [onSessionExpired] stream once until the next
  /// successful session is stored.
  void notifySessionExpired() {
    if (_sessionExpiredFired) return;
    _sessionExpiredFired = true;
    if (!_sessionExpiredController.isClosed) {
      _sessionExpiredController.add(null);
    }
  }

  /// Dispose the broadcast controller — call when the client is torn down.
  Future<void> dispose() async {
    if (!_sessionExpiredController.isClosed) {
      await _sessionExpiredController.close();
    }
  }

  /// Store session securely.
  Future<void> storeSession(Session session) async {
    if (session.accessToken.isEmpty) {
      OrbitNestLogger.error('storeSession: empty access token, skipping', null);
      return;
    }

    // Never overwrite a good refresh token with an empty one. Some payloads —
    // a refresh response that echoes only an access token, or a session
    // reconstructed from a source that dropped the refresh field — arrive with
    // an empty refreshToken. Persisting that would make the very next cold start
    // wipe the whole session, because getStoredSession() clears when the stored
    // refresh token is empty. Fall back to the refresh token we already hold so
    // a partial update can never destroy session persistence.
    if (session.refreshToken.isEmpty) {
      final existing = _cachedRefreshToken ??
          await _secureStorage.read(key: OrbitNestConstants.refreshTokenKey);
      if (existing != null && existing.isNotEmpty) {
        OrbitNestLogger.error(
          'storeSession: incoming session has empty refresh token — '
          'preserving the existing one',
          null,
        );
        session = session.copyWith(refreshToken: existing);
      }
    }

    // Update in-memory cache immediately — the next outbound request needs the
    // token now, before the secure-storage round-trip completes.  Doing this
    // first also means a transient storage failure (e.g. iOS keychain briefly
    // locked on app resume) never causes getAccessToken() to return null for a
    // session the server just confirmed as valid.
    _cachedAccessToken = session.accessToken;
    _cachedRefreshToken = session.refreshToken;
    // A fresh session arrived — re-arm the session-expired signal so a future
    // 401 on this new session fires the stream again.
    _sessionExpiredFired = false;

    try {
      final sessionJson = json.encode(session.toJson());
      final checksum = _generateChecksum(sessionJson);

      await Future.wait([
        _secureStorage.write(
          key: OrbitNestConstants.sessionKey,
          value: sessionJson,
        ),
        _secureStorage.write(
          key: '${OrbitNestConstants.sessionKey}_checksum',
          value: checksum,
        ),
        _secureStorage.write(
          key: OrbitNestConstants.accessTokenKey,
          value: session.accessToken,
        ),
        _secureStorage.write(
          key: OrbitNestConstants.refreshTokenKey,
          value: session.refreshToken,
        ),
      ]);
    } catch (e) {
      OrbitNestLogger.error('Failed to persist session to storage', e);
      // Do not re-throw.  In-memory cache is already updated, so the current
      // session remains usable.  The next app restart will re-run /auth/refresh.
    }
  }

  /// Retrieve stored session with integrity verification.
  /// Returns the session (even with an expired access token) so the caller can
  /// attempt a server-side refresh. Only returns null when there is genuinely
  /// no session to restore (never-signed-in, explicit sign-out, or a truly
  /// unrecoverable storage state).
  Future<Session?> getStoredSession() async {
    try {
      final sessionJson = await _secureStorage.read(
        key: OrbitNestConstants.sessionKey,
      );

      if (sessionJson == null) return null;

      // Integrity check — a mismatch most likely means storage corruption, not
      // tampering. Log a warning but continue so the server can validate the
      // refresh token via /auth/refresh. Wiping here would silently log users
      // out on any secure-storage write anomaly.
      final storedChecksum = await _secureStorage.read(
        key: '${OrbitNestConstants.sessionKey}_checksum',
      );
      if (storedChecksum != null) {
        final currentChecksum = _generateChecksum(sessionJson);
        if (storedChecksum != currentChecksum) {
          OrbitNestLogger.error(
            'getStoredSession: checksum mismatch — storage may be corrupt; '
            'proceeding to allow server-side refresh',
            null,
          );
          // Do NOT wipe — let /auth/refresh be the authority.
        }
      }

      final sessionMap = json.decode(sessionJson) as Map<String, dynamic>;
      final session = Session.fromJson(sessionMap);

      // Cache tokens in memory for faster access during this session
      _cachedAccessToken = session.accessToken;
      _cachedRefreshToken = session.refreshToken;

      // Without a refresh token there is nothing to recover with.
      if (session.refreshToken.isEmpty) {
        OrbitNestLogger.error('getStoredSession: empty refresh token — clearing session', null);
        await clearSession();
        return null;
      }

      // Do NOT check refresh-token expiry client-side. The exp claim in a JWT
      // is a hint, not a contract: clock skew, token rotation policies, and
      // server-side session extension can all make a locally-"expired" token
      // still valid. Let the server reject /auth/refresh if the token is truly
      // dead — only then should the session be cleared.

      return session;
    } catch (e) {
      // Transient errors (e.g. iOS secure storage initialising, disk pressure)
      // should not permanently log the user out. Log and return null so the
      // next attempt can succeed.
      OrbitNestLogger.error('getStoredSession: failed to read/decode session', e);
      return null;
    }
  }

  /// Get current access token.
  /// Returns null (rather than an expired token) so callers that need a valid
  /// token either fail fast or trigger the 401 → onError refresh flow instead
  /// of sending a token the backend will reject with "invalid signature" / expired.
  Future<String?> getAccessToken() async {
    try {
      // During sign-out, never trigger a refresh: it would enqueue an event on
      // the AuthBloc that is already blocked awaiting this very request,
      // deadlocking logout. Return the cached token as-is (even if expired) so
      // the /auth/signout call can still proceed.
      if (_isSigningOut) return _cachedAccessToken;
      // Return cached token only if it has not expired yet.
      final stale = _cachedAccessToken;
      if (stale != null) {
        if (!isTokenExpired(stale)) {
          return stale;
        }
        _cachedAccessToken = null;
      }
      // Fall through to secure storage — maybe a refresh already wrote a new one.
      final token = await _secureStorage.read(key: OrbitNestConstants.accessTokenKey);
      if (token != null && !isTokenExpired(token)) {
        _cachedAccessToken = token;
        return token;
      }
      // Both expired: refresh proactively so callers get a valid token. Every
      // concurrent caller awaits the same de-duplicated refresh — returning
      // null here would send the anon key and run the call as the anonymous
      // role. (/auth/refresh skips onRequest, so this can't re-enter itself.)
      if (_refreshCallback != null) {
        final refreshed = await refreshSession();
        if (refreshed) {
          final newToken = _cachedAccessToken ??
              await _secureStorage.read(key: OrbitNestConstants.accessTokenKey);
          if (newToken != null && !isTokenExpired(newToken)) {
            _cachedAccessToken = newToken;
            return newToken;
          }
        } else if (_lastRefreshFailedTransiently) {
          // Offline / 5xx: keep sending the old token so the call fails with
          // 401 instead of silently downgrading the signed-in user to anon.
          return stale ?? token;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get current refresh token
  Future<String?> getRefreshToken() async {
    try {
      // Return cached token if available
      if (_cachedRefreshToken != null) {
        return _cachedRefreshToken;
      }
      // Otherwise read from secure storage and cache it
      final token = await _secureStorage.read(key: OrbitNestConstants.refreshTokenKey);
      if (token != null) {
        _cachedRefreshToken = token;
      }
      return token;
    } catch (e) {
      return null;
    }
  }

  /// Get API key
  Future<String?> getApiKey() async {
    if (_apiKey != null) return _apiKey;

    try {
      return await _secureStorage.read(key: OrbitNestConstants.apiKeyKey);
    } catch (e) {
      return null;
    }
  }

  /// Store API key
  Future<void> storeApiKey(String apiKey) async {
    try {
      await _secureStorage.write(
        key: OrbitNestConstants.apiKeyKey,
        value: apiKey,
      );
    } catch (e) {
      throw Exception('Failed to store API key: $e');
    }
  }

  /// Mark that a sign-out is in progress so getAccessToken() skips the
  /// proactive refresh that would otherwise deadlock against the AuthBloc.
  /// Cleared automatically by clearSession() once sign-out completes.
  void markSigningOut() => _isSigningOut = true;

  /// Clear all stored authentication data
  Future<void> clearSession() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: OrbitNestConstants.sessionKey),
        _secureStorage.delete(key: OrbitNestConstants.accessTokenKey),
        _secureStorage.delete(key: OrbitNestConstants.refreshTokenKey),
      ]);

      // Clear cached tokens
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
    } catch (e) {
      // Ignore errors when clearing
    } finally {
      // Sign-out is done — a later sign-in must be able to refresh again.
      _isSigningOut = false;
    }
  }

  /// Check if token is expired
  bool isTokenExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (e) {
      // If we can't decode the token, consider it expired
      return true;
    }
  }

  /// Check if token will expire within the given duration
  bool isTokenExpiringWithin(String token, Duration duration) {
    try {
      final expirationDate = JwtDecoder.getExpirationDate(token);
      final now = DateTime.now();
      final timeUntilExpiration = expirationDate.difference(now);
      return timeUntilExpiration <= duration;
    } catch (e) {
      // If we can't decode the token, consider it expiring
      return true;
    }
  }

  /// Get token expiration time
  DateTime? getTokenExpirationTime(String token) {
    try {
      return JwtDecoder.getExpirationDate(token);
    } catch (e) {
      return null;
    }
  }

  /// Decode token payload
  Map<String, dynamic>? decodeToken(String token) {
    try {
      return JwtDecoder.decode(token);
    } catch (e) {
      return null;
    }
  }

  /// Extract user ID from token
  String? getUserIdFromToken(String token) {
    try {
      final payload = JwtDecoder.decode(token);
      return payload['sub'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Extract user email from token
  String? getUserEmailFromToken(String token) {
    try {
      final payload = JwtDecoder.decode(token);
      return payload['email'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Check if session needs refresh
  Future<bool> shouldRefreshSession() async {
    final session = await getStoredSession();
    if (session == null) return false;

    // Check if session is expired or expiring within threshold
    return session.isExpired ||
        session.isExpiringWithin(const Duration(minutes: 5));
  }

  /// Refresh session callback - should be set by AuthBloc
  Future<bool> Function()? _refreshCallback;

  /// In-flight refresh – deduplicate concurrent callers so only one HTTP
  /// request to /auth/refresh is made at a time.
  Future<bool>? _pendingRefresh;

  /// Set the refresh callback (called by AuthBloc during initialization)
  void setRefreshCallback(Future<bool> Function() callback) {
    _refreshCallback = callback;
  }

  /// True when the last [refreshSession] that returned false failed for a
  /// transient reason (offline, timeout, 5xx) rather than the server rejecting
  /// the refresh token. Callers must keep the stored session in that case.
  bool get lastRefreshFailedTransiently => _lastRefreshFailedTransiently;
  bool _lastRefreshFailedTransiently = false;

  /// Refresh session using the registered callback.
  /// If a refresh is already in progress, the caller awaits the same Future
  /// instead of firing a second HTTP request.
  ///
  /// The callback returns false when the server rejected the refresh token and
  /// throws on transient failures; both resolve to false here, and
  /// [lastRefreshFailedTransiently] tells them apart.
  Future<bool> refreshSession() {
    if (_refreshCallback == null) return Future.value(false);
    return _pendingRefresh ??=
        _runRefresh().whenComplete(() => _pendingRefresh = null);
  }

  Future<bool> _runRefresh() async {
    try {
      final ok = await _refreshCallback!();
      _lastRefreshFailedTransiently = false;
      return ok;
    } catch (e) {
      OrbitNestLogger.error('Token refresh failed (transient)', e);
      _lastRefreshFailedTransiently = true;
      return false;
    }
  }

  /// Store project slug
  Future<void> storeProjectInfo({String? projectSlug}) async {
    try {
      if (projectSlug != null) {
        await _secureStorage.write(
          key: OrbitNestConstants.projectSlugKey,
          value: projectSlug,
        );
      }
    } catch (e) {
      throw Exception('Failed to store project info: $e');
    }
  }

  /// Get stored project slug
  Future<String?> getProjectSlug() async {
    if (_projectSlug != null) return _projectSlug;

    try {
      return await _secureStorage.read(key: OrbitNestConstants.projectSlugKey);
    } catch (e) {
      return null;
    }
  }

  /// Clear all stored data
  Future<void> clearAll() async {
    try {
      await _secureStorage.deleteAll();

      // Clear cached tokens
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
    } catch (e) {
      // Ignore errors when clearing all
    }
  }

  /// Generate checksum for data integrity verification
  String _generateChecksum(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Check if token is about to expire and needs refresh
  bool needsRefresh(String token) {
    return isTokenExpiringWithin(
      token,
      const Duration(minutes: _refreshThresholdMinutes),
    );
  }

  /// Validate API key format
  bool isValidApiKey(String? apiKey) {
    if (apiKey == null || apiKey.isEmpty) return false;

    // Basic API key validation - should be at least 32 characters
    if (apiKey.length < 32) return false;

    // Should contain only alphanumeric characters and some special chars
    final validChars = RegExp(r'^[a-zA-Z0-9\-_.]+$');
    return validChars.hasMatch(apiKey);
  }
}
