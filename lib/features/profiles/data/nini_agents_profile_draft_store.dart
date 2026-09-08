import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/features/profiles/data/drift_profile_repository.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_draft.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

final class NiniAgentsProfileDraftStore implements ProfileDraftStore {
  NiniAgentsProfileDraftStore(this.client, this.discovery);
  final NiniAgentsReadClient client;
  final ProfileDiscoveryService discovery;

  @override
  Future<ProfileDraft> prepare({
    required String toolKey,
    required ProfileName name,
    required String displayName,
    required ProfileSetupMode setupMode,
  }) async {
    final provider = profileProvider(toolKey);
    final root = await discovery.profilesRoot();
    final home = p.normalize(
      p.absolute(p.join(root, provider.multiCliTool, name.value)),
    );
    discovery.reservePendingProfile(home);
    try {
      await client.createProfile(
        tool: provider.multiCliTool,
        name: name.value,
        setupMode: setupMode.name,
        seedFromBase: false,
        profilesRoot: root,
      );
    } on NiniAgentsReadFailure catch (error) {
      discovery.releasePendingProfile(home);
      if (error.mutationState != NiniAgentsMutationState.notApplied &&
          error.kind != NiniAgentsReadFailureKind.executableUnavailable) {
        // An ambiguous create is not proof of ownership: never delete by name.
        throw ProfileMutationAppliedFailure(
          operation: ProfileOperation.create,
          profileName: name.value,
          cause: error,
        );
      }
      throw ProfileMutationRejectedFailure(
        operation: ProfileOperation.create,
        profileName: name.value,
        reason: error.code == 'profile_exists'
            ? ProfileMutationRejectionReason.alreadyExists
            : ProfileMutationRejectionReason.rejected,
      );
    } catch (_) {
      discovery.releasePendingProfile(home);
      rethrow;
    }
    return _NiniAgentsProfileDraft(
      client,
      discovery,
      root,
      Profile(
        id: const Uuid().v4(),
        toolKey: toolKey,
        profileName: name.value,
        displayName: displayName.trim().isEmpty
            ? name.value
            : displayName.trim(),
        profileHome: home,
        source: ProfileSource.multiCli,
        kind: switch (setupMode) {
          ProfileSetupMode.shared => ProfileKind.shared,
          ProfileSetupMode.full => ProfileKind.full,
          ProfileSetupMode.cli => ProfileKind.cli,
        },
        commandName: provider.commandName(name.value),
        hasAuthFile: false,
        isAvailable: true,
        isFavorite: false,
      ),
    );
  }
}

final class _NiniAgentsProfileDraft implements ProfileDraft {
  _NiniAgentsProfileDraft(this.client, this.discovery, this.root, this.profile);
  final NiniAgentsReadClient client;
  final ProfileDiscoveryService discovery;
  final String root;
  @override
  final Profile profile;
  bool finished = false;

  @override
  Future<Profile> publish() async {
    if (finished) throw StateError('Profile draft already finished');
    // Authentication is already confirmed. A publication failure must preserve it.
    finished = true;
    discovery.releasePendingProfile(profile.profileHome);
    final profiles = await discovery.discover();
    final published = profiles
        .where((p) => p.profileHome == profile.profileHome)
        .firstOrNull;
    if (published == null) {
      throw ProfileResultNotFoundFailure(
        operation: ProfileOperation.create,
        profileName: profile.profileName,
        toolKey: profile.toolKey,
      );
    }
    await DriftProfileRepository(discovery.database).saveDisplayData(
      profileId: published.id,
      displayName: profile.displayName,
      isFavorite: false,
    );
    return published.withDisplayData(
      displayName: profile.displayName,
      isFavorite: false,
    );
  }

  @override
  Future<void> discard() async {
    if (finished) return;
    final tool = profileProvider(profile.toolKey).multiCliTool;
    try {
      try {
        await client.deleteProfile(
          tool: tool,
          name: profile.profileName,
          profilesRoot: root,
          profileId: profile.id,
        );
      } on NiniAgentsReadFailure {
        // A delete may succeed externally and lose its response.
        final status = await client.status(tool: tool, profilesRoot: root);
        if (status.profiles.any(
          (p) => p.tool == tool && p.name == profile.profileName,
        )) {
          rethrow;
        }
      }
      finished = true;
    } finally {
      // Failed cleanup remains discoverable for explicit recovery.
      discovery.releasePendingProfile(profile.profileHome);
    }
  }
}
