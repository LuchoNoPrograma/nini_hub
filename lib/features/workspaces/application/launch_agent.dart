import 'package:multi_cli_ai/features/profiles/domain/agent_profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/agent_profile_repository.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_failure.dart';
import 'package:multi_cli_ai/features/workspaces/domain/agent_launcher.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace_failure.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace_repository.dart';

final class LaunchAgentCommand {
  const LaunchAgentCommand({
    required this.profileId,
    required this.workspaceId,
  });

  final String profileId;
  final String workspaceId;
}

final class LaunchAgentResult {
  const LaunchAgentResult({required this.profile, required this.workspace});

  final AgentProfile profile;
  final Workspace workspace;
}

final class LaunchAgent {
  const LaunchAgent({
    required this.profileRepository,
    required this.workspaceRepository,
    required this.selectionStore,
    required this.launcher,
  });

  final AgentProfileRepository profileRepository;
  final WorkspaceRepository workspaceRepository;
  final WorkspaceSelectionStore selectionStore;
  final AgentLauncher launcher;

  Future<LaunchAgentResult> call(LaunchAgentCommand command) async {
    final profile = await profileRepository.findById(command.profileId);
    if (profile == null) {
      throw ProfileNotFoundFailure(command.profileId);
    }
    if (!profile.canLaunch) {
      throw ProfileUnavailableFailure(command.profileId);
    }

    final workspace = await workspaceRepository.findById(command.workspaceId);
    if (workspace == null) {
      throw const WorkspaceNotFoundFailure();
    }

    await launcher.launch(profile, workingDirectory: workspace.path);
    final openedWorkspace = await workspaceRepository.recordOpened(
      workspace.path,
    );
    await selectionStore.saveCurrentWorkspaceId(openedWorkspace.id);

    return LaunchAgentResult(profile: profile, workspace: openedWorkspace);
  }
}
