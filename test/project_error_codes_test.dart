import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/nestcore_flutter.dart';

void main() {
  test('NestCoreException names a paused project and keeps the upgrade link', () {
    const paused = NestCoreException('This project is paused.', code: ErrorCodes.projectPaused, statusCode: 423);
    expect(paused.isProjectPaused, isTrue);
    expect(paused.upgradeUrl, isNull);

    const quota = NestCoreException(
      'Your free plan includes 1 project: an app or an agent.',
      code: ErrorCodes.quotaExceeded,
      statusCode: 402,
      body: {'quota': 'projects', 'kind': 'agent', 'reason': 'project_limit', 'upgradeUrl': 'https://nestcore.io/settings/billing?ref=agent'},
    );
    expect(quota.isProjectPaused, isFalse);
    expect(quota.upgradeUrl, 'https://nestcore.io/settings/billing?ref=agent');

    expect(ErrorCodes.agentProjectRestricted, 'AGENT_PROJECT_RESTRICTED');
    expect(ErrorCodes.notAnAgentProject, 'NOT_AN_AGENT_PROJECT');
  });
}
