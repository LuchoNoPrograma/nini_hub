import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

enum LegacyDatabaseMigrationOutcome { migrated, alreadyMigrated }

enum LegacyDatabaseMigrationFailureKind {
  sourceMissing,
  samePath,
  sourceInUse,
  invalidSource,
  destinationConflict,
  exportFailed,
  validationFailed,
  activationFailed,
  temporaryCleanupFailed,
}

final class LegacyDatabaseMigrationResult {
  LegacyDatabaseMigrationResult({
    required this.outcome,
    required this.schemaVersion,
    required Map<String, int> rowCounts,
  }) : rowCounts = Map.unmodifiable(rowCounts);

  final LegacyDatabaseMigrationOutcome outcome;
  final int schemaVersion;
  final Map<String, int> rowCounts;
}

final class LegacyDatabaseMigrationException implements Exception {
  const LegacyDatabaseMigrationException(this.kind, this.message, {this.cause});

  final LegacyDatabaseMigrationFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'LegacyDatabaseMigrationException($kind): $message';
}

final class LegacyDatabaseMigrator {
  LegacyDatabaseMigrator({
    FutureOr<void> Function(File temporaryDestination)? beforeActivate,
  }) : this._(beforeActivate);

  LegacyDatabaseMigrator._(this._beforeActivate);

  static const expectedSchemaVersion = 2;
  static const destinationApplicationId = 0x4E485542;

  static const requiredTables = <String>{
    'app_settings',
    'cli_profiles',
    'command_logs',
    'cost_shares',
    'daily_usage_buckets',
    'profile_metadatas',
    'quota_windows',
    'reset_credit_snapshots',
    'usage_checks',
    'workspaces',
  };

  final FutureOr<void> Function(File temporaryDestination)? _beforeActivate;

  Future<LegacyDatabaseMigrationResult> migrate({
    required File source,
    required File destination,
  }) async {
    final sourcePath = _normalizedPath(source);
    final destinationPath = _normalizedPath(destination);
    if (sourcePath == destinationPath) {
      throw const LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.samePath,
        'El origen y el destino deben ser archivos diferentes.',
      );
    }

