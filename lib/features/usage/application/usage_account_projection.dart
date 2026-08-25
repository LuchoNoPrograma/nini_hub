import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

final class ProjectUsageAccount {
  const ProjectUsageAccount();

  Account call(Account account, UsageSnapshot snapshot) {
    final check = AccountUsageCheck(
      state: _accountState(snapshot.status),
      startedAt: snapshot.startedAt,
      planType: snapshot.planType,
      accountEmail: snapshot.accountEmail,
      accountDisplayName: snapshot.accountDisplayName,
      errorCode: snapshot.errorCode,
      errorMessage: snapshot.errorMessage,
    );
    final windows = [
      for (final window in snapshot.windows)
        AccountQuotaWindow(
          limitId: window.limitId,
          limitName: window.limitName,
          windowType: window.windowType,
          usedPercent: window.usedPercent,
          windowDurationMinutes: window.windowDurationMinutes,
          resetsAt: window.resetsAt,
          reachedType: window.reachedType,
          planType: window.planType,
        ),
    ];

    final replacesCurrent =
        account.currentCheck == null ||
        !snapshot.startedAt.isBefore(account.currentCheck!.startedAt);
    final replacesSuccessful =
        snapshot.status == UsageRefreshStatus.success &&
        (account.lastSuccessfulCheck == null ||
            !snapshot.startedAt.isBefore(
              account.lastSuccessfulCheck!.startedAt,
            ));
    if (!replacesCurrent && !replacesSuccessful) return account;

    return Account(
      profile: account.profile,
      metadata: account.metadata,
      costShares: account.costShares,
      currentCheck: replacesCurrent ? check : account.currentCheck,
      currentWindows: replacesCurrent ? windows : account.currentWindows,
      lastSuccessfulCheck: replacesSuccessful
          ? check
          : account.lastSuccessfulCheck,
      lastSuccessfulWindows: replacesSuccessful
          ? windows
          : account.lastSuccessfulWindows,
      resetCredits: replacesSuccessful
          ? AccountResetCredits(
              availableCount: snapshot.resetCredits,
              nextExpiresAt: snapshot.nextCreditExpiry,
            )
          : account.resetCredits,
    );
  }

  static AccountUsageState _accountState(UsageRefreshStatus status) =>
      switch (status) {
        UsageRefreshStatus.success => AccountUsageState.success,
        UsageRefreshStatus.partial => AccountUsageState.partial,
        UsageRefreshStatus.unavailable => AccountUsageState.unavailable,
        UsageRefreshStatus.timeout => AccountUsageState.timeout,
        UsageRefreshStatus.authRequired => AccountUsageState.authRequired,
        UsageRefreshStatus.toolMissing => AccountUsageState.toolMissing,
        UsageRefreshStatus.profileMissing => AccountUsageState.profileMissing,
        UsageRefreshStatus.error => AccountUsageState.error,
      };
}
