import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/nestcore_flutter.dart';

void main() {
  const body = {
    'statusCode': 402,
    'code': 'CREDITS_EXHAUSTED',
    'reason': 'spend_cap',
    'message': "This workspace's monthly AI credit cap (\$10) is reached.",
    'balanceUsd': 4.5,
    'monthlyCapUsd': 10,
    'spentThisMonthUsd': 10,
    'buyUrl': 'https://nestcore.io/settings/billing?ref=credits',
  };

  test('NestCoreException names exhausted credit with its reason and buy link', () {
    const e = NestCoreException('cap reached', code: ErrorCodes.creditsExhausted, statusCode: 402, body: body);
    expect(ErrorCodes.creditsExhausted, 'CREDITS_EXHAUSTED');
    expect(e.isCreditsExhausted, isTrue);
    expect(e.creditsReason, 'spend_cap');
    expect(e.buyUrl, 'https://nestcore.io/settings/billing?ref=credits');
    expect(e.isProjectPaused, isFalse);

    const other = NestCoreException('quota', code: ErrorCodes.quotaExceeded, statusCode: 402, body: {'reason': 'project_limit'});
    expect(other.isCreditsExhausted, isFalse);
    expect(other.creditsReason, isNull);
    expect(other.buyUrl, isNull);
  });

  test('AiException and the deprecated OrbitNestException alias expose the same getters', () {
    const ai = AiException('no credit', code: 'CREDITS_EXHAUSTED', statusCode: 402, body: {
      'code': 'CREDITS_EXHAUSTED',
      'reason': 'balance',
      'buyUrl': 'https://nestcore.io/settings/billing?ref=credits',
    });
    expect(ai.isCreditsExhausted, isTrue);
    expect(ai.creditsReason, 'balance');
    expect(ai.buyUrl, isNotNull);

    // ignore: deprecated_member_use_from_same_package
    const OrbitNestException legacy = NestCoreException('no credit', code: 'CREDITS_EXHAUSTED', body: body);
    expect(legacy.isCreditsExhausted, isTrue);
    expect(legacy.creditsReason, 'spend_cap');
  });
}
