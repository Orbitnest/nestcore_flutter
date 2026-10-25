// Regression test for the "logged out on every restart after 15 min" bug.
//
// The /auth/refresh route is unguarded server-side and authenticates off the
// refresh_token in the request body — it needs no Bearer access token. The
// AuthInterceptor must therefore treat it as a token-less auth endpoint and
// short-circuit in onRequest WITHOUT calling TokenManager.getAccessToken().
//
// If it doesn't, the cold-start refresh POST triggers a proactive refresh from
// inside onRequest (the access token is already expired), which re-enters the
// in-flight refresh future the POST itself belongs to and self-deadlocks — the
// refresh never completes and the session is cleared.
//
// We pin the behaviour by routing a '/auth/refresh' request through onRequest
// and asserting it passes straight through with no Authorization header and
// without touching the TokenManager (whose secure-storage reads would throw
// MissingPluginException in a plain unit test — a useful tripwire: if the path
// were ever removed from the skip-list, this test would fail loudly).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/src/auth/services/token_manager.dart';
import 'package:nestcore_flutter/src/client/interceptors/auth_interceptor.dart';

class _CaptureHandler extends RequestInterceptorHandler {
  RequestOptions? captured;
  @override
  void next(RequestOptions requestOptions) {
    captured = requestOptions;
    super.next(requestOptions);
  }
}

void main() {
  test('/auth/refresh is skipped: no token attached, TokenManager untouched',
      () async {
    final interceptor = AuthInterceptor(TokenManager());
    final handler = _CaptureHandler();
    final options =
        RequestOptions(path: '/api/projects/demo/auth/refresh', method: 'POST');

    await interceptor.onRequest(options, handler);

    expect(handler.captured, isNotNull,
        reason: 'auth endpoints must pass straight through');
    expect(handler.captured!.headers['Authorization'], isNull,
        reason: '/auth/refresh must not carry a Bearer access token');
  });
}
