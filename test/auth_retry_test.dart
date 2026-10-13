// 401 refresh-and-retry and token freshness (SDK auth sweep):
//  - concurrent getAccessToken() callers share one refresh instead of one of
//    them falling back to the anon key (RLS would see no user)
//  - a transient refresh failure keeps the user token (no silent anon)
//  - the 401 retry keeps responseType / FormData and skips a second refresh
//    when another call already rotated the token
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbitnest_studio_flutter/src/auth/models/session.dart';
import 'package:orbitnest_studio_flutter/src/auth/models/user.dart';
import 'package:orbitnest_studio_flutter/src/auth/services/token_manager.dart';
import 'package:orbitnest_studio_flutter/src/client/interceptors/auth_interceptor.dart';

String _jwt(String sub, Duration ttl) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(ttl).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'HS256'})}.${b64({'sub': sub, 'exp': exp})}.sig';
}

Session _session(String token) => Session(
      accessToken: token,
      refreshToken: 'rt',
      expiresIn: 900,
      tokenType: 'Bearer',
      user: User.fromJson({'id': 'u1', 'email': 'a@b.c'}),
    );

class _ResolveHandler extends ErrorInterceptorHandler {
  Response<dynamic>? resolved;
  DioException? passed;
  @override
  void resolve(Response response) => resolved = response;
  @override
  void next(DioException err) => passed = err;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('TokenManager.getAccessToken', () {
    test('concurrent callers with an expired token share one refresh', () async {
      final tm = TokenManager(apiKey: 'anon');
      await tm.storeSession(_session(_jwt('u1', const Duration(minutes: -1))));
      final fresh = _jwt('u1', const Duration(minutes: 15));
      var refreshes = 0;
      tm.setRefreshCallback(() async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tm.storeSession(_session(fresh));
        return true;
      });

      final tokens = await Future.wait([tm.getAccessToken(), tm.getAccessToken()]);

      expect(refreshes, 1);
      expect(tokens, everyElement(fresh),
          reason: 'no caller may fall back to the anon key mid-refresh');
    });

    test('a transient refresh failure keeps sending the user token', () async {
      final tm = TokenManager(apiKey: 'anon');
      final expired = _jwt('u1', const Duration(minutes: -1));
      await tm.storeSession(_session(expired));
      tm.setRefreshCallback(() async => throw const SocketException('offline'));

      expect(await tm.getAccessToken(), expired);
    });

    test('a rejected refresh returns null', () async {
      final tm = TokenManager(apiKey: 'anon');
      await tm.storeSession(_session(_jwt('u1', const Duration(minutes: -1))));
      tm.setRefreshCallback(() async => false);

      expect(await tm.getAccessToken(), isNull);
    });
  });

  group('AuthInterceptor 401 retry', () {
    late HttpServer server;
    final seen = <String?>[];
    setUp(() async {
      HttpOverrides.global = null; // the test binding fakes every HTTP call as 400
      seen.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        seen.add(req.headers.value('authorization'));
        req.response.headers.contentType = ContentType.binary;
        req.response.add([1, 2, 3]);
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    DioException unauthorized(RequestOptions ro) => DioException(
          requestOptions: ro,
          response: Response(requestOptions: ro, statusCode: 401),
          type: DioExceptionType.badResponse,
        );

    test('reuses a token another call already refreshed; keeps byte responses',
        () async {
      final tm = TokenManager(apiKey: 'anon');
      final fresh = _jwt('u1', const Duration(minutes: 15));
      await tm.storeSession(_session(fresh));
      var refreshes = 0;
      tm.setRefreshCallback(() async {
        refreshes++;
        return true;
      });
      final ro = RequestOptions(
        baseUrl: 'http://127.0.0.1:${server.port}',
        path: '/api/project/p/storage/b/download/a.png',
        responseType: ResponseType.bytes,
        headers: {'Authorization': 'Bearer OLD', 'apikey': 'anon'},
      );
      final h = _ResolveHandler();

      await AuthInterceptor(tm).onError(unauthorized(ro), h);

      expect(refreshes, 0, reason: 'token already rotated by another call');
      expect(seen.single, 'Bearer $fresh');
      expect(h.resolved?.data, isA<List<int>>());
      expect(h.resolved?.data, [1, 2, 3]);
    });

    test('refreshes once and re-sends a (finalized) FormData upload', () async {
      final tm = TokenManager(apiKey: 'anon');
      final stale = _jwt('u1', const Duration(minutes: 15));
      final fresh = _jwt('u1', const Duration(minutes: 16));
      await tm.storeSession(_session(stale));
      tm.setRefreshCallback(() async {
        await tm.storeSession(_session(fresh));
        return true;
      });
      final form = FormData.fromMap(
          {'file': MultipartFile.fromBytes(Uint8List.fromList([9]), filename: 'a')});
      form.finalize(); // the first (rejected) send already consumed it
      final ro = RequestOptions(
        baseUrl: 'http://127.0.0.1:${server.port}',
        path: '/api/project/p/storage/b/upload',
        method: 'POST',
        data: form,
        headers: {'Authorization': 'Bearer $stale', 'apikey': 'anon'},
      );
      final h = _ResolveHandler();

      await AuthInterceptor(tm).onError(unauthorized(ro), h);

      expect(h.passed, isNull);
      expect(seen.single, 'Bearer $fresh');
    });
  });
}
