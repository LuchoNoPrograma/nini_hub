import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';

enum AccountUsageState {
  success,
  partial,
  unavailable,
  timeout,
  authRequired,
  toolMissing,
  profileMissing,
  error,
}

enum AccountUsageIssue {
  network,
  credentialExpired,
  credentialInvalidated,
  partialMetadata,
}

final class AccountMetadata {
  const AccountMetadata({
    required this.accountEmail,
    required this.accountDisplayName,
    required this.planName,
    required this.notes,
    required this.purchasedOn,
    required this.nextRenewalOn,
    required this.billingInterval,
    required this.expectedAmountMinor,
    required this.currencyCode,
    required this.autoRenew,
    required this.subscriptionStatus,
    required this.purchasedFrom,
    required this.paymentMethodLabel,
  });

  final String accountEmail;
  final String accountDisplayName;
  final String planName;
  final String notes;
  final DateTime? purchasedOn;
  final DateTime? nextRenewalOn;
  final String billingInterval;
  final int expectedAmountMinor;
  final String currencyCode;
  final bool autoRenew;
  final String subscriptionStatus;
  final String purchasedFrom;
  final String paymentMethodLabel;

  AccountMetadata normalizedForSave() => AccountMetadata(
    accountEmail: accountEmail.trim(),
    accountDisplayName: accountDisplayName.trim(),
    planName: planName.trim(),
    notes: notes.trim(),
    purchasedOn: purchasedOn,
    nextRenewalOn: nextRenewalOn,
    billingInterval: billingInterval,
    expectedAmountMinor: expectedAmountMinor,
    currencyCode: currencyCode.trim().toUpperCase(),
    autoRenew: autoRenew,
    subscriptionStatus: subscriptionStatus,
    purchasedFrom: purchasedFrom.trim(),
    paymentMethodLabel: paymentMethodLabel.trim(),
  );
}

final class AccountCostShare {
  const AccountCostShare({
    required this.id,
    required this.personName,
    required this.expectedAmountMinor,
    required this.paidAmountMinor,
    required this.currencyCode,
    required this.paymentStatus,
    required this.paidOn,
    required this.notes,
  });

  final String id;
  final String personName;
  final int expectedAmountMinor;
  final int paidAmountMinor;
  final String currencyCode;
  final String paymentStatus;
  final DateTime? paidOn;
  final String notes;

  AccountCostShare normalizedForSave() => AccountCostShare(
    id: id,
    personName: personName.trim(),
    expectedAmountMinor: expectedAmountMinor,
    paidAmountMinor: paidAmountMinor,
    currencyCode: currencyCode.trim().toUpperCase(),
    paymentStatus: paymentStatus,
    paidOn: paidOn,
    notes: notes.trim(),
  );
}

final class AccountDetails {
  AccountDetails({
    required this.profileId,
    required this.metadata,
    required Iterable<AccountCostShare> costShares,
  }) : costShares = List.unmodifiable(costShares);

  final String profileId;
  final AccountMetadata metadata;
  final List<AccountCostShare> costShares;

  AccountDetails normalizedForSave() => AccountDetails(
    profileId: profileId,
    metadata: metadata.normalizedForSave(),
    costShares: costShares
        .where((share) => share.personName.trim().isNotEmpty)
        .map((share) => share.normalizedForSave()),
  );
}

final class AccountUsageCheck {
  const AccountUsageCheck({
    required this.state,
    required this.startedAt,
    this.planType,
    this.accountEmail,
    this.accountDisplayName,
    this.errorCode,
    this.errorMessage,
  });

  final AccountUsageState state;
  final DateTime startedAt;
  final String? planType;
  final String? accountEmail;
  final String? accountDisplayName;
  final String? errorCode;
  final String? errorMessage;
}

final class AccountQuotaWindow {
  const AccountQuotaWindow({
    required this.limitId,
    required this.windowType,
    this.limitName,
    this.usedPercent,
    this.windowDurationMinutes,
    this.resetsAt,
    this.reachedType,
    this.planType,
  });

  final String limitId;
  final String windowType;
  final String? limitName;
  final double? usedPercent;
  final int? windowDurationMinutes;
  final DateTime? resetsAt;
  final String? reachedType;
  final String? planType;

