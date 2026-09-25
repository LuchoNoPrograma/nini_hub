import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';

final class ProfileSnapshot {
  ProfileSnapshot(Iterable<Profile> profiles)
    : profiles = List.unmodifiable(profiles);

  final List<Profile> profiles;

  Profile? findById(String profileId) {
    for (final profile in profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  ProfileSnapshot replace(Profile updated) => ProfileSnapshot([
    for (final profile in profiles)
      if (profile.id == updated.id) updated else profile,
  ]);
}

final class CreateProfileCommand {
  const CreateProfileCommand({
    required this.toolKey,
    required this.name,
    required this.displayName,
    this.setupMode = ProfileSetupMode.full,
    this.seedFromBase = false,
  });

  final String toolKey;
  final String name;
  final String displayName;
  final ProfileSetupMode setupMode;
  final bool seedFromBase;
}

final class RenameProfileCommand {
  const RenameProfileCommand({required this.profileId, required this.name});

  final String profileId;
  final String name;
}

final class DeleteProfileCommand {
  const DeleteProfileCommand(this.profileId);

  final String profileId;
}

final class UpdateProfileDisplayCommand {
  const UpdateProfileDisplayCommand({
    required this.profileId,
    required this.displayName,
    required this.isFavorite,
  });

  final String profileId;
  final String displayName;
  final bool isFavorite;
}

final class CreateProfileResult {
  const CreateProfileResult({required this.profile, required this.snapshot});

  final Profile profile;
  final ProfileSnapshot snapshot;
}

final class RenameProfileResult {
  const RenameProfileResult({required this.profile, required this.snapshot});

  final Profile profile;
  final ProfileSnapshot snapshot;
}

final class DiscoverProfiles {
  const DiscoverProfiles({required this.discovery});

  final ProfileDiscovery discovery;

  Future<ProfileSnapshot> call() async =>
      ProfileSnapshot(await discovery.discover());
}

final class CreateProfile {
  const CreateProfile({
    required this.repository,
    required this.discovery,
    required this.lifecycle,
  });

  final ProfileRepository repository;
  final ProfileDiscovery discovery;
  final ProfileLifecycle lifecycle;

  Future<CreateProfileResult> call(CreateProfileCommand command) async {
    final profileName = ProfileName(command.name);
    if (profileProviderOrNull(command.toolKey) == null) {
      throw UnsupportedProfileToolFailure(command.toolKey);
    }

    await lifecycle.create(
      toolKey: command.toolKey,
      profileName: profileName,
      setupMode: command.setupMode,
      seedFromBase: command.seedFromBase,
    );

    try {
      var snapshot = ProfileSnapshot(await discovery.discover());
      Profile? created;
      for (final profile in snapshot.profiles) {
        if (profile.toolKey == command.toolKey &&
            profile.profileName == profileName.value &&
            profile.source == ProfileSource.multiCli) {
          created = profile;
          break;
        }
      }
      if (created == null) {
        throw ProfileMutationAppliedFailure(
          operation: ProfileOperation.create,
          profileName: profileName.value,
          cause: ProfileResultNotFoundFailure(
            operation: ProfileOperation.create,
            toolKey: command.toolKey,
            profileName: profileName.value,
          ),
        );
      }

      final displayName = command.displayName.trim();
      if (displayName.isNotEmpty) {
        await repository.saveDisplayData(
          profileId: created.id,
          displayName: displayName,
          isFavorite: false,
        );
        created = created.withDisplayData(
          displayName: displayName,
          isFavorite: false,
        );
        snapshot = snapshot.replace(created);
      }
      return CreateProfileResult(profile: created, snapshot: snapshot);
    } catch (error) {
      if (error is ProfileMutationAppliedFailure) rethrow;
      throw ProfileMutationAppliedFailure(
        operation: ProfileOperation.create,
        profileName: profileName.value,
        cause: error,
      );
    }
  }
}

final class RenameProfile {
  const RenameProfile({
    required this.repository,
    required this.discovery,
    required this.lifecycle,
  });

  final ProfileRepository repository;
  final ProfileDiscovery discovery;
  final ProfileLifecycle lifecycle;

  Future<RenameProfileResult> call(RenameProfileCommand command) async {
    final profile = await repository.findById(command.profileId);
    if (profile == null) {
      throw ProfileNotFoundFailure(command.profileId);
    }
    if (profile.isDeactivated) {
      throw ProfileDeactivatedFailure(command.profileId);
    }
    if (!profile.isManagedByMultiCli) {
      throw ProfileNotManagedFailure(command.profileId);
    }
    final profileName = ProfileName(command.name);
    if (profileName.value == profile.profileName) {
      throw ProfileNameUnchangedFailure(command.profileId);
    }
    if (profileProviderOrNull(profile.toolKey) == null) {
      throw UnsupportedProfileToolFailure(profile.toolKey);
    }

    await lifecycle.rename(profile: profile, profileName: profileName);

    try {
      final snapshot = ProfileSnapshot(await discovery.discover());
      final renamed = snapshot.findById(profile.id);
      if (renamed == null) {
        throw ProfileMutationAppliedFailure(
          operation: ProfileOperation.rename,
          profileId: profile.id,
          profileName: profileName.value,
          cause: ProfileResultNotFoundFailure(
            operation: ProfileOperation.rename,
            profileId: profile.id,
            profileName: profileName.value,
          ),
        );
      }
      return RenameProfileResult(profile: renamed, snapshot: snapshot);
    } catch (error) {
      if (error is ProfileMutationAppliedFailure) rethrow;
      throw ProfileMutationAppliedFailure(
        operation: ProfileOperation.rename,
        profileId: profile.id,
        profileName: profileName.value,
        cause: error,
      );
    }
  }
}

final class DeleteProfile {
  const DeleteProfile({
    required this.repository,
    required this.discovery,
    required this.lifecycle,
  });

  final ProfileRepository repository;
  final ProfileDiscovery discovery;
  final ProfileLifecycle lifecycle;

  Future<ProfileSnapshot> call(DeleteProfileCommand command) async {
    final profile = await repository.findById(command.profileId);
    if (profile == null) {
      throw ProfileNotFoundFailure(command.profileId);
    }
    if (!profile.isManagedByMultiCli) {
      throw ProfileNotManagedFailure(command.profileId);
    }
    if (profileProviderOrNull(profile.toolKey) == null) {
      throw UnsupportedProfileToolFailure(profile.toolKey);
    }

    await lifecycle.delete(profile);

    try {
      return ProfileSnapshot(await discovery.discover());
    } catch (error) {
      if (error is ProfileMutationAppliedFailure) rethrow;
      throw ProfileMutationAppliedFailure(
        operation: ProfileOperation.delete,
        profileId: profile.id,
        profileName: profile.profileName,
        cause: error,
      );
    }
  }
}

final class UpdateProfileDisplay {
  const UpdateProfileDisplay({required this.repository});

  final ProfileRepository repository;

  Future<Profile> call(UpdateProfileDisplayCommand command) async {
    final profile = await repository.findById(command.profileId);
    if (profile == null) {
      throw ProfileNotFoundFailure(command.profileId);
    }
    final displayName = profile.normalizedDisplayName(command.displayName);
    await repository.saveDisplayData(
      profileId: profile.id,
      displayName: displayName,
      isFavorite: command.isFavorite,
    );
    return profile.withDisplayData(
      displayName: displayName,
      isFavorite: command.isFavorite,
    );
  }
}
