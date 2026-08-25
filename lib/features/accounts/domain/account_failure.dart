enum AccountUpdateProgress { displaySaved, detailsSaved }

enum AccountDeviceAuthProgress {
  startRecorded,
  completionRecorded,
  authenticationPersisted,
  profilesSynchronized,
  usageRefreshed,
}

final class AccountNotFoundFailure implements Exception {
  const AccountNotFoundFailure(this.profileId);

  final String profileId;

  @override
  String toString() => 'Account not found: $profileId';
}

final class AccountUpdateResultNotFoundFailure implements Exception {
  const AccountUpdateResultNotFoundFailure(this.profileId);

  final String profileId;

  @override
  String toString() => 'Updated account not found: $profileId';
}

final class AccountUpdateAppliedFailure implements Exception {
  const AccountUpdateAppliedFailure({
    required this.profileId,
    required this.progress,
    required this.cause,
  });

  final String profileId;
  final AccountUpdateProgress progress;
  final Object cause;

  @override
  String toString() =>
      'Account update partially applied for $profileId '
      'through ${progress.name}: $cause';
}

final class AccountDeviceAuthAppliedFailure implements Exception {
  const AccountDeviceAuthAppliedFailure({
    required this.profileId,
    required this.progress,
    required this.cause,
  });

  final String profileId;
  final AccountDeviceAuthProgress progress;
  final Object cause;

  @override
  String toString() => cause.toString();
}
