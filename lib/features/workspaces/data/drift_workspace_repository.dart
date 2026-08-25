import 'dart:io';

import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart' as db;
import 'package:nini_hub/features/workspaces/domain/workspace.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_failure.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

final class DriftWorkspaceRepository implements WorkspaceRepository {
  DriftWorkspaceRepository(this._database);

  final db.AppDatabase _database;
  final Uuid _uuid = const Uuid();

  @override
  Future<List<Workspace>> loadAll() async =>
      (await (_database.select(
            _database.workspaces,
          )..orderBy([(row) => OrderingTerm.desc(row.lastUsedAt)])).get())
          .map(_toDomain)
          .toList(growable: false);

  @override
  Future<Workspace?> findById(String workspaceId) async {
    final row = await (_database.select(
      _database.workspaces,
    )..where((item) => item.id.equals(workspaceId))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<Workspace> add(String path) async {
    try {
      return await _remember(path, opened: false);
    } on StateError {
      throw const InvalidWorkspacePathFailure();
    }
  }

  @override
  Future<Workspace> recordOpened(String path) async {
    try {
      return await _remember(path, opened: true);
    } on StateError {
      throw const InvalidWorkspacePathFailure();
    }
  }

  @override
  Future<void> select(String workspaceId) async {
    final lastUsedAt = await _nextLastUsedAt();
    await (_database.update(_database.workspaces)
          ..where((row) => row.id.equals(workspaceId)))
        .write(db.WorkspacesCompanion(lastUsedAt: Value(lastUsedAt)));
  }

  @override
  Future<void> rename({
    required String workspaceId,
    required String name,
  }) async {
    try {
      final value = name.trim();
      if (value.isEmpty) {
        throw const FormatException(
          'El nombre del workspace no puede quedar vacío.',
        );
      }
      await (_database.update(_database.workspaces)
            ..where((row) => row.id.equals(workspaceId)))
          .write(db.WorkspacesCompanion(name: Value(value)));
    } on FormatException {
      throw const InvalidWorkspaceNameFailure();
    }
  }

  @override
  Future<void> remove(String workspaceId) => (_database.delete(
    _database.workspaces,
  )..where((row) => row.id.equals(workspaceId))).go();

  Future<Workspace> _remember(String value, {required bool opened}) async {
    final path = _validatePath(value);
    final key = _pathKey(path);
    final existing = await (_database.select(
      _database.workspaces,
    )..where((row) => row.pathKey.equals(key))).getSingleOrNull();
    final now = await _nextLastUsedAt();
    if (existing == null) {
      final id = _uuid.v4();
      await _database
          .into(_database.workspaces)
          .insert(
            db.WorkspacesCompanion.insert(
              id: id,
              path: path,
              pathKey: key,
              name: _defaultName(path),
              openCount: Value(opened ? 1 : 0),
              createdAt: now,
              lastUsedAt: now,
            ),
          );
      return _toDomain(
        await (_database.select(
          _database.workspaces,
        )..where((row) => row.id.equals(id))).getSingle(),
      );
    }

    await (_database.update(
      _database.workspaces,
    )..where((row) => row.id.equals(existing.id))).write(
      db.WorkspacesCompanion(
        path: Value(path),
        lastUsedAt: Value(now),
        openCount: Value(existing.openCount + (opened ? 1 : 0)),
      ),
    );
    return _toDomain(
      await (_database.select(
        _database.workspaces,
      )..where((row) => row.id.equals(existing.id))).getSingle(),
    );
  }

  Workspace _toDomain(db.Workspace row) => Workspace(
    id: row.id,
    path: row.path,
    name: row.name,
    openCount: row.openCount,
    createdAt: row.createdAt.toUtc(),
    lastUsedAt: row.lastUsedAt.toUtc(),
  );

  static String _validatePath(String value) {
    final directory = Directory(value.trim()).absolute;
    if (!directory.existsSync()) {
      throw StateError('El workspace seleccionado ya no existe.');
    }
    return p.normalize(directory.path);
  }

  static String _pathKey(String path) {
    final normalized = p.normalize(Directory(path).absolute.path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String _defaultName(String path) {
    final name = p.basename(path);
    return name.isEmpty ? path : name;
  }

  Future<DateTime> _nextLastUsedAt() async {
    final latest =
        await (_database.select(_database.workspaces)
              ..orderBy([(row) => OrderingTerm.desc(row.lastUsedAt)])
              ..limit(1))
            .getSingleOrNull();
    final rawNow = DateTime.now().toUtc();
    final now = DateTime.fromMillisecondsSinceEpoch(
      (rawNow.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
    if (latest == null || now.isAfter(latest.lastUsedAt)) return now;
    return latest.lastUsedAt.add(const Duration(seconds: 1));
  }
}
