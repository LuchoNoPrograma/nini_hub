import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/presentation/state/profiles_state.dart';

typedef ProfilesControllerDependenciesBuilder =
    ProfilesControllerDependencies Function(Ref<ProfilesState> ref);

final class ProfilesControllerDependencies {
  const ProfilesControllerDependencies({
    required this.discoverProfiles,
    required this.createProfile,
    required this.renameProfile,
    required this.deleteProfile,
    required this.updateProfileDisplay,
  });

  final DiscoverProfiles discoverProfiles;
  final CreateProfile createProfile;
  final RenameProfile renameProfile;
  final DeleteProfile deleteProfile;
  final UpdateProfileDisplay updateProfileDisplay;
}

final class ProfilesController extends Notifier<ProfilesState> {
  factory ProfilesController({
    required DiscoverProfiles discoverProfiles,
    required CreateProfile createProfile,
    required RenameProfile renameProfile,
    required DeleteProfile deleteProfile,
    required UpdateProfileDisplay updateProfileDisplay,
  }) => ProfilesController.composed(
    (_) => ProfilesControllerDependencies(
      discoverProfiles: discoverProfiles,
      createProfile: createProfile,
      renameProfile: renameProfile,
      deleteProfile: deleteProfile,
      updateProfileDisplay: updateProfileDisplay,
    ),
  );

  ProfilesController.composed(this._buildDependencies);

  final ProfilesControllerDependenciesBuilder _buildDependencies;
  late ProfilesControllerDependencies _dependencies;

  @override
  ProfilesState build() {
    _dependencies = _buildDependencies(ref);
    return ProfilesState();
  }

  Future<bool> load() async {
    if (!_begin(ProfilesOperation.load)) return false;
    try {
      final snapshot = await _dependencies.discoverProfiles();
      state = ProfilesState(profiles: snapshot.profiles, isInitialized: true);
      return true;
    } catch (error) {
      _completeFailure(error);
      return false;
    }
  }

  Future<Profile?> create(CreateProfileCommand command) async {
    if (!_begin(ProfilesOperation.create)) return null;
    try {
      final result = await _dependencies.createProfile(command);
      state = ProfilesState(
        profiles: result.snapshot.profiles,
        isInitialized: true,
      );
      return result.profile;
    } catch (error) {
      await _completeMutationFailure(error);
      return null;
    }
  }

  Future<Profile?> rename(RenameProfileCommand command) async {
    if (!_begin(ProfilesOperation.rename, profileId: command.profileId)) {
      return null;
    }
    try {
      final result = await _dependencies.renameProfile(command);
      state = ProfilesState(
        profiles: result.snapshot.profiles,
        isInitialized: true,
      );
      return result.profile;
    } catch (error) {
      await _completeMutationFailure(error);
      return null;
    }
  }

  Future<bool> delete(DeleteProfileCommand command) async {
    if (!_begin(ProfilesOperation.delete, profileId: command.profileId)) {
      return false;
    }
    try {
      final snapshot = await _dependencies.deleteProfile(command);
      state = ProfilesState(profiles: snapshot.profiles, isInitialized: true);
      return true;
    } catch (error) {
      await _completeMutationFailure(error);
      return false;
    }
  }

  Future<Profile?> updateDisplay(UpdateProfileDisplayCommand command) async {
    if (!_begin(
      ProfilesOperation.updateDisplay,
      profileId: command.profileId,
    )) {
      return null;
    }
    try {
      final updated = await _dependencies.updateProfileDisplay(command);
      state = ProfilesState(
        profiles: [
          for (final profile in state.profiles)
            if (profile.id == updated.id) updated else profile,
        ],
        isInitialized: state.isInitialized,
      );
      return updated;
    } catch (error) {
      _completeFailure(error);
      return null;
    }
  }

  void clearFailure() {
    if (state.failure == null && state.errorMessage == null) return;
    state = state.copyWith(failure: null, errorMessage: null);
  }

