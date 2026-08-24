sealed class ProfileFailure implements Exception {
  const ProfileFailure();
}

final class ProfileNotFoundFailure extends ProfileFailure {
  const ProfileNotFoundFailure(this.profileId);

  final String profileId;
}

final class ProfileUnavailableFailure extends ProfileFailure {
  const ProfileUnavailableFailure(this.profileId);

  final String profileId;
}

final class InvalidProfileNameFailure extends ProfileFailure {
  const InvalidProfileNameFailure();
}

final class UnsupportedProfileToolFailure extends ProfileFailure {
  const UnsupportedProfileToolFailure(this.toolKey);

  final String toolKey;
}

final class ProfileNotManagedFailure extends ProfileFailure {
  const ProfileNotManagedFailure(this.profileId);

  final String profileId;
}

final class ProfileDeactivatedFailure extends ProfileFailure {
  const ProfileDeactivatedFailure(this.profileId);

  final String profileId;
}

final class ProfileNameUnchangedFailure extends ProfileFailure {
  const ProfileNameUnchangedFailure(this.profileId);

  final String profileId;
}

enum ProfileOperation { create, rename, delete }

final class ProfileResultNotFoundFailure extends ProfileFailure {
  const ProfileResultNotFoundFailure({
    required this.operation,
    this.profileId,
    this.toolKey,
    this.profileName,
  });

  final ProfileOperation operation;
  final String? profileId;
  final String? toolKey;
  final String? profileName;
}

final class ProfileMutationAppliedFailure extends ProfileFailure {
  const ProfileMutationAppliedFailure({
    required this.operation,
    required this.cause,
    this.profileId,
    this.profileName,
  });

  final ProfileOperation operation;
  final Object cause;
  final String? profileId;
  final String? profileName;
}
