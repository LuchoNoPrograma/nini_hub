import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/app_startup.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/database/database_bootstrap.dart';
import 'package:nini_hub/core/database/legacy_database_migrator.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DatabaseBootstrap', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('nini_hub_bootstrap_test.');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('migrates the Linux legacy database before opening target', () async {
      final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));
      final source = File(
        p.join(
          root.path,
          DatabaseBootstrap.linuxLegacyApplicationId,
          DatabaseBootstrap.databaseFileName,
        ),
      );
      await _createClosedDatabase(source, label: 'linux');

      final result = await _bootstrap(
        supportDirectory,
        DatabaseBootstrapPlatform.linux,
      ).open();
      addTearDown(result.database.close);

      expect(result.outcome, DatabaseBootstrapOutcome.migrated);
      expect(
        result.destination.path,
        p.join(supportDirectory.path, 'multicli_ai.sqlite'),
      );
      expect(result.legacySource.path, source.path);
      expect(await source.exists(), isTrue);
      expect(result.migration?.schemaVersion, 2);
      expect(result.migration?.rowCounts['cli_profiles'], 1);
      expect(
        await result.database.select(result.database.cliProfiles).get(),
        hasLength(1),
      );
    });

    test('derives the Windows legacy product directory', () async {
      final companyDirectory = Directory(
        p.join(root.path, 'Roaming', 'com.nini'),
      );
      final supportDirectory = Directory(
        p.join(companyDirectory.path, 'Nini Hub'),
      );
      final source = File(
        p.join(
          companyDirectory.path,
          DatabaseBootstrap.windowsLegacyProductName,
          DatabaseBootstrap.databaseFileName,
        ),
      );
      await _createClosedDatabase(source, label: 'windows');

      final result = await _bootstrap(
        supportDirectory,
        DatabaseBootstrapPlatform.windows,
      ).open();
      addTearDown(result.database.close);

      expect(result.outcome, DatabaseBootstrapOutcome.migrated);
      expect(result.legacySource.path, source.path);
      expect(
        result.destination.path,
        p.join(supportDirectory.path, DatabaseBootstrap.databaseFileName),
      );
    });

    test(
      'opens a fresh explicit target when no legacy source exists',
      () async {
        final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));

        final result = await _bootstrap(
          supportDirectory,
          DatabaseBootstrapPlatform.linux,
        ).open();
        addTearDown(result.database.close);

        expect(result.outcome, DatabaseBootstrapOutcome.fresh);
        expect(await result.destination.exists(), isTrue);
        final version = await result.database
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 2);
        expect(
          await _applicationId(result.database),
          LegacyDatabaseMigrator.destinationApplicationId,
        );
      },
    );

    test('recognizes an equivalent destination on repeated startup', () async {
      final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));
      final source = File(
        p.join(
          root.path,
          DatabaseBootstrap.linuxLegacyApplicationId,
          DatabaseBootstrap.databaseFileName,
        ),
      );
      await _createClosedDatabase(source, label: 'repeat');
      final bootstrap = _bootstrap(
        supportDirectory,
        DatabaseBootstrapPlatform.linux,
      );

      final first = await bootstrap.open();
      await first.database.close();
      final second = await bootstrap.open();
      addTearDown(second.database.close);

      expect(second.outcome, DatabaseBootstrapOutcome.alreadyMigrated);
      expect(second.migration?.rowCounts['cli_profiles'], 1);
    });

    test('reopens an owned destination after legitimate Nini writes', () async {
      final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));
      final source = File(
        p.join(
          root.path,
          DatabaseBootstrap.linuxLegacyApplicationId,
          DatabaseBootstrap.databaseFileName,
        ),
      );
      await _createClosedDatabase(source, label: 'changed');
      final bootstrap = _bootstrap(
        supportDirectory,
        DatabaseBootstrapPlatform.linux,
      );

      final first = await bootstrap.open();
      await first.database.saveSetting('nini_only', 'preserved');
      await first.database.close();

      final second = await bootstrap.open();
      addTearDown(second.database.close);
      expect(second.outcome, DatabaseBootstrapOutcome.alreadyMigrated);
      expect(second.migration?.rowCounts['app_settings'], 1);
      expect(await second.database.setting('nini_only'), 'preserved');
    });

    test('rejects an existing target owned by another application', () async {
      final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));
      final destination = File(
        p.join(supportDirectory.path, DatabaseBootstrap.databaseFileName),
      );
      final database = await _openSeededDatabase(destination, label: 'foreign');
      await database.customStatement('PRAGMA application_id = 42');
      await database.close();

      await expectLater(
        _bootstrap(supportDirectory, DatabaseBootstrapPlatform.linux).open(),
        throwsA(
          isA<DatabaseBootstrapException>().having(
            (error) => error.kind,
            'kind',
            DatabaseBootstrapFailureKind.destinationConflict,
          ),
        ),
      );
    });

    test('does not open or overwrite a different existing target', () async {
      final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));
      final source = File(
        p.join(
          root.path,
          DatabaseBootstrap.linuxLegacyApplicationId,
          DatabaseBootstrap.databaseFileName,
        ),
      );
      final destination = File(
        p.join(supportDirectory.path, DatabaseBootstrap.databaseFileName),
      );
      await _createClosedDatabase(source, label: 'source');
      await _createClosedDatabase(destination, label: 'destination');
      final destinationBefore = await destination.readAsBytes();

      await expectLater(
        _bootstrap(supportDirectory, DatabaseBootstrapPlatform.linux).open(),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.kind,
            'kind',
            LegacyDatabaseMigrationFailureKind.destinationConflict,
          ),
        ),
      );

      expect(await destination.readAsBytes(), destinationBefore);
    });

    test('reports an open legacy source without creating the target', () async {
      final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));
      final source = File(
        p.join(
          root.path,
          DatabaseBootstrap.linuxLegacyApplicationId,
          DatabaseBootstrap.databaseFileName,
        ),
      );
      final openDatabase = await _openSeededDatabase(source, label: 'open');
      addTearDown(openDatabase.close);

      await expectLater(
        _bootstrap(supportDirectory, DatabaseBootstrapPlatform.linux).open(),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.kind,
            'kind',
            LegacyDatabaseMigrationFailureKind.sourceInUse,
          ),
        ),
      );

      expect(
        await File(
          p.join(supportDirectory.path, DatabaseBootstrap.databaseFileName),
        ).exists(),
        isFalse,
      );
    });

    test('rejects a non-file destination before opening SQLite', () async {
      final supportDirectory = Directory(p.join(root.path, 'com.nini.hub'));
      await Directory(
        p.join(supportDirectory.path, DatabaseBootstrap.databaseFileName),
      ).create(recursive: true);

      await expectLater(
        _bootstrap(supportDirectory, DatabaseBootstrapPlatform.linux).open(),
        throwsA(
          isA<DatabaseBootstrapException>().having(
            (error) => error.kind,
            'kind',
            DatabaseBootstrapFailureKind.destinationConflict,
          ),
        ),
      );
    });

    test('startup translation does not expose the underlying cause', () {
      final failure = AppStartupFailure.from(
        const LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailureKind.sourceInUse,
          'sensitive',
          cause: '/private/path/multicli_ai.sqlite',
        ),
      );

      expect(failure.kind, AppStartupFailureKind.databaseInUse);
      expect(failure.title, 'Cierra MultiCLI AI');
      expect(failure.message, isNot(contains('/private/path')));
      expect(failure.message, isNot(contains('sensitive')));
    });
  });

  final approvedRealSupportDirectory =
      Platform.environment['NINI_HUB_APPROVED_REAL_SUPPORT_DIRECTORY'];
  test(
    'migrates the explicitly approved real Linux database once',
    () async {
      final supportDirectory = Directory(approvedRealSupportDirectory!);
      final bootstrap = _bootstrap(
        supportDirectory,
        DatabaseBootstrapPlatform.linux,
      );

      final first = await bootstrap.open();
      final firstMigration = first.migration;
      await first.database.close();
      expect(firstMigration, isNotNull);
      expect(
        first.outcome,
        anyOf(
          DatabaseBootstrapOutcome.migrated,
          DatabaseBootstrapOutcome.alreadyMigrated,
        ),
      );

      final second = await bootstrap.open();
      final secondMigration = second.migration;
      await second.database.close();
      expect(second.outcome, DatabaseBootstrapOutcome.alreadyMigrated);
      expect(secondMigration?.rowCounts, firstMigration?.rowCounts);

      final counts = firstMigration!.rowCounts.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      debugPrint(
        'NINI_HUB_REAL_DB schema=${firstMigration.schemaVersion} '
        'outcome=${first.outcome.name} '
        'counts=${{for (final entry in counts) entry.key: entry.value}}',
      );
    },
    skip: approvedRealSupportDirectory == null
        ? 'Requires an explicitly approved real support directory.'
        : false,
  );
}

DatabaseBootstrap _bootstrap(
  Directory supportDirectory,
  DatabaseBootstrapPlatform platform,
) => DatabaseBootstrap(
  applicationSupportDirectory: () async => supportDirectory,
  platform: platform,
);

Future<void> _createClosedDatabase(File file, {required String label}) async {
  final database = await _openSeededDatabase(file, label: label);
  await database.close();
}

Future<AppDatabase> _openSeededDatabase(
  File file, {
  required String label,
}) async {
  await file.parent.create(recursive: true);
  final database = AppDatabase(NativeDatabase(file));
  final now = DateTime.utc(2026, 8, 24, 12);
  await database
      .into(database.cliProfiles)
      .insert(
        CliProfilesCompanion.insert(
          id: '$label-profile',
          profileName: label,
          displayName: 'Synthetic $label',
          profileHome: '/synthetic/$label',
          profileSource: 'fixture',
          profileType: 'persistent',
          createdAt: now,
          lastDiscoveredAt: now,
        ),
      );
  return database;
}

Future<int> _applicationId(AppDatabase database) async {
  final row = await database.customSelect('PRAGMA application_id').getSingle();
  return row.read<int>('application_id');
}
