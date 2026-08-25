import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  test(
    'snapshot preserves the provider contract and immutable collections',
    () {
      final startedAt = DateTime.utc(2026, 8, 22, 12);
      final completedAt = startedAt.add(
        const Duration(seconds: 2, milliseconds: 500),
      );
      final resetAt = DateTime.utc(2026, 8, 29, 12);
      final expiryAt = DateTime.utc(2026, 9, 1, 12);
      final windows = <UsageQuotaWindow>[
        UsageQuotaWindow(
          limitId: 'codex',
          windowType: 'secondary',
          limitName: 'Weekly',
          usedPercent: 37.5,
          windowDurationMinutes: 10080,
          resetsAt: resetAt,
          reachedType: 'soft',
          planType: 'plus',
        ),
      ];
      final daily = <UsageDailySnapshot>[
        UsageDailySnapshot(
          day: DateTime.utc(2026, 8, 21),
          tokens: 4200,
          source: 'codex-app-server',
          activeMinutes: 18,
          messageCount: 7,
        ),
      ];

      final snapshot = UsageSnapshot(
        status: UsageRefreshStatus.partial,
        startedAt: startedAt,
        completedAt: completedAt,
        planType: 'plus',
        accountEmail: 'account@example.com',
        accountDisplayName: 'Account',
        errorCode: 'PARTIAL_METADATA',
        errorMessage: 'usage unavailable',
        rateLimitsReadSucceeded: true,
        windows: windows,
        dailyUsage: daily,
        resetCredits: 3,
        nextCreditExpiry: expiryAt,
      );

      expect(UsageRefreshStatus.values, [
        UsageRefreshStatus.success,
        UsageRefreshStatus.partial,
        UsageRefreshStatus.unavailable,
        UsageRefreshStatus.timeout,
        UsageRefreshStatus.authRequired,
        UsageRefreshStatus.toolMissing,
        UsageRefreshStatus.profileMissing,
        UsageRefreshStatus.error,
      ]);
      expect(snapshot.status, UsageRefreshStatus.partial);
      expect(snapshot.startedAt, same(startedAt));
      expect(snapshot.completedAt, same(completedAt));
      expect(snapshot.durationMs, 2500);
      expect(snapshot.planType, 'plus');
      expect(snapshot.accountEmail, 'account@example.com');
      expect(snapshot.accountDisplayName, 'Account');
      expect(snapshot.errorCode, 'PARTIAL_METADATA');
      expect(snapshot.errorMessage, 'usage unavailable');
      expect(snapshot.rateLimitsReadSucceeded, isTrue);
      expect(snapshot.resetCredits, 3);
      expect(snapshot.nextCreditExpiry, same(expiryAt));
      expect(snapshot.windows.single.resetsAt, same(resetAt));
      expect(snapshot.dailyUsage.single.tokens, 4200);

      windows.clear();
      daily.clear();
      expect(snapshot.windows, hasLength(1));
      expect(snapshot.dailyUsage, hasLength(1));
      expect(() => snapshot.windows.clear(), throwsUnsupportedError);
      expect(() => snapshot.dailyUsage.clear(), throwsUnsupportedError);
    },
  );

  test('quota availability preserves nullable and clamped percentages', () {
    expect(
      const UsageQuotaWindow(
        limitId: 'normal',
        windowType: 'primary',
        usedPercent: 30,
      ).remainingPercent,
      70,
    );
    expect(
      const UsageQuotaWindow(
        limitId: 'over',
        windowType: 'primary',
        usedPercent: 120,
      ).remainingPercent,
      0,
    );
    expect(
      const UsageQuotaWindow(
        limitId: 'under',
        windowType: 'primary',
        usedPercent: -10,
      ).remainingPercent,
      100,
    );
    expect(
      const UsageQuotaWindow(
        limitId: 'unknown',
        windowType: 'primary',
      ).remainingPercent,
      isNull,
    );
  });

  test('calendar uses date-only lookup and immutable account projections', () {
    final accounts = <UsageAccountDay>[
      const UsageAccountDay(
        profileId: 'primary',
        displayName: 'Primary',
        email: 'primary@example.com',
        tokens: 100,
        successfulChecks: 1,
        failedChecks: 0,
        lowestRemaining: 60,
        resetCount: 0,
        renewalCount: 0,
      ),
    ];
    final day = UsageCalendarDay(
      day: DateTime(2026, 8, 22),
      tokens: 100,
      successfulChecks: 1,
      failedChecks: 0,
      lowestRemaining: 60,
      resetCount: 0,
      renewalCount: 0,
      accounts: accounts,
    );
    final calendar = UsageCalendar([day]);

    accounts.clear();
    expect(day.accounts, hasLength(1));
    expect(day.hasActivity, isTrue);
    expect(day.accounts.single.hasActivity, isTrue);
    expect(calendar[DateTime(2026, 8, 22, 23, 59)], same(day));
    expect(calendar[DateTime(2026, 8, 23)], isNull);
    expect(() => day.accounts.clear(), throwsUnsupportedError);
    expect(
      () => calendar.days[DateTime(2026, 8, 23)] = day,
      throwsUnsupportedError,
    );

    final empty = UsageCalendarDay(
      day: DateTime(2026, 8, 23),
      tokens: 0,
      successfulChecks: 0,
      failedChecks: 0,
      lowestRemaining: null,
      resetCount: 0,
      renewalCount: 0,
      accounts: const [
        UsageAccountDay(
          profileId: 'empty',
          displayName: 'Empty',
          email: '',
          tokens: 0,
          successfulChecks: 0,
          failedChecks: 0,
          lowestRemaining: null,
          resetCount: 0,
          renewalCount: 0,
        ),
      ],
    );
    expect(empty.hasActivity, isFalse);
    expect(empty.accounts.single.hasActivity, isFalse);
  });
}