  bool _begin(ProfilesOperation operation, {String? profileId}) {
    if (state.isBusy) return false;
    state = state.copyWith(
      operation: operation,
      operationProfileId: profileId,
      failure: null,
      errorMessage: null,
    );
    return true;
  }

  void _completeFailure(Object error) {
    final operation = state.operation;
    state = state.copyWith(
      operation: null,
      operationProfileId: null,
      failure: error,
      errorMessage: _failureMessage(error, operation),
    );
  }

  Future<void> _completeMutationFailure(Object error) async {
    if (error is ProfileMutationAppliedFailure) {
      try {
        final snapshot = await _dependencies.discoverProfiles();
        state = ProfilesState(
          profiles: snapshot.profiles,
          isInitialized: true,
          failure: error,
          errorMessage: _failureMessage(error, state.operation),
        );
        return;
      } catch (_) {
        // Keep the original mutation failure as the user-facing cause.
      }
    }
    _completeFailure(error);
  }

  static String _failureMessage(
    Object error,
    ProfilesOperation? operation,
  ) => switch (error) {
    InvalidProfileNameFailure() =>
      'Usa entre 1 y 48 caracteres: letras, números, guion o guion bajo.',
    UnsupportedProfileToolFailure() =>
      'La herramienta seleccionada no es compatible.',
    ProfileNotFoundFailure() => 'El perfil ya no está disponible.',
    ProfileUnavailableFailure() => 'El perfil no está disponible.',
    ProfileDeactivatedFailure() => 'La cuenta está desactivada en este equipo.',
    ProfileNameUnchangedFailure() => 'El nombre físico no cambió.',
    ProfileNotManagedFailure() when operation == ProfilesOperation.rename =>
      'El perfil principal no puede renombrarse con Nini Agents.',
    ProfileNotManagedFailure() when operation == ProfilesOperation.delete =>
      'El perfil principal no se elimina desde esta aplicación.',
    ProfileNotManagedFailure() =>
      'El perfil principal no admite esta operación.',
    ProfileDiscoveryUnavailableFailure() =>
      'Nini Agents no pudo entregar la lista de perfiles.',
    ProfileMutationRejectedFailure(
      reason: ProfileMutationRejectionReason.alreadyExists,
    ) =>
      'Ya existe un perfil con ese nombre.',
    ProfileMutationRejectedFailure(
      reason: ProfileMutationRejectionReason.engineUnavailable,
    ) =>
      'Nini Agents no está disponible en este equipo.',
    ProfileMutationRejectedFailure(
      reason: ProfileMutationRejectionReason.inconsistentResponse,
    ) =>
      'Nini Agents devolvió una respuesta inconsistente.',
    ProfileMutationRejectedFailure() => switch (operation) {
      ProfilesOperation.create => 'Nini Agents rechazó crear el perfil.',
      ProfilesOperation.rename => 'Nini Agents rechazó renombrar el perfil.',
      ProfilesOperation.delete => 'Nini Agents rechazó eliminar el perfil.',
      _ => 'Nini Agents rechazó la operación.',
    },
    ProfileMutationAppliedFailure(:final operation) => switch (operation) {
      ProfileOperation.create =>
        'Nini Agents inició la creación, pero no confirmó el resultado.',
      ProfileOperation.rename =>
        'Nini Agents inició el cambio de nombre, pero no confirmó el resultado.',
      ProfileOperation.delete =>
        'Nini Agents inició la eliminación, pero no confirmó el resultado.',
    },
    ProfileResultNotFoundFailure() =>
      'La operación terminó, pero el perfil no apareció al actualizar.',
    _ => switch (operation) {
      ProfilesOperation.load => 'No se pudieron cargar los perfiles.',
      ProfilesOperation.create => 'No se pudo crear el perfil.',
      ProfilesOperation.rename => 'No se pudo renombrar el perfil.',
      ProfilesOperation.delete => 'No se pudo eliminar el perfil.',
      ProfilesOperation.updateDisplay =>
        'No se pudieron guardar los datos visibles del perfil.',
      null => 'No se pudo completar la operación.',
    },
  };
}
