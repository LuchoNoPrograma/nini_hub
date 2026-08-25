import 'package:nini_hub/core/database/app_database.dart' as db;
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/profiles/data/profile_mapper.dart';

abstract final class AccountMapper {
  static Account fromRows({
    required db.CliProfile profile,
    required db.ProfileMetadata? metadata,
    required Iterable<db.CostShare> costShares,
    required db.UsageCheck? currentCheck,
    required Iterable<db.QuotaWindow> currentWindows,
    required db.UsageCheck? lastSuccessfulCheck,
    required Iterable<db.QuotaWindow> lastSuccessfulWindows,
    required db.ResetCreditSnapshot? resetCredits,
  }) => Account(
    profile: ProfileMapper.fromRow(profile),
    metadata: metadata == null ? null : metadataFromRow(metadata),
    costShares: costShares.map(costShareFromRow),
    currentCheck: currentCheck == null ? null : usageCheckFromRow(currentCheck),
    currentWindows: currentWindows.map(quotaWindowFromRow),
    lastSuccessfulCheck: lastSuccessfulCheck == null
        ? null
        : usageCheckFromRow(lastSuccessfulCheck),
    lastSuccessfulWindows: lastSuccessfulWindows.map(quotaWindowFromRow),
    resetCredits: resetCredits == null
        ? null
        : resetCreditsFromRow(resetCredits),
  );

  static AccountMetadata metadataFromRow(db.ProfileMetadata row) =>
      AccountMetadata(
        accountEmail: row.accountEmail,
        accountDisplayName: row.accountDisplayName,
        planName: row.planName,
        notes: row.notes,
        purchasedOn: row.purchasedOn,
        nextRenewalOn: row.nextRenewalOn,
        billingInterval: row.billingInterval,
        expectedAmountMinor: row.expectedAmountMinor,
        currencyCode: row.currencyCode,
        autoRenew: row.autoRenew,
        subscriptionStatus: row.subscriptionStatus,
        purchasedFrom: row.purchasedFrom,
        paymentMethodLabel: row.paymentMethodLabel,
      );

  static AccountCostShare costShareFromRow(db.CostShare row) =>
      AccountCostShare(
        id: row.id,
        personName: row.personName,
        expectedAmountMinor: row.expectedAmountMinor,
        paidAmountMinor: row.paidAmountMinor,
        currencyCode: row.currencyCode,
        paymentStatus: row.paymentStatus,
        paidOn: row.paidOn,
        notes: row.notes,
      );

  static AccountUsageCheck usageCheckFromRow(db.UsageCheck row) =>
      AccountUsageCheck(
        state: _usageState(row.status),
        startedAt: row.startedAt,
        planType: row.planType,
        accountEmail: row.accountEmail,
        accountDisplayName: row.accountDisplayName,
        errorCode: row.errorCode,
        errorMessage: row.errorMessage,
      );

  static AccountQuotaWindow quotaWindowFromRow(db.QuotaWindow row) =>
      AccountQuotaWindow(
        limitId: row.limitId,
        windowType: row.windowType,
        limitName: row.limitName,
        usedPercent: row.usedPercent,
        windowDurationMinutes: row.windowDurationMinutes,
        resetsAt: row.resetsAt,
        reachedType: row.reachedType,
        planType: row.planType,
      );

  static AccountResetCredits resetCreditsFromRow(db.ResetCreditSnapshot row) =>
      AccountResetCredits(
        availableCount: row.availableCount,
        nextExpiresAt: row.nextExpiresAt,
      );

  static AccountUsageState _usageState(String value) => switch (value) {
    'success' => AccountUsageState.success,
    'partial' => AccountUsageState.partial,
    'unavailable' => AccountUsageState.unavailable,
    'timeout' => AccountUsageState.timeout,
    'auth_required' => AccountUsageState.authRequired,
    'tool_missing' => AccountUsageState.toolMissing,
    'profile_missing' => AccountUsageState.profileMissing,
    _ => AccountUsageState.error,
  };
}
