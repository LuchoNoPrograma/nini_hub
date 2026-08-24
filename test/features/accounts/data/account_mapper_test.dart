import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/accounts/data/account_mapper.dart';
import 'package:multi_cli_ai/features/accounts/domain/account.dart';

void main() {
  test('maps persisted account values without reinterpreting them', () {
    final purchasedOn = DateTime.utc(2026, 7, 1);
    final renewalOn = DateTime.utc(2026, 9, 1);
    final startedAt = DateTime.utc(2026, 8, 22, 15);
    final resetsAt = DateTime.utc(2026, 8, 23);
    final expiresAt = DateTime.utc(2026, 8, 24);

    final account = AccountMapper.fromRows(
      profile: _profile(),
      metadata: ProfileMetadata(
        profileId: 'account',
        accountEmail: 'owner@example.com',
        accountDisplayName: 'Owner',
        planName: 'Team',
        notes: 'Notes',
        tagsJson: '["ignored-by-account"]',
        purchasedOn: purchasedOn,
        nextRenewalOn: renewalOn,
        billingInterval: 'yearly',
        expectedAmountMinor: 12345,
        currencyCode: 'BOB',
        autoRenew: false,
        subscriptionStatus: 'paused',
        purchasedFrom: 'Store',
        paymentMethodLabel: 'Card',
        updatedAt: startedAt,
      ),
      costShares: [
        CostShare(
          id: 'share',
          profileId: 'account',
          personName: 'Bea',
          expectedAmountMinor: 5000,
          paidAmountMinor: 2500,
          currencyCode: 'BOB',
          paymentStatus: 'partial',
          paidOn: purchasedOn,
          notes: 'Half',
        ),
      ],
      currentCheck: UsageCheck(
        id: 'check',
        profileId: 'account',
        queryMethod: 'test',
        status: 'auth_required',
        startedAt: startedAt,
        planType: 'pro',
        accountEmail: 'observed@example.com',
        accountDisplayName: 'Observed',
        errorCode: 'TOKEN_EXPIRED',
        errorMessage: 'expired',
      ),
      currentWindows: [
        QuotaWindow(
          id: 'window',
          checkId: 'check',
          limitId: 'codex',
          limitName: 'Messages',
          windowType: 'primary',
          usedPercent: 25,
          windowDurationMinutes: 300,
          resetsAt: resetsAt,
          reachedType: 'soft',
          planType: 'pro',
        ),
      ],
      lastSuccessfulCheck: null,
      lastSuccessfulWindows: const [],
      resetCredits: ResetCreditSnapshot(
        checkId: 'check',
        availableCount: 7,
        nextExpiresAt: expiresAt,
      ),
    );

    expect(account.profile.id, 'account');
    expect(account.metadata?.accountEmail, 'owner@example.com');
    expect(account.metadata?.purchasedOn, same(purchasedOn));
    expect(account.metadata?.nextRenewalOn, same(renewalOn));
    expect(account.metadata?.expectedAmountMinor, 12345);
    expect(account.costShares.single.personName, 'Bea');
    expect(account.costShares.single.paidOn, same(purchasedOn));
    expect(account.currentCheck?.state, AccountUsageState.authRequired);
    expect(account.currentCheck?.startedAt, same(startedAt));
    expect(account.currentWindows.single.resetsAt, same(resetsAt));
    expect(account.currentWindows.single.usedPercent, 25);
    expect(account.resetCredits?.availableCount, 7);
    expect(account.resetCredits?.nextExpiresAt, same(expiresAt));
  });

  test(
    'maps every known usage status and fails legacy-compatible to error',
    () {
      const expected = {
        'success': AccountUsageState.success,
        'partial': AccountUsageState.partial,
        'unavailable': AccountUsageState.unavailable,
        'timeout': AccountUsageState.timeout,
        'auth_required': AccountUsageState.authRequired,
        'tool_missing': AccountUsageState.toolMissing,
        'profile_missing': AccountUsageState.profileMissing,
        'error': AccountUsageState.error,
        'future_value': AccountUsageState.error,
      };

      for (final entry in expected.entries) {
        final mapped = AccountMapper.usageCheckFromRow(
          UsageCheck(
            id: entry.key,
            profileId: 'account',
            queryMethod: 'test',
            status: entry.key,
            startedAt: DateTime.utc(2026, 8, 22),
          ),
        );
        expect(mapped.state, entry.value, reason: entry.key);
      }
    },
  );
}

CliProfile _profile() => CliProfile(
  id: 'account',
  toolKey: 'codex',
  profileName: 'team',
  commandName: 'codex-team',
  displayName: 'Team',
  profileHome: '/profiles/team',
  profileSource: 'multicli',
  profileType: 'full',
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: true,
  createdAt: DateTime.utc(2026, 1, 1),
  lastDiscoveredAt: DateTime.utc(2026, 8, 1),
);
