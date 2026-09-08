import 'package:nini_hub/features/profiles/domain/profile.dart';

/// An owned, unpublished profile prepared for authentication.
abstract interface class ProfileDraft {
  Profile get profile;
  Future<Profile> publish();
  Future<void> discard();
}

abstract interface class ProfileDraftStore {
  Future<ProfileDraft> prepare({
    required String toolKey,
    required ProfileName name,
    required String displayName,
    required ProfileSetupMode setupMode,
  });
}
