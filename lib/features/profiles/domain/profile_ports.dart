import 'package:nini_hub/features/profiles/domain/profile.dart';

abstract interface class ProfileRepository {
  Future<Profile?> findById(String profileId);

  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  });
}

abstract interface class ProfileDiscovery {
  Future<List<Profile>> discover();
}

abstract interface class ProfileLifecycle {
  Future<void> create({
    required String toolKey,
    required ProfileName profileName,
    required ProfileSetupMode setupMode,
    required bool seedFromBase,
  });

  Future<void> rename({
    required Profile profile,
    required ProfileName profileName,
  });

  Future<void> delete(Profile profile);
}
