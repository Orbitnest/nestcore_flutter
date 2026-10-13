// Session-lifecycle regressions:
//  B-08  offline / 5xx refresh must not wipe the stored session
//  B-18  plain 401s (anonymous, analytics, transient refresh) must not fire onSessionExpired
//  B-13  resetPassword() resolves instead of throwing a null-check error
//  B-14  verifySmsOtp() updates auth state
//  B-19/20 getUser()/refreshSession() throw instead of hanging when signed out
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbitnest_studio_flutter/src/auth/bloc/auth_bloc.dart';
import 'package:orbitnest_studio_flutter/src/auth/bloc/auth_event.dart';
import 'package:orbitnest_studio_flutter/src/auth/bloc/auth_state.dart';
import 'package:orbitnest_studio_flutter/src/auth/exceptions/auth_exception.dart';
import 'package:orbitnest_studio_flutter/src/auth/models/auth_response.dart';
import 'package:orbitnest_studio_flutter/src/auth/models/session.dart';
import 'package:orbitnest_studio_flutter/src/auth/models/user.dart';
import 'package:orbitnest_studio_flutter/src/auth/orbitnest_auth.dart';
import 'package:orbitnest_studio_flutter/src/auth/repositories/auth_repository.dart';
import 'package:orbitnest_studio_flutter/src/auth/services/auth_service.dart';
import 'package:orbitnest_studio_flutter/src/auth/services/token_manager.dart';
import 'package:orbitnest_studio_flutter/src/client/interceptors/auth_interceptor.dart';
import 'package:orbitnest_studio_flutter/src/client/interceptors/error_interceptor.dart';
import 'package:orbitnest_studio_flutter/src/client/interceptors/retry_interceptor.dart';
import 'package:orbitnest_studio_flutter/src/constants/constants.dart';
import 'package:orbitnest_studio_flutter/src/database/exceptions/database_exception.dart';
import 'package:orbitnest_studio_flutter/src/edge_functions/exceptions/function_exception.dart';

/// TokenManager without secure storage.
class _Tm extends TokenManager {
  _Tm({this.refreshToken = 'rt'}) : super(apiKey: 'anon');
  String? refreshToken;
  int clears = 0;
  int expiredSignals = 0;

  @override
  Future<String?> getRefreshToken() async => refreshToken;
  @override
  Future<Session?> getStoredSession() async => null;
  @override
  Future<String?> getAccessToken() async => null;
  @override
  Future<void> storeSession(Session session) async {}
  @override
  Future<void> clearSession() async => clears++;
  @override
  void notifySessionExpired() => expiredSignals++;
}

/// Repository stub; [refreshError] decides how /auth/refresh fails.
class _Repo implements AuthRepository {
  Object refreshError = const AuthException('offline', code: 'CONNECTION_ERROR');

  @override
  Future<AuthResponse> refreshSession({required String refreshToken}) async =>
      throw refreshError;

  @override
  Future<User?> getUser() async => null; // signed out

  @override
  Future<AuthResponse> updatePassword(
          {required String email, required String token, required String password}) async =>
      AuthResponse.fromJson(
          {'success': true, 'message': 'Password has been reset. Please sign in with your new password.'});

  @override
  Future<AuthResponse> verifySmsOtp({required String phone, required String code}) async =>
      AuthResponse.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'user': {'id': 'u1', 'email': 'p@sms.local'},
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Svc implements AuthService {
  int deletes = 0;
  @override
  Future<void> deleteUser() async => deletes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ErrHandler extends ErrorInterceptorHandler {
  DioException? passed;
  @override
  void next(DioException err) => passed = err;
  @override
  void reject(DioException err) => passed = err;
}

DioException _unauthorized(String path) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response(requestOptions: RequestOptions(path: path), statusCode: 401),
      type: DioExceptionType.badResponse,
    );

/// TokenManager whose refresh outcome is scripted.
class _ScriptedTm extends _Tm {
  _ScriptedTm({super.refreshToken, required this.transient});
  final bool transient;
  int refreshes = 0;
  @override
  Future<bool> refreshSession() async {
    refreshes++;
    return false;
  }

