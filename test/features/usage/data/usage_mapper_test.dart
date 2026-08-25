import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';
import 'package:nini_hub/features/usage/data/usage_mapper.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  test('maps the complete Codex snapshot', () {
    final startedAt = DateTime.utc(2026, 8, 22, 10);
    final completedAt = startedAt.add(
      const Duration(seconds: 2, milliseconds: 500),
    );
    final resetAt = DateTime.utc(2026, 8, 29, 10);
    final expiry = DateTime.utc(2026, 9, 1, 10);
    final result = CodexRefreshResult(
      state: UsageCheckState.partial,
      startedAt: startedAt,
      completedAt: completedAt,
      planType: 'plus',
      accountEmail: 'owner@example.com',
      accountDisplayName: 'Owner',
      errorCode: 'PARTIAL_METADATA',
      errorMessage: 'Usage endpoint unavailable',
      rateLimitsReadSucceeded: true,
      windows: [
        QuotaSnapshot(
          limitId: 'codex',
          windowType: 'secondary',
          limitName: 'Weekly',
          usedPercent: 42.5,
          windowDurationMinutes: 10080,
          resetsAt: resetAt,
          reachedType: 'soft',
          planType: 'plus',
        ),
      ],
      dailyUsage: [
        DailyUsageSnapshot(
          day: DateTime.utc(2026, 8, 21),
          tokens: 4200,
          activeMinutes: 18,
          messageCount: 7,
          source: 'codex-app-server',
        ),
      ],
      resetCredits: 3,
      nextCreditExpiry: expiry,
    );

    final snapshot = UsageMapper.fromCodex(result);

    expect(snapshot.status, UsageRefreshStatus.partial);
    expect(snapshot.startedAt, startedAt);
    expect(snapshot.completedAt, completedAt);
    expect(snapshot.durationMs, 2500);
    expect(snapshot.planType, 'plus');
    expect(snapshot.accountEmail, 'owner@example.com');
    expect(snapshot.accountDisplayName, 'Owner');
    expect(snapshot.errorCode, 'PARTIAL_METADATA');
    expect(snapshot.errorMessage, 'Usage endpoint unavailable');
    expect(snapshot.rateLimitsReadSucceeded, isTrue);
    expect(snapshot.windows.single.limitName, 'Weekly');
    expect(snapshot.windows.single.usedPercent, 42.5);
    expect(snapshot.windows.single.resetsAt, resetAt);
    expect(snapshot.dailyUsage.single.tokens, 4200);
    expect(snapshot.dailyUsage.single.day, DateTime.utc(2026, 8, 21));
    expect(snapshot.resetCredits, 3);
    expect(snapshot.nextCreditExpiry, expiry);
  });

  test('maps every status to the existing storage string', () {
    const expected = {
      UsageRefreshStatus.success: 'success',
      UsageRefreshStatus.partial: 'partial',
      UsageRefreshStatus.unavailable: 'unavailable',
      UsageRefreshStatus.timeout: 'timeout',
      UsageRefreshStatus.authRequired: 'auth_required',
      UsageRefreshStatus.toolMissing: 'tool_missing',
      UsageRefreshStatus.profileMissing: 'profile_missing',
      UsageRefreshStatus.error: 'error',
    };

    for (final entry in expected.entries) {
      expect(UsageMapper.statusToStorage(entry.key), entry.value);
    }
  });
}
