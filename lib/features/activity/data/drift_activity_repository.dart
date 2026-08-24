import 'package:drift/drift.dart';
import 'package:multi_cli_ai/core/database/app_database.dart' as db;
import 'package:multi_cli_ai/features/activity/data/activity_log_mapper.dart';
import 'package:multi_cli_ai/features/activity/domain/activity_log.dart';
import 'package:multi_cli_ai/features/activity/domain/activity_repository.dart';

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
  Future<void> clearAll() => _database.delete(_database.commandLogs).go();
}
