import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

void main() {
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
    expect(account.nextResetAt, fallbackReset);
    expect(account.displayPlan, 'Metadata plan');
    expect(account.displayEmail, 'metadata@example.com');
    expect(account.isReady, isFalse);
    expect(account.needsAttention, isTrue);
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
    expect(account.isReady, isTrue);
    expect(account.needsAttention, isFalse);
  });

  test('details normalize storage values and omit blank participants', () {
    final purchasedOn = DateTime.utc(2026, 7, 1);
    final paidOn = DateTime.utc(2026, 8, 1);
    final details = AccountDetails(
      profileId: 'profile-id',
      metadata: AccountMetadata(
        accountEmail: ' owner@example.com ',
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
    expect(normalized.metadata.accountEmail, 'owner@example.com');
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
