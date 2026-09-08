import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/usage/domain/quota_reset_anchor_policy.dart';

/// Mutually exclusive status shared by account cards, counts and filters.
enum AccountStatus {
  available,
  quotaExhausted,
  authRequired,
  deactivated,
  unlinked,
  unchecked,
  quotaUnconfirmed,
  queryError,
  unavailable,
}

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
}

final class AccountEditableMetadata {
  const AccountEditableMetadata({
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

  AccountEditableMetadata normalizedForSave() => AccountEditableMetadata(
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
  final AccountEditableMetadata metadata;
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
    this.completedAt,
    this.planType,
    this.accountEmail,
    this.accountDisplayName,
    this.errorCode,
    this.errorMessage,
  });

  final AccountUsageState state;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? planType;
  final String? accountEmail;
  final String? accountDisplayName;
  final String? errorCode;
  final String? errorMessage;

  DateTime get observedAt => completedAt ?? startedAt;
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

  double? get remainingPercent => usedPercent == null || !usedPercent!.isFinite
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
    this.previousSuccessfulCheck,
    Iterable<AccountQuotaWindow> previousSuccessfulWindows = const [],
    required this.resetCredits,
  }) : costShares = List.unmodifiable(costShares),
       currentWindows = List.unmodifiable(currentWindows),
       lastSuccessfulWindows = List.unmodifiable(lastSuccessfulWindows),
       previousSuccessfulWindows = List.unmodifiable(previousSuccessfulWindows);

  final Profile profile;
  final AccountMetadata? metadata;
  final List<AccountCostShare> costShares;
  final AccountUsageCheck? currentCheck;
  final List<AccountQuotaWindow> currentWindows;
  final AccountUsageCheck? lastSuccessfulCheck;
  final List<AccountQuotaWindow> lastSuccessfulWindows;
  final AccountUsageCheck? previousSuccessfulCheck;
  final List<AccountQuotaWindow> previousSuccessfulWindows;
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

  bool get _visibleUsesCurrent => currentIsUsable && currentWindows.isNotEmpty;

  AccountUsageCheck? get visibleCheck =>
      _visibleUsesCurrent ? currentCheck : lastSuccessfulCheck;

  List<AccountQuotaWindow> get visibleWindows =>
      _visibleUsesCurrent ? currentWindows : lastSuccessfulWindows;

  AccountUsageCheck? get previousVisibleCheck {
    if (!_visibleUsesCurrent) return previousSuccessfulCheck;
    if (currentCheck?.state == AccountUsageState.success) {
      return previousSuccessfulCheck;
    }
    return lastSuccessfulCheck;
  }

  List<AccountQuotaWindow> get previousVisibleWindows {
    if (!_visibleUsesCurrent) return previousSuccessfulWindows;
    if (currentCheck?.state == AccountUsageState.success) {
      return previousSuccessfulWindows;
    }
    return lastSuccessfulWindows;
  }

  QuotaResetAnchorConfidence resetAnchorConfidence(AccountQuotaWindow window) {
    final check = visibleCheck;
    if (check == null) return QuotaResetAnchorConfidence.unavailable;
    final previousWindow = _matchingWindow(previousVisibleWindows, window);
    final previousCheck = previousVisibleCheck;
    return QuotaResetAnchorPolicy.classify(
      current: _resetObservation(check, window),
      previous: previousWindow == null || previousCheck == null
          ? null
          : _resetObservation(previousCheck, previousWindow),
    );
  }

  /// Informational balance, including the last successful observation.
  /// Use [operationalAvailablePercent] for current availability decisions.
  double? get lowestAvailablePercent {
    double? lowest;
    for (final window in visibleWindows) {
      final remaining = window.remainingPercent;
      if (remaining == null) continue;
      if (lowest == null || remaining < lowest) lowest = remaining;
    }
    return lowest;
  }

  /// Current account-wide quota. Unknown or historical quota cannot establish
  /// availability; an exhausted window still proves that the account is blocked.
  /// This never changes the observed balance or reset of any individual window.
  double? get operationalAvailablePercent {
    if (isDeactivated ||
        !profile.isAvailable ||
        !profile.hasAuthFile ||
        !hasCurrentQuota) {
      return null;
    }
    if (hasExhaustedQuota) return 0;
    double? lowest;
    for (final window in currentWindows) {
      final remaining = window.remainingPercent;
      if (remaining == null) return null;
      if (lowest == null || remaining < lowest) lowest = remaining;
    }
    return lowest;
  }

  String get observedPlan =>
      currentCheck?.planType ?? lastSuccessfulCheck?.planType ?? '';

  String get displayPlan =>
      metadata?.planName.isNotEmpty == true ? metadata!.planName : observedPlan;

  String get observedEmail => _firstNonEmpty([
    currentCheck?.accountEmail,
    lastSuccessfulCheck?.accountEmail,
  ]);

  String get displayEmail =>
      _firstNonEmpty([observedEmail, metadata?.accountEmail]);

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

  /// Quotas from a previous successful query are informative, not evidence
  /// that the account can currently be used.
  bool get hasCurrentQuota => currentIsUsable && currentWindows.isNotEmpty;

  bool get hasExhaustedQuota =>
      hasCurrentQuota &&
      currentWindows.any((window) => window.remainingPercent == 0);

  bool get hasWeeklyLimitReached =>
      hasCurrentQuota &&
      currentWindows.any(
        (window) =>
            window.windowDurationMinutes == 10080 &&
            window.remainingPercent == 0,
      );

  /// Only windows in the same provider limit constrain one another.
  /// An unnamed limit is not enough evidence to associate two windows.
  AccountQuotaWindow? blockingWindowFor(AccountQuotaWindow window) {
    if (!hasCurrentQuota) return null;
    final limit = window.limitId.trim().toLowerCase();
    if (limit.isEmpty || window.remainingPercent == 0) return null;
    AccountQuotaWindow? blocking;
    for (final candidate in visibleWindows) {
      if (candidate.limitId.trim().toLowerCase() != limit ||
          candidate.remainingPercent != 0 ||
          identical(candidate, window)) {
        continue;
      }
      if (blocking == null ||
          (candidate.windowDurationMinutes ?? 0) >
              (blocking.windowDurationMinutes ?? 0)) {
        blocking = candidate;
      }
    }
    return blocking;
  }

  AccountStatus get status {
    if (isDeactivated) return AccountStatus.deactivated;
    if (!profile.isAvailable) return AccountStatus.unavailable;
    if (!profile.hasAuthFile) return AccountStatus.unlinked;
    if (!profileProvider(profile.toolKey).supportsUsage) {
      return AccountStatus.available;
    }
    if (currentCheck?.state == AccountUsageState.authRequired ||
        currentIssue == AccountUsageIssue.credentialExpired ||
        currentIssue == AccountUsageIssue.credentialInvalidated) {
      return AccountStatus.authRequired;
    }
    if (hasExhaustedQuota) return AccountStatus.quotaExhausted;
    return switch (currentCheck?.state) {
      null => AccountStatus.unchecked,
      AccountUsageState.success || AccountUsageState.partial =>
        isReady ? AccountStatus.available : AccountStatus.quotaUnconfirmed,
      AccountUsageState.authRequired => AccountStatus.authRequired,
      AccountUsageState.toolMissing ||
      AccountUsageState.profileMissing ||
      AccountUsageState.unavailable => AccountStatus.unavailable,
      AccountUsageState.timeout ||
      AccountUsageState.error => AccountStatus.queryError,
    };
  }

  bool get isReady {
    if (isDeactivated || !profile.isAvailable || !profile.hasAuthFile) {
      return false;
    }
    if (!profileProvider(profile.toolKey).supportsUsage) return true;
    return (operationalAvailablePercent ?? 0) > 0;
  }

  bool get needsAttention {
    final provider = profileProvider(profile.toolKey);
    return isDeactivated ||
        !profile.isAvailable ||
        (provider.supportsUsage &&
            profile.hasAuthFile &&
            currentCheck != null &&
            !isReady);
  }

  bool get isUnlinked => profile.isAvailable && !profile.hasAuthFile;

  static String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  static AccountQuotaWindow? _matchingWindow(
    Iterable<AccountQuotaWindow> candidates,
    AccountQuotaWindow current,
  ) {
    final limitId = current.limitId.trim().toLowerCase();
    final windowType = current.windowType.trim().toLowerCase();
    for (final candidate in candidates) {
      if (candidate.limitId.trim().toLowerCase() == limitId &&
          candidate.windowType.trim().toLowerCase() == windowType) {
        return candidate;
      }
    }
    return null;
  }

  static QuotaResetAnchorObservation _resetObservation(
    AccountUsageCheck check,
    AccountQuotaWindow window,
  ) => QuotaResetAnchorObservation(
    observedAt: check.observedAt,
    usedPercent: window.usedPercent,
    windowDurationMinutes: window.windowDurationMinutes,
    resetsAt: window.resetsAt,
  );
}
