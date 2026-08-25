import 'package:nini_hub/features/profiles/domain/profile.dart';

enum ProfilesOperation { load, create, rename, delete, updateDisplay }

final class ProfilesState {
  ProfilesState({
    List<Profile> profiles = const [],
    this.isInitialized = false,
    this.operation,
    this.operationProfileId,
    this.errorMessage,
    this.failure,
  }) : profiles = List.unmodifiable(profiles);

  static const _unset = Object();

  final List<Profile> profiles;
  final bool isInitialized;
  final ProfilesOperation? operation;
  final String? operationProfileId;
  final String? errorMessage;
  final Object? failure;

  bool get isBusy => operation != null;

  bool get isLoading => operation == ProfilesOperation.load;

  bool get isCreating => operation == ProfilesOperation.create;

  Profile? findById(String profileId) {
    for (final profile in profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  ProfilesState copyWith({
    List<Profile>? profiles,
    bool? isInitialized,
    Object? operation = _unset,
    Object? operationProfileId = _unset,
    Object? errorMessage = _unset,
    Object? failure = _unset,
  }) => ProfilesState(
    profiles: profiles ?? this.profiles,
    isInitialized: isInitialized ?? this.isInitialized,
    operation: identical(operation, _unset)
        ? this.operation
        : operation as ProfilesOperation?,
    operationProfileId: identical(operationProfileId, _unset)
        ? this.operationProfileId
        : operationProfileId as String?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    failure: identical(failure, _unset) ? this.failure : failure,
  );
}
