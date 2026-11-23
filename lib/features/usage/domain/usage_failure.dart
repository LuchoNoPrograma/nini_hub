import 'package:nini_hub/features/usage/domain/usage.dart';

enum UsageProfileUnavailableReason { unavailable, deactivated }

final class UsageProfileNotFoundFailure implements Exception {
  const UsageProfileNotFoundFailure(this.profileId);

  final String profileId;

  @override
  String toString() => 'Usage profile not found: $profileId';
}

final class UsageProfileUnavailableFailure implements Exception {
  const UsageProfileUnavailableFailure({
    required this.profileId,
    required this.reason,
  });

  final String profileId;
  final UsageProfileUnavailableReason reason;

  @override
  String toString() => 'Usage profile unavailable: $profileId (${reason.name})';
}

final class UsageUnsupportedProviderFailure implements Exception {
  const UsageUnsupportedProviderFailure({
    required this.profileId,
    required this.toolKey,
  });

  final String profileId;
  final String toolKey;

  @override
  String toString() => 'Usage is not supported for $toolKey ($profileId)';
}

enum UsageResetCreditFailureReason {
  /// Nothing was sent: the tool or the profile folder is missing.
  notSent,

  /// The provider rejected the session; nothing was spent.
  authRequired,

  /// The provider answered with an error; nothing was spent.
  rejected,

  /// No answer arrived, so the credit may or may not have been spent.
  outcomeUnknown,
}

final class UsageResetCreditFailure implements Exception {
  const UsageResetCreditFailure({
    required this.profileId,
    required this.reason,
    required this.detail,
  });

  final String profileId;
  final UsageResetCreditFailureReason reason;

  /// Sanitized provider diagnostic, for the activity log only.
  final String detail;

  @override
  String toString() =>
      'Reset credit failed for $profileId (${reason.name}): $detail';
}

enum UsageRefreshProgress { snapshotPersisted, activityRecorded }

final class UsageRefreshAppliedFailure implements Exception {
  const UsageRefreshAppliedFailure({
    required this.profileId,
    required this.progress,
    required this.snapshot,
    required this.cause,
  });

  final String profileId;
  final UsageRefreshProgress progress;
  final UsageSnapshot snapshot;
  final Object cause;

  @override
  String toString() =>
      'Usage refresh partially applied for $profileId '
      'through ${progress.name}: $cause';
}

final class UsageBatchFailure implements Exception {
  UsageBatchFailure({
    required this.failedProfileId,
    required Map<String, UsageSnapshot> completedByProfile,
    required this.cause,
  }) : completedByProfile = Map.unmodifiable(completedByProfile);

  final String failedProfileId;
  final Map<String, UsageSnapshot> completedByProfile;
  final Object cause;

  @override
  String toString() =>
      'Usage batch failed for $failedProfileId after '
      '${completedByProfile.length} completed profiles: $cause';
}
