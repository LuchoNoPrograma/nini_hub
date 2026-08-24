import 'package:multi_cli_ai/features/profiles/data/multi_cli_gateway.dart';
import 'package:multi_cli_ai/features/profiles/domain/agent_profile.dart';
import 'package:multi_cli_ai/features/workspaces/domain/agent_launcher.dart';

final class MultiCliAgentLauncher implements AgentLauncher {
  const MultiCliAgentLauncher(this._gateway);

  final MultiCliGateway _gateway;

  @override
  Future<void> launch(
    AgentProfile profile, {
    required String workingDirectory,
  }) async {
    try {
      await _gateway.launchAgentProfile(
        profile,
        workingDirectory: workingDirectory,
      );
    } on AgentLauncherFailure {
      rethrow;
    } catch (_, stackTrace) {
      Error.throwWithStackTrace(const AgentLauncherFailure(), stackTrace);
    }
  }
}