    final sourceExists = await source.exists();
    final destinationType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (destinationType == FileSystemEntityType.link ||
        destinationType == FileSystemEntityType.directory) {
      throw const LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.destinationConflict,
        'El destino existente no es un archivo SQLite regular.',
      );
    }
    if (destinationType == FileSystemEntityType.file &&
        sourceExists &&
        await FileSystemEntity.identical(source.path, destination.path)) {
      throw const LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.samePath,
        'El origen y el destino apuntan al mismo archivo.',
      );
    }
    if (destinationType == FileSystemEntityType.file) {
      final ownedDestination = await _ownedDestinationSnapshot(destination);
      if (ownedDestination != null) {
        return LegacyDatabaseMigrationResult(
          outcome: LegacyDatabaseMigrationOutcome.alreadyMigrated,
          schemaVersion: ownedDestination.schemaVersion,
          rowCounts: ownedDestination.rowCounts,
        );
      }
    }
    if (!sourceExists) {
      throw const LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.sourceMissing,
        'No existe la base SQLite legacy.',
      );
    }

    final sourceExecutor = _exclusiveExecutor(source);
    try {
      await _openSource(sourceExecutor);
      final sourceSnapshot = await _inspectSource(sourceExecutor);

      if (destinationType == FileSystemEntityType.file) {
        return await _handleExistingDestination(
          sourceExecutor: sourceExecutor,
          sourceSnapshot: sourceSnapshot,
          destination: destination,
        );
      }

      return await _exportAndActivate(
        sourceExecutor: sourceExecutor,
        sourceSnapshot: sourceSnapshot,
        destination: destination,
      );
    } finally {
      await sourceExecutor.close();
    }
  }

  Future<void> _openSource(QueryExecutor executor) async {
    try {
      await executor.ensureOpen(_executorUser);
    } on SqliteException catch (error) {
      if (_isBusy(error)) {
        throw LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailureKind.sourceInUse,
          'La base legacy debe estar cerrada antes de migrarla.',
          cause: error,
        );
      }
      throw LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.invalidSource,
        'No se pudo abrir la base SQLite legacy.',
        cause: error,
      );
    }
  }

  Future<_DatabaseSnapshot> _inspectSource(QueryExecutor executor) async {
    try {
      return await _inspectOpenDatabase(executor, requireWal: true);
    } on LegacyDatabaseMigrationException {
      rethrow;
    } on SqliteException catch (error) {
      final kind = _isBusy(error)
          ? LegacyDatabaseMigrationFailureKind.sourceInUse
          : LegacyDatabaseMigrationFailureKind.invalidSource;
      throw LegacyDatabaseMigrationException(
        kind,
        kind == LegacyDatabaseMigrationFailureKind.sourceInUse
            ? 'La base legacy debe estar cerrada antes de migrarla.'
            : 'La base legacy no cumple el contrato SQLite esperado.',
        cause: error,
      );
    } on Object catch (error) {
      throw LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.invalidSource,
        'La base legacy no cumple el contrato SQLite esperado.',
        cause: error,
      );
    }
  }

  Future<LegacyDatabaseMigrationResult> _handleExistingDestination({
    required QueryExecutor sourceExecutor,
    required _DatabaseSnapshot sourceSnapshot,
    required File destination,
  }) async {
    try {
      final destinationSnapshot = await _inspectFile(destination);
      final sameCounts = _sameCounts(sourceSnapshot, destinationSnapshot);
      final sameContents =
          sameCounts &&
          await _sameContents(
            sourceExecutor: sourceExecutor,
            destination: destination,
          );
      if (!sameContents) {
        throw const LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailureKind.destinationConflict,
          'El destino contiene una base diferente y no sera sobrescrito.',
        );
      }
      await _stampDestination(destination);

      return LegacyDatabaseMigrationResult(
        outcome: LegacyDatabaseMigrationOutcome.alreadyMigrated,
        schemaVersion: sourceSnapshot.schemaVersion,
        rowCounts: sourceSnapshot.rowCounts,
      );
    } on LegacyDatabaseMigrationException {
      rethrow;
    } on Object catch (error) {
      throw LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.destinationConflict,
        'El destino existente no es una migracion valida y no sera sobrescrito.',
        cause: error,
      );
    }
  }

  Future<LegacyDatabaseMigrationResult> _exportAndActivate({
    required QueryExecutor sourceExecutor,
    required _DatabaseSnapshot sourceSnapshot,
    required File destination,
  }) async {
    try {
      await destination.parent.create(recursive: true);
    } on Object catch (error) {
      throw LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.activationFailed,
        'No se pudo preparar el directorio de destino.',
        cause: error,
      );
    }

    late final Directory temporaryDirectory;
    try {
      temporaryDirectory = await destination.parent.createTemp(
        '.${p.basename(destination.path)}.migration.',
      );
    } on Object catch (error) {
      throw LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.activationFailed,
        'No se pudo crear el staging de migracion.',
        cause: error,
      );
    }

    final temporaryDestination = File(
      p.join(temporaryDirectory.path, p.basename(destination.path)),
    );
    LegacyDatabaseMigrationResult? result;
    Object? failure;
    StackTrace? failureStack;

    try {
      try {
        await sourceExecutor.runCustom('VACUUM INTO ?', [
          temporaryDestination.path,
        ]);
      } on Object catch (error) {
        throw LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailureKind.exportFailed,
          'SQLite no pudo generar el snapshot de migracion.',
          cause: error,
        );
      }

      final temporarySnapshot = await _inspectTemporary(temporaryDestination);
      final sameCounts = _sameCounts(sourceSnapshot, temporarySnapshot);
      final sameContents =
          sameCounts &&
          await _sameContents(
            sourceExecutor: sourceExecutor,
            destination: temporaryDestination,
          );
      if (!sameContents) {
        throw const LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailureKind.validationFailed,
          'El snapshot no conserva exactamente el contenido del origen.',
        );
      }
      await _stampDestination(temporaryDestination);

      try {
        await _beforeActivate?.call(temporaryDestination);
        if (await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const LegacyDatabaseMigrationException(
            LegacyDatabaseMigrationFailureKind.destinationConflict,
            'El destino aparecio durante la migracion y no sera sobrescrito.',
          );
        }
        await temporaryDestination.rename(destination.path);
      } on LegacyDatabaseMigrationException {
        rethrow;
      } on Object catch (error) {
        throw LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailureKind.activationFailed,
          'No se pudo activar atomicamente la base migrada.',
          cause: error,
        );
      }

      result = LegacyDatabaseMigrationResult(
        outcome: LegacyDatabaseMigrationOutcome.migrated,
        schemaVersion: temporarySnapshot.schemaVersion,
        rowCounts: temporarySnapshot.rowCounts,
      );
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }

    try {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    } on Object catch (error, stackTrace) {
      if (failure == null) {
        failure = LegacyDatabaseMigrationException(
          LegacyDatabaseMigrationFailureKind.temporaryCleanupFailed,
          'La migracion termino, pero no se pudo limpiar el staging.',
          cause: error,
        );
        failureStack = stackTrace;
      }
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
    return result!;
  }

  Future<_DatabaseSnapshot> _inspectTemporary(File file) async {
    try {
      return await _inspectFile(file);
    } on Object catch (error) {
      throw LegacyDatabaseMigrationException(
        LegacyDatabaseMigrationFailureKind.validationFailed,
        'El snapshot exportado no cumple el contrato SQLite esperado.',
        cause: error,
      );
    }
  }

  Future<_DatabaseSnapshot> _inspectFile(File file) async {
    final executor = _exclusiveExecutor(file);
    try {
      await executor.ensureOpen(_executorUser);
      return await _inspectOpenDatabase(executor, requireWal: false);
    } finally {
      await executor.close();
    }
  }

  Future<_DatabaseSnapshot?> _ownedDestinationSnapshot(File file) async {
    try {
      final snapshot = await _inspectFile(file);
      return snapshot.applicationId == destinationApplicationId
          ? snapshot
          : null;
    } on Object {
      return null;
    }
  }

  Future<void> _stampDestination(File file) async {
    final executor = _exclusiveExecutor(file);
    try {
      await executor.ensureOpen(_executorUser);
      await executor.runCustom(
        'PRAGMA application_id = $destinationApplicationId',
      );
      final rows = await executor.runSelect('PRAGMA application_id', const []);
      if ((rows.single.values.single as num).toInt() !=
          destinationApplicationId) {
        throw const FormatException('Could not stamp destination ownership');
      }
    } finally {
      await executor.close();
    }
  }

  Future<_DatabaseSnapshot> _inspectOpenDatabase(
    QueryExecutor executor, {
    required bool requireWal,
  }) async {
    final quickCheck = await executor.runSelect('PRAGMA quick_check', const []);
    if (quickCheck.length != 1 || quickCheck.single.values.single != 'ok') {
      throw const FormatException('PRAGMA quick_check failed');
    }

    final foreignKeyErrors = await executor.runSelect(
      'PRAGMA foreign_key_check',
      const [],
    );
    if (foreignKeyErrors.isNotEmpty) {
      throw const FormatException('PRAGMA foreign_key_check failed');
    }

    final versionRows = await executor.runSelect(
      'PRAGMA user_version',
      const [],
    );
    final schemaVersion = (versionRows.single.values.single as num).toInt();
    if (schemaVersion != expectedSchemaVersion) {
      throw FormatException('Unexpected schema version $schemaVersion');
    }

    final applicationIdRows = await executor.runSelect(
      'PRAGMA application_id',
      const [],
    );
    final applicationId = (applicationIdRows.single.values.single as num)
        .toInt();

    if (requireWal) {
      final journalRows = await executor.runSelect(
        'PRAGMA journal_mode',
        const [],
      );
      final journalMode = journalRows.single.values.single
          .toString()
          .toLowerCase();
      if (journalMode != 'wal') {
        throw FormatException('Unexpected journal mode $journalMode');
      }
    }

    final tableRows = await executor.runSelect(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      const [],
    );
    final tables = tableRows.map((row) => row['name']! as String).toSet();
    if (!_sameSet(tables, requiredTables)) {
      throw const FormatException('Unexpected SQLite tables');
    }

    final rowCounts = <String, int>{};
    for (final table in requiredTables) {
      final rows = await executor.runSelect(
        'SELECT COUNT(*) AS row_count FROM "$table"',
        const [],
      );
      rowCounts[table] = (rows.single['row_count']! as num).toInt();
    }
    return _DatabaseSnapshot(
      schemaVersion: schemaVersion,
      applicationId: applicationId,
      rowCounts: rowCounts,
    );
  }

  Future<bool> _sameContents({
    required QueryExecutor sourceExecutor,
    required File destination,
  }) async {
    var attached = false;
    try {
      await sourceExecutor.runCustom('ATTACH DATABASE ? AS migration_target', [
        destination.path,
      ]);
      attached = true;
      for (final table in requiredTables) {
        final rows = await sourceExecutor.runSelect(
          'SELECT '
          'EXISTS(SELECT * FROM main."$table" '
          'EXCEPT SELECT * FROM migration_target."$table") AS source_only, '
          'EXISTS(SELECT * FROM migration_target."$table" '
          'EXCEPT SELECT * FROM main."$table") AS target_only',
          const [],
        );
        final row = rows.single;
        if (row['source_only'] != 0 || row['target_only'] != 0) {
          return false;
        }
      }
      return true;
    } finally {
      if (attached) {
        await sourceExecutor.runCustom('DETACH DATABASE migration_target');
      }
    }
  }

  static NativeDatabase _exclusiveExecutor(File file) => NativeDatabase(
    file,
    enableMigrations: false,
    setup: (database) {
      database.execute('PRAGMA busy_timeout = 0');
      database.execute('PRAGMA locking_mode = EXCLUSIVE');
    },
  );

  static String _normalizedPath(File file) {
    final normalized = p.canonicalize(file.absolute.path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static bool _sameSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  static bool _sameCounts(_DatabaseSnapshot left, _DatabaseSnapshot right) =>
      left.schemaVersion == right.schemaVersion &&
      left.applicationId == right.applicationId &&
      left.rowCounts.length == right.rowCounts.length &&
      left.rowCounts.entries.every(
        (entry) => right.rowCounts[entry.key] == entry.value,
      );

  static bool _isBusy(SqliteException error) =>
      error.resultCode == 5 || error.resultCode == 6;
}

final class _DatabaseSnapshot {
  _DatabaseSnapshot({
    required this.schemaVersion,
    required this.applicationId,
    required Map<String, int> rowCounts,
  }) : rowCounts = Map.unmodifiable(rowCounts);

  final int schemaVersion;
  final int applicationId;
  final Map<String, int> rowCounts;
}

final class _NoMigrationExecutorUser extends QueryExecutorUser {
  @override
  int get schemaVersion => LegacyDatabaseMigrator.expectedSchemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

final _executorUser = _NoMigrationExecutorUser();