  double? get remainingPercent => usedPercent == null
      ? null
      : (100 - usedPercent!).clamp(0, 100).toDouble();
}

final class AccountResetCredits {
  const AccountResetCredits({
    required this.availableCount,
    required this.nextExpiresAt,
  });

  final int availableCount;
  final DateTime? nextExpiresAt;
}

final class Account {
  Account({
    required this.profile,
    required this.metadata,
    required Iterable<AccountCostShare> costShares,
    required this.currentCheck,
    required Iterable<AccountQuotaWindow> currentWindows,
    required this.lastSuccessfulCheck,
    required Iterable<AccountQuotaWindow> lastSuccessfulWindows,
    required this.resetCredits,
  }) : costShares = List.unmodifiable(costShares),
       currentWindows = List.unmodifiable(currentWindows),
       lastSuccessfulWindows = List.unmodifiable(lastSuccessfulWindows);

  final Profile profile;
  final AccountMetadata? metadata;
  final List<AccountCostShare> costShares;
  final AccountUsageCheck? currentCheck;
  final List<AccountQuotaWindow> currentWindows;
  final AccountUsageCheck? lastSuccessfulCheck;
  final List<AccountQuotaWindow> lastSuccessfulWindows;
  final AccountResetCredits? resetCredits;

  bool get isDeactivated => profile.isDeactivated;

  bool get currentIsUsable =>
      currentCheck?.state == AccountUsageState.success ||
      currentCheck?.state == AccountUsageState.partial;

  AccountUsageIssue? get currentIssue {
    final check = currentCheck;
    if (check == null) return null;
    final code = check.errorCode?.toUpperCase();
    final message = check.errorMessage?.toLowerCase() ?? '';
    if (code == 'TOKEN_INVALIDATED' ||
        message.contains('token_invalidated') ||
        message.contains('token has been invalidated')) {
      return AccountUsageIssue.credentialInvalidated;
    }
    if (code == 'TOKEN_EXPIRED' ||
        message.contains('token_expired') ||
        message.contains('token is expired')) {
      return AccountUsageIssue.credentialExpired;
    }
    if (code == 'NETWORK_ERROR' ||
        message.contains('error sending request') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('failed host lookup')) {
      return AccountUsageIssue.network;
    }
    if (code == 'PARTIAL_METADATA') {
      return AccountUsageIssue.partialMetadata;
    }
    return null;
  }

  List<AccountQuotaWindow> get visibleWindows =>
      currentIsUsable && currentWindows.isNotEmpty
      ? currentWindows
      : lastSuccessfulWindows;

  double? get lowestAvailablePercent {
    double? lowest;
    for (final window in visibleWindows) {
      final remaining = window.remainingPercent;
      if (remaining == null) continue;
      if (lowest == null || remaining < lowest) lowest = remaining;
    }
    return lowest;
  }

  String get observedPlan =>
      currentCheck?.planType ?? lastSuccessfulCheck?.planType ?? '';

  String get displayPlan =>
      metadata?.planName.isNotEmpty == true ? metadata!.planName : observedPlan;

  String get displayEmail => metadata?.accountEmail.isNotEmpty == true
      ? metadata!.accountEmail
      : (currentCheck?.accountEmail ?? lastSuccessfulCheck?.accountEmail ?? '');

  DateTime? get nextResetAt {
    DateTime? next;
    for (final window in visibleWindows) {
      final reset = window.resetsAt;
      if (reset != null && (next == null || reset.isBefore(next))) {
        next = reset;
      }
    }
    return next;
  }

  bool get isReady {
    final provider = profileProvider(profile.toolKey);
    return profile.isAvailable && provider.supportsUsage
        ? currentIsUsable
        : profile.isAvailable && profile.hasAuthFile;
  }

  bool get needsAttention {
    final provider = profileProvider(profile.toolKey);
    return !profile.isAvailable ||
        (provider.supportsUsage && currentCheck != null && !isReady);
  }

  bool get isUnlinked => profile.isAvailable && !profile.hasAuthFile;
}
