import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/domain/agent_profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/workspaces/data/desktop_workspace_runtime.dart';
import 'package:nini_hub/features/workspaces/domain/agent_launcher.dart';
import 'package:path/path.dart' as p;

final class NiniAgentsAgentLauncher implements AgentLauncher {
  const NiniAgentsAgentLauncher(this._database, this._runner);

  final AppDatabase _database;
  final ProcessRunner _runner;

  @override
  Future<void> launch(
    AgentProfile profile, {
    required String workingDirectory,
  }) async {
    try {
      final launchDirectory = DesktopWorkspaceRuntime.validateWorkingDirectory(
        workingDirectory,
      );
      final title = DesktopWorkspaceRuntime.buildTerminalTitle(
        profileName: profile.profileName,
        workingDirectory: launchDirectory,
      );
      final provider = profileProvider(profile.toolKey);
      if (profile.profileSource == 'multicli') {
        final profilesRoot = p.dirname(
          p.dirname(p.normalize(p.absolute(profile.profileHome))),
        );
        await _runner.startInTerminal(
          executable: 'nini-agents',
          arguments: [
            'launch',
            provider.profileSpec(profile.profileName),
            if (provider.launchArguments.isNotEmpty) ...[
              '--',
              ...provider.launchArguments,
            ],
          ],
          summary: 'Abrir ${profile.displayName}',
          profileId: profile.id,
          workingDirectory: launchDirectory,
          title: title,
          environment: {
            'MULTICLI_HOME': profilesRoot,
            'NINI_AGENTS_HYPER_TITLE_LOCK': '1',
          },
        );
      } else {
        await _runner.startInTerminal(
          executable: provider.executable,
          arguments: provider.launchArguments,
          summary: 'Abrir ${provider.productName} principal',
          profileId: profile.id,
          workingDirectory: launchDirectory,
          title: title,
        );
      }
      await (_database.update(
        _database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).write(
        CliProfilesCompanion(lastLaunchedAt: Value(DateTime.now().toUtc())),
      );
    } on AgentLauncherFailure {
      rethrow;
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(const AgentLauncherFailure(), stackTrace);
    }
  }
}
