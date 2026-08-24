import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/profiles/data/drift_agent_profile_repository.dart';

void main() {
  late AppDatabase database;
  late DriftAgentProfileRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftAgentProfileRepository(database);
  });

  tearDown(() => database.close());

  test('maps a persisted profile to the launch projection', () async {
    final now = DateTime.utc(2026, 8, 22);
    await database
        .into(database.cliProfiles)
        .insert(
          CliProfile(
            id: 'profile-id',
            toolKey: 'codex',
            profileName: 'team',
            commandName: 'codex-team',
            displayName: 'Team',
            profileHome: '/tmp/profiles/team',
            profileSource: 'multicli',
            profileType: 'full',
            hasAuthFile: true,
            isAvailable: true,
            isFavorite: true,
            createdAt: now,
            lastDiscoveredAt: now,
          ),
        );

    final profile = await repository.findById('profile-id');

    expect(profile, isNotNull);
    expect(profile!.id, 'profile-id');
    expect(profile.toolKey, 'codex');
    expect(profile.profileName, 'team');
    expect(profile.displayName, 'Team');
    expect(profile.profileHome, '/tmp/profiles/team');
    expect(profile.profileSource, 'multicli');
    expect(profile.hasAuthFile, isTrue);
    expect(profile.isAvailable, isTrue);
    expect(profile.canLaunch, isTrue);
    expect(await repository.findById('missing'), isNull);
  });
}
