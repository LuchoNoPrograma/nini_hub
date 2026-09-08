import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/quota_reset_anchor_policy.dart';

void main() {
  test('status distinguishes current evidence from historical quota', () {
    Account sample(AccountUsageState? state, {String? code, double? used}) =>
        Account(
          profile: _profile(),
          metadata: null,
          costShares: const [],
          currentCheck: state == null
              ? null
              : AccountUsageCheck(
                  state: state,
                  startedAt: DateTime.utc(2026, 9, 7),
                  errorCode: code,
                ),
          currentWindows: used == null
              ? const []
              : [
                  AccountQuotaWindow(
                    limitId: 'codex',
                    windowType: 'primary',
                    usedPercent: used,
                  ),
                ],
          lastSuccessfulCheck: AccountUsageCheck(
            state: AccountUsageState.success,
            startedAt: DateTime.utc(2026, 9, 6),
          ),
          lastSuccessfulWindows: const [
            AccountQuotaWindow(
              limitId: 'codex',
              windowType: 'primary',
              usedPercent: 100,
            ),
          ],
          resetCredits: null,
        );
    expect(sample(null).status, AccountStatus.unchecked);
    expect(
      sample(AccountUsageState.success).status,
      AccountStatus.quotaUnconfirmed,
    );
    expect(
      sample(AccountUsageState.success, used: 20).status,
      AccountStatus.available,
    );
    expect(
      sample(AccountUsageState.partial, used: 20).status,
      AccountStatus.available,
    );
    expect(
      sample(AccountUsageState.partial).status,
      AccountStatus.quotaUnconfirmed,
    );
    expect(
      sample(AccountUsageState.success, used: 100).status,
      AccountStatus.quotaExhausted,
    );
    expect(
      sample(AccountUsageState.authRequired).status,
      AccountStatus.authRequired,
    );
    for (final code in ['TOKEN_EXPIRED', 'TOKEN_INVALIDATED']) {
      expect(
        sample(AccountUsageState.error, code: code).status,
        AccountStatus.authRequired,
      );
    }
    for (final state in [AccountUsageState.error, AccountUsageState.timeout]) {
      expect(sample(state).status, AccountStatus.queryError);
    }
    for (final state in [
      AccountUsageState.toolMissing,
      AccountUsageState.profileMissing,
      AccountUsageState.unavailable,
    ]) {
      expect(sample(state).status, AccountStatus.unavailable);
    }
  });

  test('account preserves visible fallback and descriptive issue rules', () {
    final current = AccountUsageCheck(
      state: AccountUsageState.error,
      startedAt: DateTime.utc(2026, 8, 22, 15),
      planType: 'observed-current',
      accountEmail: 'current@example.com',
      errorCode: 'PARTIAL_METADATA',
      errorMessage: 'connection refused',
    );
    final successful = AccountUsageCheck(
      state: AccountUsageState.success,
      startedAt: DateTime.utc(2026, 8, 22, 14),
      planType: 'observed-success',
      accountEmail: 'success@example.com',
    );
    final fallbackReset = DateTime.utc(2026, 8, 29);
    final account = Account(
      profile: _profile(),
      metadata: _metadata(
        accountEmail: 'metadata@example.com',
        planName: 'Metadata plan',
      ),
      costShares: const [],
      currentCheck: current,
      currentWindows: const [
        AccountQuotaWindow(
          limitId: 'current',
          windowType: 'primary',
          usedPercent: 90,
        ),
      ],
      lastSuccessfulCheck: successful,
      lastSuccessfulWindows: [
        AccountQuotaWindow(
          limitId: 'fallback',
          windowType: 'secondary',
          usedPercent: 12,
          resetsAt: fallbackReset,
        ),
      ],
      resetCredits: const AccountResetCredits(
        availableCount: 4,
        nextExpiresAt: null,
      ),
    );

    expect(account.currentIsUsable, isFalse);
    expect(account.currentIssue, AccountUsageIssue.network);
    expect(account.visibleWindows.single.limitId, 'fallback');
    expect(account.lowestAvailablePercent, 88);
    expect(account.operationalAvailablePercent, isNull);
    expect(account.nextResetAt, fallbackReset);
    expect(account.displayPlan, 'Metadata plan');
    expect(account.observedEmail, 'current@example.com');
    expect(account.displayEmail, 'current@example.com');
    expect(account.isReady, isFalse);
    expect(account.needsAttention, isTrue);
    expect(account.isUnlinked, isFalse);
  });

  test('usable current windows take precedence and clamp availability', () {
    final account = Account(
      profile: _profile(),
      metadata: _metadata(accountEmail: '', planName: ''),
      costShares: const [],
      currentCheck: AccountUsageCheck(
        state: AccountUsageState.partial,
        startedAt: DateTime.utc(2026, 8, 22),
        planType: 'Observed',
        accountEmail: 'observed@example.com',
      ),
      currentWindows: const [
        AccountQuotaWindow(
          limitId: 'over',
          windowType: 'primary',
          usedPercent: 120,
        ),
        AccountQuotaWindow(
          limitId: 'normal',
          windowType: 'secondary',
          usedPercent: 30,
        ),
      ],
      lastSuccessfulCheck: null,
      lastSuccessfulWindows: const [
        AccountQuotaWindow(
          limitId: 'fallback',
          windowType: 'primary',
          usedPercent: 1,
        ),
      ],
      resetCredits: null,
    );

    expect(account.visibleWindows.map((window) => window.limitId), [
      'over',
      'normal',
    ]);
    expect(account.lowestAvailablePercent, 0);
    expect(account.displayPlan, 'Observed');
    expect(account.displayEmail, 'observed@example.com');
    expect(account.isReady, isFalse);
    expect(account.needsAttention, isTrue);
  });

  test('weekly quota blocks only windows of the same limit', () {
    const short = AccountQuotaWindow(
      limitId: 'codex',
      windowType: 'primary',
      usedPercent: 0,
      windowDurationMinutes: 300,
    );
    const weekly = AccountQuotaWindow(
      limitId: ' CODEX ',
      windowType: 'secondary',
      usedPercent: 100,
      windowDurationMinutes: 10080,
    );
    const independent = AccountQuotaWindow(
      limitId: 'spark',
      windowType: 'primary',
      usedPercent: 0,
      windowDurationMinutes: 300,
    );
    final account = _quotaAccount([short, weekly, independent]);
    expect(account.blockingWindowFor(short), weekly);
    expect(account.blockingWindowFor(independent), isNull);
    expect(account.hasWeeklyLimitReached, isTrue);
    expect(account.isReady, isFalse);
    expect(account.needsAttention, isTrue);
    expect(account.operationalAvailablePercent, 0);
    expect(short.remainingPercent, 100);
  });

  test('short exhaustion preserves weekly balance and its own reset', () {
    final shortReset = DateTime.utc(2026, 9, 5, 20);
    final weeklyReset = DateTime.utc(2026, 9, 10);
    final short = AccountQuotaWindow(
      limitId: 'codex',
      windowType: 'primary',
      usedPercent: 100,
      windowDurationMinutes: 300,
      resetsAt: shortReset,
    );
    final weekly = AccountQuotaWindow(
      limitId: 'codex',
      windowType: 'secondary',
      usedPercent: 20,
      windowDurationMinutes: 10080,
      resetsAt: weeklyReset,
    );
    final account = _quotaAccount([short, weekly]);
    expect(account.operationalAvailablePercent, 0);
    expect(account.isReady, isFalse);
    expect(account.blockingWindowFor(weekly), same(short));
    expect(account.visibleWindows, [short, weekly]);
    expect(weekly.remainingPercent, 80);
    expect(weekly.resetsAt, weeklyReset);
    expect(short.resetsAt, shortReset);
    expect(account.hasWeeklyLimitReached, isFalse);
  });

  test('unknown quota cannot borrow availability from a known window', () {
    for (final unknown in [null, double.nan, double.infinity]) {
      final account = _quotaAccount([
        AccountQuotaWindow(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: unknown,
        ),
        const AccountQuotaWindow(
          limitId: 'codex',
          windowType: 'secondary',
          usedPercent: 20,
        ),
      ]);
      expect(account.lowestAvailablePercent, 80);
      expect(account.operationalAvailablePercent, isNull);
      expect(account.isReady, isFalse);
    }
  });

  test('successful query requires known positive quota to count as ready', () {
    for (final used in [null, double.nan, double.infinity, 100.0, 120.0]) {
      final account = _quotaAccount([
        AccountQuotaWindow(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: used,
        ),
      ]);
      expect(account.isReady, isFalse, reason: 'used=$used');
    }
    expect(_quotaAccount([]).isReady, isFalse);
    expect(
      _quotaAccount(const [
        AccountQuotaWindow(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 0,
        ),
      ]).isReady,
      isTrue,
    );
  });

  test('unnamed and unknown limits never invent a blocking relationship', () {
    const unknown = AccountQuotaWindow(limitId: '', windowType: 'primary');
    const exhausted = AccountQuotaWindow(
      limitId: '',
      windowType: 'secondary',
      usedPercent: 100,
    );
    final account = _quotaAccount([unknown, exhausted]);
    expect(account.blockingWindowFor(unknown), isNull);
    expect(unknown.remainingPercent, isNull);
  });

  test('details normalize storage values and omit blank participants', () {
    final purchasedOn = DateTime.utc(2026, 7, 1);
    final paidOn = DateTime.utc(2026, 8, 1);
    final details = AccountDetails(
      profileId: 'profile-id',
      metadata: AccountEditableMetadata(
        accountDisplayName: ' Owner ',
        planName: ' Team ',
        notes: ' Note ',
        purchasedOn: purchasedOn,
        nextRenewalOn: null,
        billingInterval: 'yearly',
        expectedAmountMinor: 12345,
        currencyCode: ' bob ',
        autoRenew: false,
        subscriptionStatus: 'paused',
        purchasedFrom: ' Store ',
        paymentMethodLabel: ' Visa ',
      ),
      costShares: [
        const AccountCostShare(
          id: 'blank',
          personName: '   ',
          expectedAmountMinor: 100,
          paidAmountMinor: 0,
          currencyCode: 'usd',
          paymentStatus: 'pending',
          paidOn: null,
          notes: '',
        ),
        AccountCostShare(
          id: 'bea',
          personName: ' Bea ',
          expectedAmountMinor: 5000,
          paidAmountMinor: 2500,
          currencyCode: ' bob ',
          paymentStatus: 'partial',
          paidOn: paidOn,
          notes: ' Half ',
        ),
      ],
    );

    final normalized = details.normalizedForSave();

    expect(normalized.profileId, 'profile-id');
    expect(normalized.metadata.accountDisplayName, 'Owner');
    expect(normalized.metadata.planName, 'Team');
    expect(normalized.metadata.notes, 'Note');
    expect(normalized.metadata.currencyCode, 'BOB');
    expect(normalized.metadata.purchasedOn, same(purchasedOn));
    expect(normalized.metadata.expectedAmountMinor, 12345);
    expect(normalized.costShares, hasLength(1));
    expect(normalized.costShares.single.personName, 'Bea');
    expect(normalized.costShares.single.currencyCode, 'BOB');
    expect(normalized.costShares.single.paidOn, same(paidOn));
    expect(normalized.costShares.single.notes, 'Half');
    expect(
      () => normalized.costShares.add(normalized.costShares.single),
      throwsUnsupportedError,
    );
  });

  test('account collections are immutable', () {
    final account = _account();

    expect(
      () => account.currentWindows.add(
        const AccountQuotaWindow(limitId: 'x', windowType: 'primary'),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => account.costShares.add(
        const AccountCostShare(
          id: 'x',
          personName: 'X',
          expectedAmountMinor: 0,
          paidAmountMinor: 0,
          currencyCode: 'USD',
          paymentStatus: 'pending',
          paidOn: null,
          notes: '',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('account compares the same visible window across successful reads', () {
    final currentAt = DateTime.utc(2026, 8, 25, 12, 30);
    final previousAt = DateTime.utc(2026, 8, 25, 12);
    final account = Account(
      profile: _profile(),
      metadata: null,
      costShares: const [],
      currentCheck: AccountUsageCheck(
        state: AccountUsageState.success,
        startedAt: currentAt,
        completedAt: currentAt,
      ),
      currentWindows: [
        AccountQuotaWindow(
          limitId: 'CODEX',
          windowType: 'PRIMARY',
          usedPercent: 0,
          windowDurationMinutes: 300,
          resetsAt: currentAt.add(const Duration(hours: 5)),
        ),
      ],
      lastSuccessfulCheck: AccountUsageCheck(
        state: AccountUsageState.success,
        startedAt: currentAt,
        completedAt: currentAt,
      ),
      lastSuccessfulWindows: const [],
      previousSuccessfulCheck: AccountUsageCheck(
        state: AccountUsageState.success,
        startedAt: previousAt,
        completedAt: previousAt,
      ),
      previousSuccessfulWindows: [
        AccountQuotaWindow(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 0,
          windowDurationMinutes: 300,
          resetsAt: previousAt.add(const Duration(hours: 5)),
        ),
      ],
      resetCredits: null,
    );

    expect(
      account.resetAnchorConfidence(account.visibleWindows.single),
      QuotaResetAnchorConfidence.estimated,
    );
  });
}

Account _account() => Account(
  profile: _profile(),
  metadata: null,
  costShares: const [],
  currentCheck: null,
  currentWindows: const [],
  lastSuccessfulCheck: null,
  lastSuccessfulWindows: const [],
  resetCredits: null,
);

Profile _profile() => const Profile(
  id: 'profile-id',
  toolKey: 'codex',
  profileName: 'team',
  commandName: 'codex-team',
  displayName: 'Team',
  profileHome: '/profiles/team',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);

AccountMetadata _metadata({
  required String accountEmail,
  required String planName,
}) => AccountMetadata(
  accountEmail: accountEmail,
  accountDisplayName: '',
  planName: planName,
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
);

Account _quotaAccount(List<AccountQuotaWindow> windows) => Account(
  profile: _profile(),
  metadata: null,
  costShares: const [],
  currentCheck: AccountUsageCheck(
    state: AccountUsageState.success,
    startedAt: DateTime.utc(2026, 9, 5),
  ),
  currentWindows: windows,
  lastSuccessfulCheck: null,
  lastSuccessfulWindows: const [],
  resetCredits: null,
);
