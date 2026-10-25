import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/nestcore_flutter.dart';

// Minimal JWT with payload {"role":"anon","project_slug":"test-project"}
const _testAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJyb2xlIjoiYW5vbiIsInByb2plY3Rfc2x1ZyI6InRlc3QtcHJvamVjdCJ9'
    '.fake-signature';

void main() {
  setUpAll(() async {
    // Initialize without a .env file — still marks as initialized
    await EnvConfig.initialize();
  });

  group('NestCoreClient', () {
    test('decodes project slug from JWT and uses hardcoded base URL', () {
      final client = NestCoreClient.create(anonKey: _testAnonKey);

      expect(client.projectSlug, 'test-project');
      expect(client.baseUrl, EnvConfig.kBaseUrl);
      expect(client.anonKey, _testAnonKey);

      client.dispose();
    });
  });

  group('EnvConfig', () {
    test('decodes project_slug from JWT payload', () {
      final slug = EnvConfig.decodeProjectSlugFromJwt(_testAnonKey);
      expect(slug, 'test-project');
    });

    test('baseUrl returns hardcoded production URL', () {
      expect(EnvConfig.baseUrl, 'https://api.nestcore.io');
    });
  });
}
