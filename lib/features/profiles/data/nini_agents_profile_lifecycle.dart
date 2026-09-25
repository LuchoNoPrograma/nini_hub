import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:path/path.dart' as p;

final class NiniAgentsProfileLifecycle implements ProfileLifecycle {
  const NiniAgentsProfileLifecycle(
    this._database,
    this._client,
    this._discovery,
  );

  final AppDatabase _database;
  final NiniAgentsReadClient _client;
  final ProfileDiscoveryService _discovery;

  @override
  Future<void> create({
    required String toolKey,
    required ProfileName profileName,
    required ProfileSetupMode setupMode,
    required bool seedFromBase,
  }) async {
    final provider = profileProvider(toolKey);
    final root = await _discovery.profilesRoot();
    try {
      await _client.createProfile(
        tool: provider.multiCliTool,
        name: profileName.value,
        setupMode: switch (setupMode) {
          ProfileSetupMode.full => 'full',
          ProfileSetupMode.shared => 'shared',
          ProfileSetupMode.cli => 'cli',
        },
        seedFromBase: seedFromBase,
        profilesRoot: root,
      );
    } on NiniAgentsReadFailure catch (failure) {
      await _throwMappedFailure(
        failure: failure,
        operation: ProfileOperation.create,
        provider: provider,
        profileName: profileName.value,
        root: root,
      );
    }
  }

  @override
  Future<void> rename({
    required Profile profile,
    required ProfileName profileName,
  }) async {
    final provider = profileProvider(profile.toolKey);
    final root = await _discovery.profilesRoot();
    try {
      await _client.renameProfile(
        tool: provider.multiCliTool,
        currentName: profile.profileName,
        newName: profileName.value,
        profileId: profile.id,
        profilesRoot: root,
      );
    } on NiniAgentsReadFailure catch (failure) {
      await _throwMappedFailure(
        failure: failure,
        operation: ProfileOperation.rename,
        provider: provider,
        profile: profile,
        profileName: profileName.value,
        root: root,
      );
    }

    try {
      await _persistRename(
        profile: profile,
        provider: provider,
        profileName: profileName.value,
        root: root,
      );
    } catch (failure) {
      await _reconcileAndThrow(
        cause: failure,
        operation: ProfileOperation.rename,
        provider: provider,
        profile: profile,
        profileName: profileName.value,
        root: root,
      );
    }
  }

  @override
  Future<void> delete(Profile profile) async {
    final provider = profileProvider(profile.toolKey);
    final root = await _discovery.profilesRoot();
    try {
      await _client.deleteProfile(
        tool: provider.multiCliTool,
        name: profile.profileName,
        profileId: profile.id,
        profilesRoot: root,
      );
    } on NiniAgentsReadFailure catch (failure) {
      var confirmedAbsent = false;
      if (failure.code == 'profile_not_found' && !_mayHaveApplied(failure)) {
        try {
          final status = await _client.status(
            tool: provider.multiCliTool,
            profilesRoot: root,
          );
          confirmedAbsent = !_contains(
            status,
            provider.multiCliTool,
            profile.profileName,
          );
        } on NiniAgentsReadFailure {
          // A failed read is not a partially applied deletion. Keep local data.
          throw ProfileMutationRejectedFailure(
            operation: ProfileOperation.delete,
            reason: ProfileMutationRejectionReason.inconsistentResponse,
            profileId: profile.id,
            profileName: profile.profileName,
          );
        }
      }
      if (!confirmedAbsent) {
        await _throwMappedFailure(
          failure: failure,
          operation: ProfileOperation.delete,
          provider: provider,
          profile: profile,
          profileName: profile.profileName,
          root: root,
        );
      }
    }

    try {
      await _deletePersistedProfile(profile.id);
    } catch (failure) {
      await _reconcileAndThrow(
        cause: failure,
        operation: ProfileOperation.delete,
        provider: provider,
        profile: profile,
        profileName: profile.profileName,
        root: root,
      );
    }
  }

