import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/profiles/data/drift_profile_repository.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';

void main() {
  late AppDatabase database;
  late DriftProfileRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftProfileRepository(database);
  });

  tearDown(() => database.close());

  test(
    'maps persisted sources, kinds, nullability, and visible data',
    () async {
      const cases = <(String, String, ProfileSource, ProfileKind)>[
        ('default', 'base', ProfileSource.defaultProfile, ProfileKind.base),
        ('multicli', 'full', ProfileSource.multiCli, ProfileKind.full),
        ('multicli', 'shared', ProfileSource.multiCli, ProfileKind.shared),
        ('multicli', 'cli', ProfileSource.multiCli, ProfileKind.cli),
        (
          'multicli',
          'deactivated',
          ProfileSource.multiCli,
          ProfileKind.deactivated,
        ),
      ];

      for (var index = 0; index < cases.length; index++) {
        final (source, type, expectedSource, expectedKind) = cases[index];
        final row = _row(
          id: 'profile-$index',
          profileHome: '/profiles/profile-$index',
          profileSource: source,
          profileType: type,
          commandName: index == 0 ? null : 'codex-profile-$index',
        );
        await database.into(database.cliProfiles).insert(row);

        final profile = await repository.findById(row.id);

        expect(profile, isNotNull);
        expect(profile!.id, row.id);
        expect(profile.toolKey, row.toolKey);
        expect(profile.profileName, row.profileName);
        expect(profile.commandName, row.commandName);
        expect(profile.displayName, row.displayName);
        expect(profile.profileHome, row.profileHome);
        expect(profile.source, expectedSource);
        expect(profile.kind, expectedKind);
        expect(profile.hasAuthFile, row.hasAuthFile);
        expect(profile.isAvailable, row.isAvailable);
        expect(profile.isFavorite, row.isFavorite);
      }

      expect(await repository.findById('missing'), isNull);
    },
  );

  test(
    'updates only display data and preserves persisted timestamps',
    () async {
      final row = _row();
      await database.into(database.cliProfiles).insert(row);

      await repository.saveDisplayData(
        profileId: row.id,
        displayName: 'Equipo',
        isFavorite: false,
      );

      final stored = await (database.select(
        database.cliProfiles,
      )..where((item) => item.id.equals(row.id))).getSingle();
      expect(stored.displayName, 'Equipo');
      expect(stored.isFavorite, isFalse);
      expect(stored.id, row.id);
      expect(stored.profileName, row.profileName);
      expect(stored.profileHome, row.profileHome);
      expect(
        stored.createdAt.millisecondsSinceEpoch,
        row.createdAt.millisecondsSinceEpoch,
      );
      expect(
        stored.lastDiscoveredAt.millisecondsSinceEpoch,
        row.lastDiscoveredAt.millisecondsSinceEpoch,
      );
      expect(
        stored.lastLaunchedAt?.millisecondsSinceEpoch,
        row.lastLaunchedAt?.millisecondsSinceEpoch,
      );
    },
  );

  test('rejects unknown persisted source and type values', () async {
    final unknownSource = _row(
      id: 'unknown-source',
      profileHome: '/profiles/unknown-source',
      profileSource: 'other',
    );
    final unknownType = _row(
      id: 'unknown-type',
      profileHome: '/profiles/unknown-type',
      profileType: 'other',
    );
    await database.into(database.cliProfiles).insert(unknownSource);
    await database.into(database.cliProfiles).insert(unknownType);

    await expectLater(
      repository.findById(unknownSource.id),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.findById(unknownType.id),
      throwsA(isA<StateError>()),
    );
  });
}

CliProfile _row({
  String id = 'profile-id',
  String profileHome = '/profiles/team',
  String profileSource = 'multicli',
  String profileType = 'full',
  String? commandName = 'codex-team',
}) => CliProfile(
  id: id,
  toolKey: 'codex',
  profileName: 'team',
  commandName: commandName,
  displayName: 'Team',
  profileHome: profileHome,
  profileSource: profileSource,
  profileType: profileType,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: true,
  createdAt: DateTime.utc(2025, 1, 2),
  lastDiscoveredAt: DateTime.utc(2025, 2, 3),
  lastLaunchedAt: DateTime.utc(2025, 3, 4),
);
