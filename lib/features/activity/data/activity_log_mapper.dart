import 'package:nini_hub/core/database/app_database.dart' as db;
import 'package:nini_hub/features/activity/domain/activity_log.dart';

abstract final class ActivityLogMapper {
  static ActivityLog fromRow(db.CommandLog row) => ActivityLog(
    id: row.id,
    profileId: row.profileId,
    command: row.command,
    summary: row.summary,
    output: row.output,
    status: _status(row.status),
    exitCode: row.exitCode,
    startedAt: row.startedAt.toUtc(),
    completedAt: row.completedAt?.toUtc(),
  );

  static ActivityLogStatus _status(String value) => switch (value) {
    'success' => ActivityLogStatus.success,
    'running' => ActivityLogStatus.running,
    'error' => ActivityLogStatus.error,
    'timeout' => ActivityLogStatus.timeout,
    _ => ActivityLogStatus.unknown,
  };
}
