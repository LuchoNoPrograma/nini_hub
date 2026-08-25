import 'package:nini_hub/features/profiles/domain/agent_profile.dart';

abstract interface class AgentProfileRepository {
  Future<AgentProfile?> findById(String profileId);
}
