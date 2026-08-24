import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/profiles/domain/agent_profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/agent_profile_repository.dart';

final class DriftAgentProfileRepository implements AgentProfileRepository {
  const DriftAgentProfileRepository(this._database);

  final AppDatabase _database;

  @override
  Future<AgentProfile?> findById(String profileId) async {
    final row = await (_database.select(
      _database.cliProfiles,
    )..where((item) => item.id.equals(profileId))).getSingleOrNull();
    if (row == null) return null;
    return AgentProfile(
      id: row.id,
      toolKey: row.toolKey,
      profileName: row.profileName,
      displayName: row.displayName,
      profileHome: row.profileHome,
      profileSource: row.profileSource,
      hasAuthFile: row.hasAuthFile,
      isAvailable: row.isAvailable,
    );
  }
}
