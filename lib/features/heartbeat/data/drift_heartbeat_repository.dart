import 'package:drift/drift.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/heartbeat/data/heartbeat_state_mapper.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat_ports.dart';

final class DriftHeartbeatRepository
    implements HeartbeatStateRepository, HeartbeatHistoryRepository {
  const DriftHeartbeatRepository(this.database);

  final AppDatabase database;

  @override
  Future<HeartbeatState> load(String profileId) async =>
      HeartbeatStateMapper.fromJsonString(
        await database.setting(_key(profileId)),
      );

  @override
  Future<void> save({
    required String profileId,
    required HeartbeatState state,
  }) => database.saveSetting(
    _key(profileId),
    HeartbeatStateMapper.toJsonString(state),
  );

  @override
  Future<HeartbeatObservation?> loadLatestBefore({
    required String profileId,
    required DateTime before,
    required int expectedWindowMinutes,
  }) async {
    final row = await database
        .customSelect(
          _historySql,
          variables: [
            Variable<String>(profileId),
            Variable<DateTime>(before.toUtc()),
            Variable<int>(expectedWindowMinutes - 60),
            Variable<int>(expectedWindowMinutes + 60),
          ],
          readsFrom: {database.usageChecks, database.quotaWindows},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final data = row.data;
    return HeartbeatObservation(
      limitId: data['limit_id']! as String,
      usedPercent: (data['used_percent'] as num?)?.toDouble(),
      windowDurationMinutes:
          (data['window_duration_minutes'] as num?)?.toInt() ??
          expectedWindowMinutes,
      resetsAt: _sqliteDate(data['resets_at']),
      observedAt: _sqliteDate(data['observed_at'])!,
      accountEmail: data['account_email'] as String?,
      planType: data['plan_type'] as String?,
    );
  }

  static String _key(String profileId) =>
      'codex_weekly_keep_alive_state_$profileId';

  static DateTime? _sqliteDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is! num) return null;
    final raw = value.toInt();
    final milliseconds = raw.abs() < 100000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  static const _historySql = r'''
WITH recent_checks AS (
  SELECT id,
         started_at,
         completed_at,
         account_email,
         plan_type
  FROM usage_checks
  WHERE profile_id = ?
    AND started_at < ?
  ORDER BY started_at DESC
  LIMIT 20
)
SELECT windows.limit_id,
       windows.used_percent,
       windows.window_duration_minutes,
       windows.resets_at,
       COALESCE(checks.completed_at, checks.started_at) AS observed_at,
       checks.account_email,
       checks.plan_type
FROM recent_checks AS checks
INNER JOIN quota_windows AS windows ON windows.check_id = checks.id
WHERE windows.window_duration_minutes >= ?
  AND windows.window_duration_minutes <= ?
ORDER BY checks.started_at DESC,
         CASE WHEN LOWER(windows.limit_id) = 'codex' THEN 0 ELSE 1 END,
         windows.rowid
LIMIT 1
''';
}
