import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_models.dart';

abstract final class UsageMapper {
  static UsageSnapshot fromCodex(CodexRefreshResult result) => UsageSnapshot(
    status: _fromCodexStatus(result.state),
    startedAt: result.startedAt.toUtc(),
    completedAt: result.completedAt.toUtc(),
    planType: result.planType,
    accountEmail: result.accountEmail,
    accountDisplayName: result.accountDisplayName,
    errorCode: result.errorCode,
    errorMessage: result.errorMessage,
    rateLimitsReadSucceeded: result.rateLimitsReadSucceeded,
    windows: result.windows.map(
      (window) => UsageQuotaWindow(
        limitId: window.limitId,
        windowType: window.windowType,
        limitName: window.limitName,
        usedPercent: window.usedPercent,
        windowDurationMinutes: window.windowDurationMinutes,
        resetsAt: window.resetsAt?.toUtc(),
        reachedType: window.reachedType,
        planType: window.planType,
      ),
    ),
    dailyUsage: result.dailyUsage.map(
      (daily) => UsageDailySnapshot(
        day: daily.day.toUtc(),
        tokens: daily.tokens,
        activeMinutes: daily.activeMinutes,
        messageCount: daily.messageCount,
        source: daily.source,
      ),
    ),
    resetCredits: result.resetCredits,
    nextCreditExpiry: result.nextCreditExpiry?.toUtc(),
  );

  static String statusToStorage(UsageRefreshStatus status) => switch (status) {
    UsageRefreshStatus.authRequired => 'auth_required',
    UsageRefreshStatus.toolMissing => 'tool_missing',
    UsageRefreshStatus.profileMissing => 'profile_missing',
    _ => status.name,
  };

  static UsageRefreshStatus _fromCodexStatus(UsageCheckState status) =>
      switch (status) {
        UsageCheckState.success => UsageRefreshStatus.success,
        UsageCheckState.partial => UsageRefreshStatus.partial,
        UsageCheckState.unavailable => UsageRefreshStatus.unavailable,
        UsageCheckState.timeout => UsageRefreshStatus.timeout,
        UsageCheckState.authRequired => UsageRefreshStatus.authRequired,
        UsageCheckState.toolMissing => UsageRefreshStatus.toolMissing,
        UsageCheckState.profileMissing => UsageRefreshStatus.profileMissing,
        UsageCheckState.error => UsageRefreshStatus.error,
      };
}
