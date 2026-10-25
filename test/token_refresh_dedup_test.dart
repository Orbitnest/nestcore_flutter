// Regression test for the refresh-rotation race that logged freshly-registered
// users out on cold restart.
//
// The backend rotates refresh tokens single-use: two parallel /auth/refresh
// calls with the same token make one win and one 401. The fix routes every
// refresh path (interceptor 401-retry, proactive getAccessToken, and the
// AuthBloc's _onRefreshSession) through TokenManager.refreshSession(), which
// de-duplicates concurrent callers onto a single in-flight request. This test
// pins that de-duplication so a regression can't silently reintroduce the race.
//
// refreshSession() only touches the registered callback + the in-flight guard
// (no secure storage / platform channels), so it runs as a plain unit test.
import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/src/auth/services/token_manager.dart';

void main() {
  group('TokenManager.refreshSession de-duplication', () {
    test('concurrent callers share a single underlying refresh', () async {
      final tm = TokenManager();
      var callCount = 0;

      tm.setRefreshCallback(() async {
        callCount++;
        // Hold the refresh open so all three callers overlap.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return true;
      });

      final results = await Future.wait([
        tm.refreshSession(),
        tm.refreshSession(),
        tm.refreshSession(),
      ]);

      expect(callCount, 1, reason: 'only one /auth/refresh should be issued');
      expect(results, everyElement(isTrue));
    });

    test('a later refresh issues a new request once the first settled', () async {
      final tm = TokenManager();
      var callCount = 0;

      tm.setRefreshCallback(() async {
        callCount++;
        return true;
      });

      await tm.refreshSession();
      await tm.refreshSession();

      expect(callCount, 2, reason: 'sequential refreshes are not de-duplicated');
    });

    test('a failing refresh resolves all concurrent callers to false', () async {
      final tm = TokenManager();
      var callCount = 0;

      tm.setRefreshCallback(() async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return false;
      });

      final results = await Future.wait([
        tm.refreshSession(),
        tm.refreshSession(),
      ]);

      expect(callCount, 1);
      expect(results, everyElement(isFalse));
    });
  });
}
