// 1.11.0: session keys are scoped to the project slug, so a Production build
// (`shop`) and a Development build (`shop__dev`) of one app on one device keep
// separate sessions, and sessions saved by SDK < 1.11.0 move over only to the
// project that issued them.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/src/auth/models/session.dart';
import 'package:nestcore_flutter/src/auth/services/token_manager.dart';

String _jwt(String sub, {String? aud, Duration ttl = const Duration(minutes: 15)}) {
  String b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(ttl).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'HS256'})}.${b64({'sub': sub, 'exp': exp, if (aud != null) 'aud': aud, if (aud != null) 'iss': 'nestcore:project:$aud'})}.sig';
}

Map<String, String> _sharedSession(String access, String refresh) => {
      'nestcore_session': jsonEncode({
        'access_token': access,
        'refresh_token': refresh,
        'expires_in': 900,
        'token_type': 'Bearer',
        'user': {'id': 'u1', 'email': 'a@b.c'},
      }),
      'nestcore_access_token': access,
      'nestcore_refresh_token': refresh,
    };

Session _session(String access, String refresh) => Session.fromJson({
      'access_token': access,
      'refresh_token': refresh,
      'expires_in': 900,
      'token_type': 'Bearer',
      'user': {'id': 'u1', 'email': 'a@b.c'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();

  test('a pre-1.11 session of this project moves to its scoped keys', () async {
    final access = _jwt('u1', aud: 'shop');
    FlutterSecureStorage.setMockInitialValues(_sharedSession(access, 'rt-shop'));

    final session = await TokenManager(projectSlug: 'shop').getStoredSession();
    expect(session?.refreshToken, 'rt-shop');

    final all = await storage.readAll();
    expect(all['nestcore_session@shop'], isNotNull);
    expect(all['nestcore_refresh_token@shop'], 'rt-shop');
    expect(all.containsKey('nestcore_session'), isFalse);
    // Cold start reads the scoped keys.
    expect(await TokenManager(projectSlug: 'shop').getRefreshToken(), 'rt-shop');
  });

  test("another branch's session is never adopted", () async {
    final access = _jwt('u1', aud: 'shop');
    FlutterSecureStorage.setMockInitialValues(_sharedSession(access, 'rt-shop'));

    expect(await TokenManager(projectSlug: 'shop__dev').getStoredSession(), isNull);
    expect(await TokenManager(projectSlug: 'shop__dev').getRefreshToken(), isNull);
    // Production's session is still there for the Production build.
    expect((await storage.readAll())['nestcore_refresh_token'], 'rt-shop');
    expect(await TokenManager(projectSlug: 'shop').getRefreshToken(), 'rt-shop');
  });

  test('tokens without aud/iss (older servers) are adopted, so nobody is signed out', () async {
    FlutterSecureStorage.setMockInitialValues(_sharedSession(_jwt('u1'), 'rt-old'));
    expect((await TokenManager(projectSlug: 'shop').getStoredSession())?.refreshToken, 'rt-old');
  });

  test('Production and Development keep separate sessions', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await TokenManager(projectSlug: 'shop').storeSession(_session(_jwt('u1', aud: 'shop'), 'rt-prod'));
    await TokenManager(projectSlug: 'shop__dev').storeSession(_session(_jwt('u1', aud: 'shop__dev'), 'rt-dev'));

    expect(await TokenManager(projectSlug: 'shop').getRefreshToken(), 'rt-prod');
    expect(await TokenManager(projectSlug: 'shop__dev').getRefreshToken(), 'rt-dev');

    await TokenManager(projectSlug: 'shop__dev').clearSession();
    expect(await TokenManager(projectSlug: 'shop__dev').getStoredSession(), isNull);
    expect(await TokenManager(projectSlug: 'shop').getRefreshToken(), 'rt-prod');
  });

  test('signing out removes a leftover shared session of this project', () async {
    final access = _jwt('u1', aud: 'shop');
    FlutterSecureStorage.setMockInitialValues({
      ..._sharedSession(access, 'rt-shared'),
      'nestcore_session@shop': jsonEncode({
        'access_token': access,
        'refresh_token': 'rt-scoped',
        'expires_in': 900,
        'token_type': 'Bearer',
        'user': {'id': 'u1', 'email': 'a@b.c'},
      }),
    });
    await TokenManager(projectSlug: 'shop').clearSession();
    expect(await TokenManager(projectSlug: 'shop').getStoredSession(), isNull);
    expect((await storage.readAll()).containsKey('nestcore_session'), isFalse);
  });
}