  @override
  bool get lastRefreshFailedTransiently => transient;
}

void main() {
  group('TokenManager.refreshSession', () {
    test('a throwing refresh is reported as transient; false is a rejection', () async {
      final tm = TokenManager();
      tm.setRefreshCallback(() async => throw const AuthException('offline'));
      expect(await tm.refreshSession(), isFalse);
      expect(tm.lastRefreshFailedTransiently, isTrue);

      tm.setRefreshCallback(() async => false);
      expect(await tm.refreshSession(), isFalse);
      expect(tm.lastRefreshFailedTransiently, isFalse);
    });
  });

  group('AuthInterceptor 401 handling (B-18, B-09)', () {
    test('anonymous 401 is passed to the caller without refresh or expiry', () async {
      final tm = _ScriptedTm(refreshToken: null, transient: false);
      final h = _ErrHandler();
      await AuthInterceptor(tm).onError(_unauthorized('/api/project/p/database/tables/t/rows/bulk'), h);
      expect(h.passed, isNotNull);
      expect(tm.refreshes, 0);
      expect(tm.expiredSignals, 0);
    });

    test('analytics 401 never refreshes or expires the session', () async {
      final tm = _ScriptedTm(transient: false);
      final h = _ErrHandler();
      await AuthInterceptor(tm).onError(_unauthorized('https://api.x/api/analytics/events'), h);
      expect(tm.refreshes, 0);
      expect(tm.expiredSignals, 0);
    });

    test('a 401 from /auth/refresh itself does not recurse into refresh', () async {
      final tm = _ScriptedTm(transient: false);
      final h = _ErrHandler();
      await AuthInterceptor(tm).onError(_unauthorized('/api/projects/p/auth/refresh'), h);
      expect(tm.refreshes, 0);
      expect(h.passed, isNotNull);
    });

    test('a transient refresh failure keeps the session', () async {
      final tm = _ScriptedTm(transient: true);
      final h = _ErrHandler();
      await AuthInterceptor(tm).onError(_unauthorized('/api/project/p/functions/v1/f'), h);
      expect(tm.refreshes, 1);
      expect(tm.expiredSignals, 0);
      expect(h.passed, isNotNull);
    });

    test('a rejected refresh token signals session expiry', () async {
      final tm = _ScriptedTm(transient: false);
      await AuthInterceptor(tm).onError(_unauthorized('/api/project/p/functions/v1/f'), _ErrHandler());
      expect(tm.expiredSignals, 1);
    });
  });

  group('AuthBloc refresh (B-08)', () {
    late _Tm tm;
    late _Repo repo;
    late AuthBloc bloc;

    setUp(() async {
      tm = _Tm();
      repo = _Repo();
      bloc = AuthBloc(authRepository: repo, tokenManager: tm);
      await bloc.stream.firstWhere((s) => s is AuthUnauthenticatedState); // init done
    });
    tearDown(() => bloc.close());

    test('network failure keeps the stored session', () async {
      final next = bloc.stream.firstWhere((s) => s is! AuthLoadingState);
      bloc.add(const AuthRefreshSessionEvent());
      final state = await next;
      expect(state, isA<AuthErrorState>());
      expect((state as AuthErrorState).code, 'REFRESH_FAILED');
      expect(tm.clears, 0);
    });

    test('a 5xx keeps the stored session', () async {
      repo.refreshError = const AuthException('down', statusCode: 503);
      expect(await tm.refreshSession(), isFalse);
      expect(tm.lastRefreshFailedTransiently, isTrue);
    });

    test('a rejected refresh token clears it', () async {
      repo.refreshError = const AuthException('revoked', statusCode: 401);
      final next = bloc.stream.firstWhere((s) => s is! AuthLoadingState);
      bloc.add(const AuthRefreshSessionEvent());
      expect(await next, isA<AuthUnauthenticatedState>());
      expect(tm.clears, 1);
    });

    test('a silent (cold start) network failure emits nothing', () async {
      final emitted = <AuthState>[];
      final sub = bloc.stream.listen(emitted.add);
      bloc.add(const AuthRefreshSessionEvent(silent: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(emitted, isEmpty);
      expect(tm.clears, 0);
    });
  });

  group('OrbitNestAuth', () {
    late _Tm tm;
    late _Repo repo;
    late AuthBloc bloc;
    late OrbitNestAuth auth;
    late _Svc svc;

    setUp(() async {
      tm = _Tm();
      repo = _Repo();
      bloc = AuthBloc(authRepository: repo, tokenManager: tm);
      svc = _Svc();
      auth = OrbitNestAuth(bloc, svc, tm);
      await bloc.stream.firstWhere((s) => s is AuthUnauthenticatedState);
    });
    tearDown(() => bloc.close());

    test('resetPassword() resolves with the server message (B-13)', () async {
      final res = await auth
          .resetPassword(email: 'a@b.c', token: '1234', newPassword: 'newpass123')
          .timeout(const Duration(seconds: 2));
      expect(res['message'], contains('Password has been reset'));
    });

    test('verifySmsOtp() signs the user in (B-14)', () async {
      final res = await auth
          .verifySmsOtp(phone: '+15555550123', code: '123456')
          .timeout(const Duration(seconds: 2));
      expect(res['user'], isNotNull);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.id, 'u1');
    });

    test('getUser() throws instead of hanging when signed out (B-19)', () async {
      await expectLater(
        auth.getUser().timeout(const Duration(seconds: 2)),
        throwsA(isA<AuthException>()),
      );
    });

    test('deleteUser() deletes the account and clears the local session', () async {
      await auth.deleteUser();
      expect(svc.deletes, 1);
      expect(tm.clears, 1);
    });

    test('refreshSession() throws instead of hanging (B-20)', () async {
      repo.refreshError = const AuthException('revoked', statusCode: 401);
      await expectLater(
        auth.refreshSession().timeout(const Duration(seconds: 2)),
        throwsA(isA<AuthException>()),
      );
    });
  });

  test('ErrorInterceptor joins NestJS validation message lists (B-29)', () {
    final h = _ErrHandler();
    ErrorInterceptor().onError(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 400,
          data: {
            'message': ['a should not exist', 'b must be a string']
          },
        ),
      ),
      h,
    );
    expect((h.passed!.error as OrbitNestException).message,
        'a should not exist, b must be a string');
  });

