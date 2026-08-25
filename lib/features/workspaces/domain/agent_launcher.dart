import 'package:nini_hub/features/profiles/domain/agent_profile.dart';

abstract interface class AgentLauncher {
  Future<void> launch(AgentProfile profile, {required String workingDirectory});
}

final class AgentLauncherFailure implements Exception {
  const AgentLauncherFailure();
}
