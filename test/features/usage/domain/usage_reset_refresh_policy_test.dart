import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_reset_refresh_policy.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);
  UsageQuotaWindow window(
    int minutes,
    DateTime? reset, {
    double? used = 20,
    String limit = 'codex',
    String? reached,
  }) => UsageQuotaWindow(
    limitId: limit,
    windowType: '$minutes',
    windowDurationMinutes: minutes,
    resetsAt: reset,
    usedPercent: used,
    reachedType: reached,
  );

  test('earliest provider reset plus one minute across all windows', () {
    expect(
      UsageResetRefreshPolicy.nextAt([
        window(300, now),
        window(10080, now.add(const Duration(days: 2))),
      ], observedAt: now),
      now.add(const Duration(minutes: 1)),
    );
  });

  test(
    'weekly exhaustion suppresses expired short windows of its limit only',
    () {
      final weekly = window(10080, now.add(const Duration(days: 2)), used: 100);
      expect(
        UsageResetRefreshPolicy.nextAt([
          window(300, now.subtract(const Duration(hours: 4))),
          weekly,
        ], observedAt: now),
        now.add(const Duration(days: 2, minutes: 1)),
      );
      expect(
        UsageResetRefreshPolicy.nextAt([
          window(300, now, limit: 'independent'),
          weekly,
        ], observedAt: now),
        now.add(const Duration(minutes: 1)),
      );
    },
  );

  test(
    'unknown exhausted weekly reset retries hourly, including reached flag',
    () {
      expect(
        UsageResetRefreshPolicy.nextAt([
          window(300, now),
          window(10080, null, used: null, reached: 'rate_limit'),
        ], observedAt: now),
        now.add(const Duration(hours: 1)),
      );
    },
  );

  for (final weeklyUsed in [16.0, 32.0, 61.0]) {
    test(
      'group reached flag cannot block short reset with $weeklyUsed% weekly use',
      () {
        expect(
          UsageResetRefreshPolicy.nextAt([
            window(300, now, used: 100, reached: 'rate_limit_reached'),
            window(
              10080,
              now.add(const Duration(days: 5)),
              used: weeklyUsed,
              reached: 'rate_limit_reached',
            ),
          ], observedAt: now),
          now.add(const Duration(minutes: 1)),
        );
      },
    );
  }

  test('no invented reset for windows without a deadline', () {
    expect(
      UsageResetRefreshPolicy.nextAt([window(300, null)], observedAt: now),
      isNull,
    );
    expect(UsageResetRefreshPolicy.nextAt([], observedAt: now), isNull);
  });

  test('weekly recovery restores short-window scheduling', () {
    expect(
      UsageResetRefreshPolicy.nextAt([
        window(300, now),
        window(10080, now.add(const Duration(days: 7)), used: 0),
      ], observedAt: now),
      now.add(const Duration(minutes: 1)),
    );
  });

  test('retries are bounded and authentication stops automation', () {
    expect([1, 2, 3, 20].map(UsageResetRefreshPolicy.retryDelay), [
      const Duration(minutes: 5),
      const Duration(minutes: 15),
      const Duration(hours: 1),
      const Duration(hours: 1),
    ]);
    expect([1, 2, 3, 20].map(UsageResetRefreshPolicy.networkRetryDelay), [
      const Duration(seconds: 30),
      const Duration(minutes: 2),
      const Duration(minutes: 5),
      const Duration(minutes: 15),
    ]);
    expect(
      UsageResetRefreshPolicy.pauses(UsageRefreshStatus.authRequired),
      isTrue,
    );
    expect(UsageResetRefreshPolicy.pauses(UsageRefreshStatus.timeout), isFalse);
  });
}
