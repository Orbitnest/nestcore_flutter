import 'package:flutter_test/flutter_test.dart';
import 'package:orbitnest_studio_flutter/orbitnest_studio_flutter.dart';

void main() {
  test('AuthException names the project auth limit codes', () {
    final locked = AuthException.fromException(
      const OrbitNestException('Too many failed sign-in attempts.', code: 'ACCOUNT_LOCKED', statusCode: 429),
    );
    expect(locked.isAccountLocked, isTrue);
    expect(locked.isTooManyAttempts, isTrue);
    expect(locked.isOtpRateLimited, isFalse);

    const wrongCodes = AuthException('x', code: ErrorCodes.otpRateLimited, statusCode: 429);
    expect(wrongCodes.isOtpRateLimited, isTrue);
    const requests = AuthException('x', code: ErrorCodes.otpRequestLimit, statusCode: 429);
    expect(requests.isOtpRequestLimited, isTrue);
    const other = AuthException('x', code: 'INVALID_CREDENTIALS', statusCode: 401);
    expect(other.isTooManyAttempts, isFalse);
  });
}
