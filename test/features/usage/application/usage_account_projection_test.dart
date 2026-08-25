import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/application/usage_account_projection.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  const project = ProjectUsageAccount();

  test('projects a successful snapshot without losing account-owned data', () {
    final account = _account();
    final startedAt = DateTime.utc(2026, 8, 25, 10);
    final projected = project(
      account,
      UsageSnapshot(
        status: UsageRefreshStatus.success,
        startedAt: startedAt,
        completedAt: startedAt.add(const Duration(seconds: 2)),
        planType: 'pro',
        accountEmail: 'fresh@example.com',
        accountDisplayName: 'Fresh',
        windows: [
          UsageQuotaWindow(
            limitId: 'codex',
            windowType: 'primary',
            usedPercent: 23,
            windowDurationMinutes: 300,
          ),
        ],
        resetCredits: 4,
        nextCreditExpiry: DateTime.utc(2026, 9, 1),
      ),
    );

    expect(projected.profile, same(account.profile));
    expect(projected.metadata, same(account.metadata));
    expect(projected.costShares, account.costShares);
    expect(projected.currentCheck?.state, AccountUsageState.success);
    expect(projected.currentCheck?.startedAt, startedAt);
    expect(projected.displayEmail, 'fresh@example.com');
    expect(projected.currentWindows.single.remainingPercent, 77);
    expect(projected.lastSuccessfulWindows.single.remainingPercent, 77);
    expect(projected.resetCredits?.availableCount, 4);
  });

  test(
    'a partial snapshot updates current usage and preserves last success',
    () {
      final priorSuccess = DateTime.utc(2026, 8, 25, 9);
      final account = _account(
        currentCheck: _check(AccountUsageState.success, priorSuccess),
        currentWindows: [_window(10)],
        lastSuccessfulCheck: _check(AccountUsageState.success, priorSuccess),
        lastSuccessfulWindows: [_window(10)],
      );
      final projected = project(
        account,
        UsageSnapshot(
          status: UsageRefreshStatus.partial,
          startedAt: DateTime.utc(2026, 8, 25, 10),
          completedAt: DateTime.utc(2026, 8, 25, 10, 0, 1),
          windows: [
            const UsageQuotaWindow(
              limitId: 'codex',
              windowType: 'primary',
              usedPercent: 35,
            ),
          ],
        ),
      );

      expect(projected.currentCheck?.state, AccountUsageState.partial);
      expect(projected.currentWindows.single.remainingPercent, 65);
      expect(projected.lastSuccessfulCheck?.startedAt, priorSuccess);
      expect(projected.lastSuccessfulWindows.single.remainingPercent, 90);
    },
  );

  test('an older response cannot replace a newer current check', () {
    final account = _account(
      currentCheck: _check(
        AccountUsageState.timeout,
        DateTime.utc(2026, 8, 25, 13),
      ),
      currentWindows: [_window(70)],
      lastSuccessfulCheck: _check(
        AccountUsageState.success,
        DateTime.utc(2026, 8, 25, 10),
      ),
      lastSuccessfulWindows: [_window(60)],
    );
    final projected = project(
      account,
      UsageSnapshot(
        status: UsageRefreshStatus.success,
        startedAt: DateTime.utc(2026, 8, 25, 12),
        completedAt: DateTime.utc(2026, 8, 25, 12, 0, 1),
        windows: [
          const UsageQuotaWindow(
            limitId: 'codex',
            windowType: 'primary',
            usedPercent: 20,
          ),
        ],
      ),
    );

    expect(projected.currentCheck?.state, AccountUsageState.timeout);
    expect(projected.currentCheck?.startedAt, DateTime.utc(2026, 8, 25, 13));
    expect(projected.currentWindows.single.remainingPercent, 30);
    expect(
      projected.lastSuccessfulCheck?.startedAt,
      DateTime.utc(2026, 8, 25, 12),
    );
    expect(projected.lastSuccessfulWindows.single.remainingPercent, 80);
  });

  test('a newer success rotates the prior successful observation', () {
    final priorAt = DateTime.utc(2026, 8, 25, 10);
    final nextAt = DateTime.utc(2026, 8, 25, 11);
    final account = _account(
      currentCheck: _check(AccountUsageState.success, priorAt),
      currentWindows: [_window(10)],
      lastSuccessfulCheck: _check(AccountUsageState.success, priorAt),
      lastSuccessfulWindows: [_window(10)],
    );

    final projected = project(
      account,
      UsageSnapshot(
        status: UsageRefreshStatus.success,
        startedAt: nextAt,
        completedAt: nextAt.add(const Duration(seconds: 3)),
        windows: [
          const UsageQuotaWindow(
            limitId: 'codex',
            windowType: 'primary',
            usedPercent: 20,
          ),
        ],
      ),
    );

    expect(projected.lastSuccessfulCheck?.startedAt, nextAt);
    expect(
      projected.lastSuccessfulCheck?.observedAt,
      nextAt.add(const Duration(seconds: 3)),
    );
    expect(projected.previousSuccessfulCheck?.startedAt, priorAt);
    expect(projected.previousSuccessfulWindows.single.usedPercent, 10);
  });
}

Account _account({
  AccountUsageCheck? currentCheck,
  List<AccountQuotaWindow> currentWindows = const [],
  AccountUsageCheck? lastSuccessfulCheck,
  List<AccountQuotaWindow> lastSuccessfulWindows = const [],
}) => Account(
  profile: Profile(
    id: 'profile',
    toolKey: 'codex',
    profileName: 'profile',
    commandName: 'codex-profile',
    displayName: 'Profile',
    profileHome: '/profiles/profile',
    source: ProfileSource.multiCli,
    kind: ProfileKind.full,
    hasAuthFile: true,
    isAvailable: true,
    isFavorite: true,
  ),
  metadata: const AccountMetadata(
    accountEmail: 'owned@example.com',
    accountDisplayName: 'Owned',
    planName: '',
    notes: '',
    purchasedOn: null,
    nextRenewalOn: null,
    billingInterval: 'monthly',
    expectedAmountMinor: 0,
    currencyCode: 'USD',
    autoRenew: true,
    subscriptionStatus: 'active',
    purchasedFrom: '',
    paymentMethodLabel: '',
  ),
  costShares: const [
    AccountCostShare(
      id: 'share',
      personName: 'Nini',
      expectedAmountMinor: 100,
      paidAmountMinor: 100,
      currencyCode: 'USD',
      paymentStatus: 'paid',
      paidOn: null,
      notes: '',
    ),
  ],
  currentCheck: currentCheck,
  currentWindows: currentWindows,
  lastSuccessfulCheck: lastSuccessfulCheck,
  lastSuccessfulWindows: lastSuccessfulWindows,
  resetCredits: null,
);

AccountUsageCheck _check(AccountUsageState state, DateTime startedAt) =>
    AccountUsageCheck(state: state, startedAt: startedAt);

AccountQuotaWindow _window(double usedPercent) => AccountQuotaWindow(
  limitId: 'codex',
  windowType: 'primary',
  usedPercent: usedPercent,
);
