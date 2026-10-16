import 'package:dio/dio.dart';
import '../../auth/services/token_manager.dart';

/// Credentials for a project request: the anon key identifies the project
/// (`apikey`); the Bearer is the user's access token when signed in, else the
/// anon key.
Future<Map<String, String>> projectAuthHeaders(TokenManager tokenManager) async {
  final apiKey = await tokenManager.getApiKey();
  final token = await tokenManager.getAccessToken() ?? apiKey;
  return {
    if (apiKey != null) 'apikey': apiKey,
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

/// Interceptor for handling authentication tokens
class AuthInterceptor extends Interceptor {
  final TokenManager _tokenManager;

  AuthInterceptor(this._tokenManager);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      // Auth endpoints don't need tokens
      if (_isAuthEndpoint(options.path)) {
        handler.next(options);
        return;
      }

      options.headers.addAll(await projectAuthHeaders(_tokenManager));

      handler.next(options);
    } catch (_) {
      // Best-effort — let the request through without auth headers
      handler.next(options);
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // A 401 on analytics is never a session problem (and analytics must not
    // rotate refresh tokens or log anyone out).
    // Auth endpoints (sign-in, /auth/refresh itself) are skipped too: a 401
    // there is a wrong credential, and refreshing from inside the refresh
    // request would await its own in-flight future forever.
    if (err.response?.statusCode != 401 ||
        err.requestOptions.path.contains('/api/analytics/') ||
        _isAuthEndpoint(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    // No user session (anonymous caller): a 401 is a plain authorization
    // error for the caller, not an expired session.
    final refreshToken = await _tokenManager.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      handler.next(err);
      return;
    }

    // A concurrent call may already have refreshed: reuse its token instead of
    // rotating the refresh token again.
    final sent = err.requestOptions.headers['Authorization'];
    var token = await _tokenManager.getAccessToken();
    if (token == null || 'Bearer $token' == sent) {
      final refreshed = await _tokenManager.refreshSession();
      if (!refreshed) {
        // Only a refresh the server rejected ends the session; offline / 5xx
        // keeps it so the next request can try again.
        if (!_tokenManager.lastRefreshFailedTransiently) {
          _tokenManager.notifySessionExpired();
        }
        handler.next(err);
        return;
      }
      token = await _tokenManager.getAccessToken();
    }

    final apiKey = await _tokenManager.getApiKey();
    if (token == null || 'Bearer $token' == sent) {
      handler.next(err);
      return;
    }
    err.requestOptions.headers['Authorization'] = 'Bearer $token';
    if (apiKey != null) err.requestOptions.headers['apikey'] = apiKey;

    // Retry once on a bare Dio (no interceptors → no refresh loop) with the
    // original options, so responseType (byte downloads), contentType and the
    // no-redirect hardening carry over. A sent FormData is finalized: clone it.
    final data = err.requestOptions.data;
    try {
      final response = await Dio().fetch<dynamic>(err.requestOptions
          .copyWith(data: data is FormData ? data.clone() : data));
      handler.resolve(response);
    } on DioException catch (retryErr) {
      // A fresh token that still gets 401/403 means "not allowed", not
      // "session expired" — surface it to the caller without logging out.
      handler.next(retryErr);
    }
  }

  bool _isAuthEndpoint(String path) {
    // Public auth operations that authenticate via the request body (OTP,
    // credentials, or a refresh token) rather than a Bearer access token —
    // the interceptor must NOT attach a token to these.
    //
    // '/auth/refresh' is critical here: the server route is unguarded and
    // authenticates off the refresh_token in the body, so it needs no Bearer.
    // If it is NOT skipped, onRequest calls getAccessToken() for the refresh
    // POST; on a cold start the access token is already expired, so
    // getAccessToken() kicks off a *proactive* refresh which re-enters
    // refreshSession() and awaits the very in-flight refresh future this POST
    // belongs to — a self-deadlock that hangs the request until it fails and
    // the session is cleared. That is the "logged out on every restart after
    // 15 min" bug: the access token (15-min TTL) expires while the app is
    // backgrounded, and the cold-start refresh can never complete.
    //
    // Use specific paths, never broad prefixes like '/api/projects/', so
    // genuinely authenticated endpoints (e.g. '/auth/user') still get a token.
    const authPaths = [
      '/auth/signin',
      '/auth/signup',
      '/auth/verify-signup',
      '/auth/verify',
      '/auth/recover',
      '/auth/reset-password',
      '/auth/refresh',
    ];

    return authPaths.any((authPath) => path.contains(authPath));
  }
}