  test('RetryInterceptor does not re-send a FormData body (B-31)', () async {
    final h = _ErrHandler();
    final err = DioException(
      requestOptions: RequestOptions(path: '/upload', data: FormData()),
      type: DioExceptionType.connectionError,
    );
    await RetryInterceptor().onError(err, h);
    expect(identical(h.passed, err), isTrue);
  });

  DioException apiError(int status, Map<String, dynamic> body) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: status, data: body),
      );

  test('structured API errors keep code, message and body', () {
    final h = _ErrHandler();
    ErrorInterceptor().onError(
      apiError(402, {
        'statusCode': 402,
        'code': 'QUOTA_EXCEEDED',
        'quota': 'functions',
        'plan': 'free',
        'limit': 2,
        'usage': 2,
        'message': 'Function limit reached',
      }),
      h,
    );
    final db = DatabaseException.fromException(h.passed);
    expect(db.code, 'QUOTA_EXCEEDED');
    expect(db.statusCode, 402);
    expect(db.message, 'Function limit reached');
    expect(db.body!['plan'], 'free');
    final fn = FunctionException.fromException(h.passed);
    expect(fn.code, 'QUOTA_EXCEEDED');
    expect(fn.body!['limit'], 2);

    final h2 = _ErrHandler();
    ErrorInterceptor().onError(
        apiError(403, {'code': 'MFA_ENROLLMENT_REQUIRED', 'message': 'Set up 2FA'}), h2);
    final auth = AuthException.fromException(h2.passed);
    expect(auth.code, 'MFA_ENROLLMENT_REQUIRED');
    expect(auth.message, 'Set up 2FA');
  });

  test('a coded 429 (SMS_RATE_LIMITED) is not retried', () async {
    final coded = apiError(429, {'code': 'SMS_RATE_LIMITED', 'message': 'Too many codes'});
    final h = _ErrHandler();
    await RetryInterceptor().onError(coded, h);
    expect(identical(h.passed, coded), isTrue);
  });

  test('402/403/429 never refresh or end the session', () async {
    for (final status in [402, 403, 429]) {
      final tm = _ScriptedTm(transient: false);
      final h = _ErrHandler();
      await AuthInterceptor(tm).onError(apiError(status, {'code': 'X', 'message': 'm'}), h);
      expect(tm.refreshes, 0);
      expect(tm.expiredSignals, 0);
      expect(h.passed, isNotNull);
    }
  });

  test('client version matches pubspec (B-28)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(OrbitNestConstants.version, version);
  });
}
