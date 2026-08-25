import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/database/legacy_database_migrator.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryRoot;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp(
      'nini-hub-db-migration-test-',
    );
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  test('migrates every committed row retained in a WAL snapshot', () async {
    final source = await _createClosedWalSnapshot(
      temporaryRoot,
      name: 'legacy',
      label: 'source',
    );
    final destination = File(
      p.join(temporaryRoot.path, 'destination', 'multicli_ai.sqlite'),
    );
    expect(await File('${source.path}-wal').length(), greaterThan(32));

    final result = await LegacyDatabaseMigrator().migrate(
      source: source,
      destination: destination,
    );

    expect(result.outcome, LegacyDatabaseMigrationOutcome.migrated);
    expect(result.schemaVersion, 2);
    expect(result.rowCounts.keys, LegacyDatabaseMigrator.requiredTables);
    expect(result.rowCounts.values, everyElement(1));
    expect(await destination.exists(), isTrue);
    expect(await source.exists(), isTrue);

    final migrated = AppDatabase(
      NativeDatabase(destination, enableMigrations: false),
    );
    addTearDown(migrated.close);
    expect(
      await _applicationId(migrated),
      LegacyDatabaseMigrator.destinationApplicationId,
    );
    expect(await migrated.select(migrated.cliProfiles).get(), hasLength(1));
    expect(
      (await migrated.select(migrated.appSettings).getSingle()).settingValue,
      'source-value',
    );
  });

  test('repeats as an idempotent no-op for the same destination', () async {
    final source = await _createClosedWalSnapshot(
      temporaryRoot,
      name: 'legacy',
      label: 'same',
    );
    final destination = File(
      p.join(temporaryRoot.path, 'destination', 'multicli_ai.sqlite'),
    );
    final migrator = LegacyDatabaseMigrator();

    final first = await migrator.migrate(
      source: source,
      destination: destination,
    );
    final bytesBeforeRepeat = await destination.readAsBytes();
    final second = await migrator.migrate(
      source: source,
      destination: destination,
    );

    expect(first.outcome, LegacyDatabaseMigrationOutcome.migrated);
    expect(second.outcome, LegacyDatabaseMigrationOutcome.alreadyMigrated);
    expect(second.rowCounts, first.rowCounts);
    expect(await destination.readAsBytes(), bytesBeforeRepeat);
  });

  test('keeps legitimate Nini changes on startup after migration', () async {
    final source = await _createClosedWalSnapshot(
      temporaryRoot,
      name: 'legacy',
      label: 'changed',
    );
    final destination = File(
      p.join(temporaryRoot.path, 'destination', 'multicli_ai.sqlite'),
    );
    final migrator = LegacyDatabaseMigrator();
    await migrator.migrate(source: source, destination: destination);

    final active = AppDatabase(NativeDatabase(destination));
    await active.saveSetting('nini_only', 'preserved');
    await active.close();

    final repeated = await migrator.migrate(
      source: source,
      destination: destination,
    );
    expect(repeated.outcome, LegacyDatabaseMigrationOutcome.alreadyMigrated);
    expect(repeated.rowCounts['app_settings'], 2);

    final reopened = AppDatabase(NativeDatabase(destination));
    addTearDown(reopened.close);
    expect(await reopened.setting('nini_only'), 'preserved');
  });

  test('rejects a destination stamped by another application', () async {
    final source = await _createClosedWalSnapshot(
      temporaryRoot,
      name: 'legacy',
      label: 'foreign',
    );
    final destination = await _createClosedDatabase(
      temporaryRoot,
      name: 'destination.sqlite',
      label: 'foreign',
    );
    final destinationDatabase = AppDatabase(NativeDatabase(destination));
    await destinationDatabase.customStatement('PRAGMA application_id = 42');
    await destinationDatabase.close();

    await expectLater(
      LegacyDatabaseMigrator().migrate(
        source: source,
        destination: destination,
      ),
      throwsA(
        isA<LegacyDatabaseMigrationException>().having(
          (error) => error.kind,
          'kind',
          LegacyDatabaseMigrationFailureKind.destinationConflict,
        ),
      ),
    );
  });

  test(
    'does not overwrite a valid destination with different content',
    () async {
      final source = await _createClosedWalSnapshot(
        temporaryRoot,
        name: 'legacy',
        label: 'source',
      );
      final destination = await _createClosedDatabase(
        temporaryRoot,
        name: 'destination.sqlite',
        label: 'other',
      );
      final destinationBytes = await destination.readAsBytes();

      await expectLater(
        LegacyDatabaseMigrator().migrate(
          source: source,
          destination: destination,
        ),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.kind,
            'kind',
            LegacyDatabaseMigrationFailureKind.destinationConflict,
          ),
        ),
      );

      expect(await destination.readAsBytes(), destinationBytes);
    },
  );

  test('rejects source and destination resolving to the same path', () async {
    final source = await _createClosedWalSnapshot(
      temporaryRoot,
      name: 'legacy',
      label: 'same-path',
    );

    await expectLater(
      LegacyDatabaseMigrator().migrate(source: source, destination: source),
      throwsA(
        isA<LegacyDatabaseMigrationException>().having(
          (error) => error.kind,
          'kind',
          LegacyDatabaseMigrationFailureKind.samePath,
        ),
      ),
    );
  });

  test(
    'rejects an incompatible schema before creating a destination',
    () async {
      final source = await _createClosedDatabase(
        temporaryRoot,
        name: 'incompatible.sqlite',
        label: 'incompatible',
      );
      final database = AppDatabase(
        NativeDatabase(source, enableMigrations: false),
      );
      try {
        await database.customStatement('PRAGMA user_version = 1');
      } finally {
        await database.close();
      }
      final destination = File(
        p.join(temporaryRoot.path, 'destination', 'multicli_ai.sqlite'),
      );

      await expectLater(
        LegacyDatabaseMigrator().migrate(
          source: source,
          destination: destination,
        ),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.kind,
            'kind',
            LegacyDatabaseMigrationFailureKind.invalidSource,
          ),
        ),
      );
      expect(await destination.exists(), isFalse);
    },
  );

  test('requires the legacy database connection to be closed', () async {
    final source = File(p.join(temporaryRoot.path, 'open-source.sqlite'));
    final openDatabase = AppDatabase(NativeDatabase(source));
    await _seedAllTables(openDatabase, 'open');
    final destination = File(
      p.join(temporaryRoot.path, 'destination', 'multicli_ai.sqlite'),
    );

    try {
      await expectLater(
        LegacyDatabaseMigrator().migrate(
          source: source,
          destination: destination,
        ),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.kind,
            'kind',
            LegacyDatabaseMigrationFailureKind.sourceInUse,
          ),
        ),
      );
    } finally {
      await openDatabase.close();
    }
    expect(await destination.exists(), isFalse);
  });

  test(
    'cleans staging and keeps rollback when activation is interrupted',
    () async {
      final source = await _createClosedWalSnapshot(
        temporaryRoot,
        name: 'legacy',
        label: 'interrupt',
      );
      final destinationDirectory = Directory(
        p.join(temporaryRoot.path, 'destination'),
      );
      final destination = File(
        p.join(destinationDirectory.path, 'multicli_ai.sqlite'),
      );
      var hookCalled = false;
      final migrator = LegacyDatabaseMigrator(
        beforeActivate: (temporaryDestination) {
          hookCalled = true;
          expect(temporaryDestination.existsSync(), isTrue);
          throw StateError('synthetic interruption');
        },
      );

      await expectLater(
        migrator.migrate(source: source, destination: destination),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.kind,
            'kind',
            LegacyDatabaseMigrationFailureKind.activationFailed,
          ),
        ),
      );

      expect(hookCalled, isTrue);
      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isFalse);
      final leftovers = await destinationDirectory
          .list()
          .where(
            (entity) => p
                .basename(entity.path)
                .startsWith('.multicli_ai.sqlite.migration.'),
          )
          .toList();
      expect(leftovers, isEmpty);
    },
  );
}