  Future<Never> _throwMappedFailure({
    required NiniAgentsReadFailure failure,
    required ProfileOperation operation,
    required ProfileProvider provider,
    required String profileName,
    required String root,
    Profile? profile,
  }) async {
    if (_mayHaveApplied(failure)) {
      await _reconcileAndThrow(
        cause: failure,
        operation: operation,
        provider: provider,
        profile: profile,
        profileName: profileName,
        root: root,
      );
    }

    switch (failure.code) {
      case 'invalid_identifier':
      case 'invalid_arguments':
        throw const InvalidProfileNameFailure();
      case 'profile_not_found':
        throw ProfileUnavailableFailure(
          profile?.id ?? '${provider.toolKey}/$profileName',
        );
      case 'profile_exists':
        throw ProfileMutationRejectedFailure(
          operation: operation,
          reason: ProfileMutationRejectionReason.alreadyExists,
          profileId: profile?.id,
          profileName: profileName,
        );
      case 'cross_tool_rename':
      case 'confirmation_required':
        throw ProfileMutationRejectedFailure(
          operation: operation,
          reason: ProfileMutationRejectionReason.inconsistentResponse,
          profileId: profile?.id,
          profileName: profileName,
        );
      default:
        throw ProfileMutationRejectedFailure(
          operation: operation,
          reason:
              failure.kind == NiniAgentsReadFailureKind.executableUnavailable
              ? ProfileMutationRejectionReason.engineUnavailable
              : ProfileMutationRejectionReason.rejected,
          profileId: profile?.id,
          profileName: profileName,
        );
    }
  }

  static bool _mayHaveApplied(NiniAgentsReadFailure failure) {
    if (failure.mutationState == NiniAgentsMutationState.partiallyApplied) {
      return true;
    }
    if (failure.mutationState == NiniAgentsMutationState.notApplied) {
      return false;
    }
    return failure.kind != NiniAgentsReadFailureKind.executableUnavailable;
  }

  Future<Never> _reconcileAndThrow({
    required Object cause,
    required ProfileOperation operation,
    required ProfileProvider provider,
    required String profileName,
    required String root,
    Profile? profile,
  }) async {
    try {
      final status = await _client.status(
        tool: provider.multiCliTool,
        profilesRoot: root,
      );
      final currentName = profile?.profileName;
      final currentExists =
          currentName != null &&
          _contains(status, provider.multiCliTool, currentName);
      final targetExists = _contains(
        status,
        provider.multiCliTool,
        profileName,
      );

      if (operation == ProfileOperation.rename &&
          profile != null &&
          targetExists &&
          !currentExists) {
        await _persistRename(
          profile: profile,
          provider: provider,
          profileName: profileName,
          root: root,
        );
      }
      if (operation == ProfileOperation.delete &&
          profile != null &&
          !targetExists) {
        await _deletePersistedProfile(profile.id);
      }
      await _discovery.reconcileProfiles(status);
    } catch (_) {
      // The original partial failure remains authoritative. Presentation will
      // attempt one more discovery before exposing the reconciled state.
    }
    throw ProfileMutationAppliedFailure(
      operation: operation,
      cause: cause,
      profileId: profile?.id,
      profileName: profileName,
    );
  }

  static bool _contains(
    NiniAgentsProfileList profiles,
    String tool,
    String name,
  ) => profiles.profiles.any(
    (profile) => profile.tool == tool && profile.name == name,
  );

  Future<void> _persistRename({
    required Profile profile,
    required ProfileProvider provider,
    required String profileName,
    required String root,
  }) =>
      (_database.update(
        _database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).write(
        CliProfilesCompanion(
          profileName: Value(profileName),
          commandName: Value(provider.commandName(profileName)),
          profileHome: Value(
            p.normalize(
              p.absolute(p.join(root, provider.multiCliTool, profileName)),
            ),
          ),
          lastDiscoveredAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> _deletePersistedProfile(String profileId) => (_database.delete(
    _database.cliProfiles,
  )..where((row) => row.id.equals(profileId))).go();
}
