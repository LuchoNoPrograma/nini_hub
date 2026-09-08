enum HeartbeatProfileUnavailableReason {
  unavailable,
  deactivated,
  missingCredential,
}

final class HeartbeatProfileNotFoundFailure implements Exception {
  const HeartbeatProfileNotFoundFailure(this.profileId);

  final String profileId;

  @override
  String toString() => 'Heartbeat profile not found: $profileId';
}

final class HeartbeatProfileUnavailableFailure implements Exception {
  const HeartbeatProfileUnavailableFailure({
    required this.profileId,
    required this.reason,
  });

  final String profileId;
  final HeartbeatProfileUnavailableReason reason;

  @override
  String toString() =>
      'Heartbeat profile unavailable: $profileId (${reason.name})';
}

final class HeartbeatUnsupportedProviderFailure implements Exception {
  const HeartbeatUnsupportedProviderFailure({
    required this.profileId,
    required this.toolKey,
  });

  final String profileId;
  final String toolKey;

  @override
  String toString() => 'Heartbeat is not supported for $toolKey ($profileId)';
}

enum HeartbeatAppliedProgress {
  statePersisted,
  verificationPersisted,
  usageRead,
}

final class HeartbeatAppliedFailure implements Exception {
  const HeartbeatAppliedFailure({
    required this.profileId,
    required this.progress,
    required this.cause,
  });

  final String profileId;
  final HeartbeatAppliedProgress progress;
  final Object cause;

  @override
  String toString() =>
      'Heartbeat partially applied for $profileId through ${progress.name}: '
      '$cause';
}