Future<File> _createClosedWalSnapshot(
  Directory root, {
  required String name,
  required String label,
}) async {
  final active = File(p.join(root.path, '$name-active.sqlite'));
  final snapshot = File(p.join(root.path, '$name.sqlite'));
  final database = AppDatabase(NativeDatabase(active));
  try {
    await database.customSelect('SELECT 1').get();
    await database.customSelect('PRAGMA wal_autocheckpoint = 0').get();
    await database.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
    await _seedAllTables(database, label);

    final activeWal = File('${active.path}-wal');
    if (!await activeWal.exists() || await activeWal.length() <= 32) {
      throw StateError('The synthetic WAL fixture was not created.');
    }
    await active.copy(snapshot.path);
    await activeWal.copy('${snapshot.path}-wal');
  } finally {
    await database.close();
  }
  return snapshot;
}

Future<File> _createClosedDatabase(
  Directory root, {
  required String name,
  required String label,
}) async {
  final file = File(p.join(root.path, name));
  final database = AppDatabase(NativeDatabase(file));
  try {
    await _seedAllTables(database, label);
  } finally {
    await database.close();
  }
  return file;
}

Future<int> _applicationId(AppDatabase database) async {
  final row = await database.customSelect('PRAGMA application_id').getSingle();
  return row.read<int>('application_id');
}

