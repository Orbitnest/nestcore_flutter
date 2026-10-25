// 1.9.0 OrbitNest -> NestCore rename: the old names, import path, env vars and
// secure-storage keys must keep working for apps updating from
// orbitnest_studio_flutter.
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/nestcore_flutter.dart';
import 'package:nestcore_flutter/orbitnest_studio_flutter.dart' as legacy;
import 'package:nestcore_flutter/src/auth/services/token_manager.dart';

// Minimal JWT with payload {"role":"anon","project_slug":"test-project"}
const _anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJyb2xlIjoiYW5vbiIsInByb2plY3Rfc2x1ZyI6InRlc3QtcHJvamVjdCJ9'
    '.fake-signature';

String _jwt(String sub, Duration ttl) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(ttl).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'HS256'})}.${b64({'sub': sub, 'exp': exp})}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => EnvConfig.initialize());

  group('deprecated OrbitNest* aliases', () {
    test('are the same types as the NestCore* classes', () {
      expect(OrbitNestClient, NestCoreClient);
      expect(OrbitNestAuth, NestCoreAuth);
      expect(OrbitNestDatabase, NestCoreDatabase);
      expect(OrbitNestFunctions, NestCoreFunctions);
      expect(OrbitNestRealtime, NestCoreRealtime);
      expect(OrbitNestStorage, NestCoreStorage);
      expect(OrbitNestAi, NestCoreAi);
      expect(OrbitNestMemory, NestCoreMemory);
      expect(OrbitNestCollections, NestCoreCollections);
      expect(OrbitNestException, NestCoreException);
      expect(OrbitNestConstants, NestCoreConstants);
      expect(OrbitNestLogger, NestCoreLogger);
    });

    test('factories, constructors and static members work through them', () {
      FlutterSecureStorage.setMockInitialValues({});
      final OrbitNestClient client = OrbitNestClient.create(anonKey: _anonKey);
      expect(client, isA<NestCoreClient>());
      expect(client.projectSlug, 'test-project');
      final OrbitNestAuth auth = client.auth;
      expect(auth, isA<NestCoreAuth>());
      client.dispose();

      const e = OrbitNestException('boom', code: 'X', statusCode: 400);
      expect(e, isA<NestCoreException>());
      expect(e.toString(), 'NestCoreException(X): boom');
      try {
        throw const NestCoreException('caught');
      } on OrbitNestException catch (caught) {
        expect(caught.message, 'caught');
      }

      expect(OrbitNestConstants.version, NestCoreConstants.version);
      OrbitNestLogger.debug('alias logger call compiles');
    });

    test('the old library path re-exports the package', () {
      final legacy.NestCoreClient client =
          legacy.OrbitNestClient.create(anonKey: _anonKey);
      expect(client.baseUrl, 'https://api.nestcore.io');
      client.dispose();
    });
  });

  group('env variables', () {
    tearDown(() => dotenv.testLoad(fileInput: ''));

    test('legacy ORBITNEST_* names are still read', () {
      dotenv.testLoad(
          fileInput: 'ORBITNEST_ANON_KEY=$_anonKey\nORBITNEST_DEBUG=true\n'
              'ORBITNEST_API_TIMEOUT=1234');
      expect(EnvConfig.anonKey, _anonKey);
      expect(EnvConfig.isDebugMode, isTrue);
      expect(EnvConfig.apiTimeout, 1234);
      expect(EnvConfig.projectSlug, 'test-project');
    });

    test('NESTCORE_* wins over ORBITNEST_*', () {
      dotenv.testLoad(
          fileInput: 'NESTCORE_API_URL=http://localhost:3002\n'
              'ORBITNEST_API_URL=http://localhost:9999\n'
              'NESTCORE_DEBUG=false\nORBITNEST_DEBUG=true');
      expect(EnvConfig.baseUrl, contains(':3002'));
      expect(EnvConfig.isDebugMode, isFalse);
    });

    test('default base URL is api.nestcore.io', () {
      expect(EnvConfig.baseUrl, 'https://api.nestcore.io');
    });
  });

  group('secure-storage key migration', () {
    const storage = FlutterSecureStorage();

    Map<String, String> legacySession(String access) {
      final sessionJson = jsonEncode({
        'access_token': access,
        'refresh_token': 'legacy-rt',
        'expires_in': 900,
        'token_type': 'Bearer',
        'user': {'id': 'u1', 'email': 'a@b.c'},
      });
      return {
        'orbitnest_session': sessionJson,
        'orbitnest_access_token': access,
        'orbitnest_refresh_token': 'legacy-rt',
        'orbitnest_api_key': 'legacy-anon',
        'orbitnest_project_slug': 'legacy-slug',
      };
    }

    test('a session stored under orbitnest_* keys is restored and moved', () async {
      final access = _jwt('u1', const Duration(minutes: 15));
      FlutterSecureStorage.setMockInitialValues(legacySession(access));
      final tm = TokenManager();

      final session = await tm.getStoredSession();
      expect(session, isNotNull);
      expect(session!.accessToken, access);
      expect(session.refreshToken, 'legacy-rt');
      expect(await tm.getRefreshToken(), 'legacy-rt');
      expect(await tm.getApiKey(), 'legacy-anon');
      expect(await tm.getProjectSlug(), 'legacy-slug');

      // A fresh TokenManager (cold start) reads the migrated keys.
      expect(await TokenManager().getAccessToken(), access);

      final all = await storage.readAll();
      expect(all['nestcore_session'], isNotNull);
      expect(all['nestcore_access_token'], access);
      expect(all['nestcore_refresh_token'], 'legacy-rt');
      expect(all['nestcore_api_key'], 'legacy-anon');
      expect(all['nestcore_project_slug'], 'legacy-slug');
      expect(all.keys.where((k) => k.startsWith('orbitnest_')), isEmpty);
    });

    test('new keys win over leftover legacy keys', () async {
      FlutterSecureStorage.setMockInitialValues({
        ...legacySession('old'),
        'nestcore_refresh_token': 'new-rt',
      });
      expect(await TokenManager().getRefreshToken(), 'new-rt');
    });

    test('signing out clears the legacy session keys too', () async {
      FlutterSecureStorage.setMockInitialValues(
          legacySession(_jwt('u1', const Duration(minutes: 15))));
      await TokenManager().clearSession();
      expect(await TokenManager().getStoredSession(), isNull);
      expect(await TokenManager().getRefreshToken(), isNull);
    });
  });
}
