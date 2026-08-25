import 'dart:io';

import 'package:drift/native.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/database/legacy_database_migrator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ApplicationSupportDirectoryResolver = Future<Directory> Function();

enum DatabaseBootstrapPlatform { linux, windows }

enum DatabaseBootstrapOutcome { fresh, existing, migrated, alreadyMigrated }

enum DatabaseBootstrapFailureKind {
  unsupportedPlatform,
  supportDirectoryUnavailable,
  destinationConflict,
  databaseOpenFailed,
}

final class DatabaseBootstrapException implements Exception {
  const DatabaseBootstrapException(this.kind, this.message, {this.cause});

  final DatabaseBootstrapFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'DatabaseBootstrapException($kind): $message';
}

final class DatabaseBootstrapResult {
  const DatabaseBootstrapResult({
    required this.database,
    required this.outcome,
    required this.destination,
    required this.legacySource,
    this.migration,
  });

  final AppDatabase database;
  final DatabaseBootstrapOutcome outcome;
  final File destination;
  final File legacySource;
  final LegacyDatabaseMigrationResult? migration;
}

final class DatabaseBootstrap {
  DatabaseBootstrap({
    this.applicationSupportDirectory = getApplicationSupportDirectory,
    this.platform,
    LegacyDatabaseMigrator? migrator,
  }) : _migrator = migrator ?? LegacyDatabaseMigrator();

  static const databaseFileName = 'multicli_ai.sqlite';
  static const linuxLegacyApplicationId = 'com.nini.multi_cli_ai';
  static const windowsLegacyProductName = 'MultiCLI AI';

  final ApplicationSupportDirectoryResolver applicationSupportDirectory;
  final DatabaseBootstrapPlatform? platform;
  final LegacyDatabaseMigrator _migrator;

  Future<DatabaseBootstrapResult> open() async {
    final platform = this.platform ?? _currentPlatform();
    final supportDirectory = await _resolveSupportDirectory();
    final destination = File(p.join(supportDirectory.path, databaseFileName));
    final legacySource = File(
      p.join(
        _legacySupportDirectory(supportDirectory, platform).path,
        databaseFileName,
      ),
    );

    final destinationType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (destinationType != FileSystemEntityType.notFound &&
        destinationType != FileSystemEntityType.file) {
      throw const DatabaseBootstrapException(
        DatabaseBootstrapFailureKind.destinationConflict,
        'El destino SQLite de Nini Hub no es un archivo regular.',
      );
    }

    final sourceType = await FileSystemEntity.type(
      legacySource.path,
      followLinks: false,
    );
    LegacyDatabaseMigrationResult? migration;
    late final DatabaseBootstrapOutcome outcome;
    if (sourceType == FileSystemEntityType.file) {
      migration = await _migrator.migrate(
        source: legacySource,
        destination: destination,
      );
      outcome = switch (migration.outcome) {
        LegacyDatabaseMigrationOutcome.migrated =>
          DatabaseBootstrapOutcome.migrated,
        LegacyDatabaseMigrationOutcome.alreadyMigrated =>
          DatabaseBootstrapOutcome.alreadyMigrated,
      };
    } else if (sourceType == FileSystemEntityType.notFound) {
      outcome = destinationType == FileSystemEntityType.file
          ? DatabaseBootstrapOutcome.existing
          : DatabaseBootstrapOutcome.fresh;
    } else {
      throw const LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.invalidSource,
        'La ruta SQLite legacy no es un archivo regular.',
      );
    }

    return _openDestination(
      destination: destination,
      legacySource: legacySource,
      outcome: outcome,
      migration: migration,
    );
  }

  Future<Directory> _resolveSupportDirectory() async {
    try {
      final directory = await applicationSupportDirectory();
      await directory.create(recursive: true);
      return directory;
    } on Object catch (error) {
      throw DatabaseBootstrapException(
        DatabaseBootstrapFailureKind.supportDirectoryUnavailable,
        'No se pudo preparar el directorio de datos de Nini Hub.',
        cause: error,
      );
    }
  }

  Future<DatabaseBootstrapResult> _openDestination({
    required File destination,
    required File legacySource,
    required DatabaseBootstrapOutcome outcome,
    required LegacyDatabaseMigrationResult? migration,
  }) async {
    AppDatabase? database;
    try {
      database = AppDatabase(NativeDatabase(destination));
      await database.customSelect('SELECT 1').get();
      await _ensureDestinationOwnership(database);
      return DatabaseBootstrapResult(
        database: database,
        outcome: outcome,
        destination: destination,
        legacySource: legacySource,
        migration: migration,
      );
    } on DatabaseBootstrapException {
      if (database != null) {
        await _closeAfterStartupFailure(database);
      }
      rethrow;
    } on Object catch (error) {
      if (database != null) {
        await _closeAfterStartupFailure(database);
      }
      throw DatabaseBootstrapException(
        DatabaseBootstrapFailureKind.databaseOpenFailed,
        'No se pudo abrir la base SQLite de Nini Hub.',
        cause: error,
      );
    }
  }

  Future<void> _ensureDestinationOwnership(AppDatabase database) async {
    final row = await database
        .customSelect('PRAGMA application_id')
        .getSingle();
    final applicationId = row.read<int>('application_id');
    if (applicationId != 0 &&
        applicationId != LegacyDatabaseMigrator.destinationApplicationId) {
      throw const DatabaseBootstrapException(
        DatabaseBootstrapFailureKind.destinationConflict,
        'El destino SQLite pertenece a otra aplicacion.',
      );
    }
    if (applicationId == 0) {
      await database.customStatement(
        'PRAGMA application_id = '
        '${LegacyDatabaseMigrator.destinationApplicationId}',
      );
      final stampedRow = await database
          .customSelect('PRAGMA application_id')
          .getSingle();
      if (stampedRow.read<int>('application_id') !=
          LegacyDatabaseMigrator.destinationApplicationId) {
        throw const DatabaseBootstrapException(
          DatabaseBootstrapFailureKind.databaseOpenFailed,
          'No se pudo registrar la propiedad SQLite de Nini Hub.',
        );
      }
    }
  }

  Future<void> _closeAfterStartupFailure(AppDatabase database) async {
    try {
      await database.close();
    } on Object {
      // The original startup failure is the actionable cause.
    }
  }

  static Directory _legacySupportDirectory(
    Directory supportDirectory,
    DatabaseBootstrapPlatform platform,
  ) => switch (platform) {
    DatabaseBootstrapPlatform.linux => Directory(
      p.join(supportDirectory.parent.path, linuxLegacyApplicationId),
    ),
    DatabaseBootstrapPlatform.windows => Directory(
      p.join(supportDirectory.parent.path, windowsLegacyProductName),
    ),
  };

  static DatabaseBootstrapPlatform _currentPlatform() {
    if (Platform.isLinux) return DatabaseBootstrapPlatform.linux;
    if (Platform.isWindows) return DatabaseBootstrapPlatform.windows;
    throw const DatabaseBootstrapException(
      DatabaseBootstrapFailureKind.unsupportedPlatform,
      'Nini Hub solo admite la base local en Linux y Windows.',
    );
  }
}