Future<void> _seedAllTables(AppDatabase database, String label) async {
  final now = DateTime.utc(2026, 8, 24, 12);
  final profileId = '$label-profile';
  final checkId = '$label-check';

  await database.transaction(() async {
    await database
        .into(database.cliProfiles)
        .insert(
          CliProfilesCompanion.insert(
            id: profileId,
            profileName: label,
            displayName: 'Synthetic $label',
            profileHome: '/synthetic/profiles/$label',
            profileSource: 'fixture',
            profileType: 'persistent',
            createdAt: now,
            lastDiscoveredAt: now,
          ),
        );
    await database
        .into(database.profileMetadatas)
        .insert(
          ProfileMetadatasCompanion.insert(
            profileId: profileId,
            updatedAt: now,
          ),
        );
    await database
        .into(database.costShares)
        .insert(
          CostSharesCompanion.insert(
            id: '$label-share',
            profileId: profileId,
            personName: 'Synthetic owner',
          ),
        );
    await database
        .into(database.usageChecks)
        .insert(
          UsageChecksCompanion.insert(
            id: checkId,
            profileId: profileId,
            status: 'success',
            startedAt: now,
          ),
        );
    await database
        .into(database.quotaWindows)
        .insert(
          QuotaWindowsCompanion.insert(
            id: '$label-window',
            checkId: checkId,
            limitId: 'synthetic-limit',
            windowType: 'weekly',
          ),
        );
    await database
        .into(database.resetCreditSnapshots)
        .insert(ResetCreditSnapshotsCompanion.insert(checkId: checkId));
    await database
        .into(database.dailyUsageBuckets)
        .insert(
          DailyUsageBucketsCompanion.insert(
            id: '$label-bucket',
            checkId: checkId,
            profileId: profileId,
            day: now,
            tokens: const Value(42),
            source: 'fixture',
          ),
        );
    await database
        .into(database.commandLogs)
        .insert(
          CommandLogsCompanion.insert(
            id: '$label-command',
            profileId: Value(profileId),
            command: 'synthetic-command',
            summary: 'Synthetic summary',
            status: 'success',
            startedAt: now,
          ),
        );
    await database
        .into(database.workspaces)
        .insert(
          WorkspacesCompanion.insert(
            id: '$label-workspace',
            path: '/synthetic/workspaces/$label',
            pathKey: '/synthetic/workspaces/$label',
            name: 'Synthetic workspace',
            createdAt: now,
            lastUsedAt: now,
          ),
        );
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            settingKey: 'synthetic_setting',
            settingValue: '$label-value',
            updatedAt: now,
          ),
        );
  });
}
