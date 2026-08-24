import 'package:multi_cli_ai/features/profiles/domain/agent_profile.dart';

abstract interface class AgentProfileRepository {
  Future<AgentProfile?> findById(String profileId);
}
