import 'package:nini_hub/features/profiles/domain/agent_profile.dart';

abstract interface class AgentLauncher {
  Future<void> launch(AgentProfile profile, {required String workingDirectory});
}

/// Why a launch failed, limited to the causes the user can act on.
enum AgentLauncherFailureReason {
  workingDirectoryMissing,
  terminalUnavailable,
  unknown,
}

final class AgentLauncherFailure implements Exception {
  const AgentLauncherFailure({
    this.reason = AgentLauncherFailureReason.unknown,
  });

  final AgentLauncherFailureReason reason;
}
