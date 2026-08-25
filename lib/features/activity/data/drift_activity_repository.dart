import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart' as db;
import 'package:nini_hub/features/activity/data/activity_log_mapper.dart';
import 'package:nini_hub/features/activity/domain/activity_log.dart';
import 'package:nini_hub/features/activity/domain/activity_repository.dart';

final class DriftActivityRepository implements ActivityRepository {
  const DriftActivityRepository(this._database);

  final db.AppDatabase _database;

  @override
  Future<List<ActivityLog>> loadRecent({required int limit}) async =>
      (await (_database.select(_database.commandLogs)
                ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
                ..limit(limit))
              .get())
          .map(ActivityLogMapper.fromRow)
          .toList(growable: false);

  @override
  Stream<List<ActivityLog>> watchRecent({required int limit}) =>
      (_database.select(_database.commandLogs)
            ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
            ..limit(limit))
          .watch()
          .map(
            (rows) =>
                rows.map(ActivityLogMapper.fromRow).toList(growable: false),
          );

  @override
  Future<void> clearAll() => _database.delete(_database.commandLogs).go();
}
