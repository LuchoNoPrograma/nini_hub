import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/activity/data/activity_log_mapper.dart';
import 'package:multi_cli_ai/features/activity/domain/activity_log.dart';

void main() {
  test('maps persisted fields, nullability, and instants to UTC', () {
    final startedAt = DateTime(2026, 8, 22, 12, 30);
    final completedAt = DateTime(2026, 8, 22, 12, 31);

    final log = ActivityLogMapper.fromRow(
      CommandLog(
        id: 'log-1',
        profileId: null,
        command: 'codex exec',
        summary: 'Finished command',
        output: 'done',
        status: 'success',
        exitCode: null,
        startedAt: startedAt,
        completedAt: completedAt,
      ),
    );

    expect(log.id, 'log-1');
    expect(log.profileId, isNull);
    expect(log.command, 'codex exec');
    expect(log.summary, 'Finished command');
    expect(log.output, 'done');
    expect(log.status, ActivityLogStatus.success);
    expect(log.exitCode, isNull);
    expect(
      log.startedAt.millisecondsSinceEpoch,
      startedAt.millisecondsSinceEpoch,
    );
    expect(log.startedAt.isUtc, isTrue);
    expect(
      log.completedAt?.millisecondsSinceEpoch,
      completedAt.millisecondsSinceEpoch,
    );
    expect(log.completedAt?.isUtc, isTrue);
  });

  test('maps known persisted statuses and falls back to unknown', () {
    const expected = {
      'success': ActivityLogStatus.success,
      'running': ActivityLogStatus.running,
      'error': ActivityLogStatus.error,
      'timeout': ActivityLogStatus.timeout,
      'future-status': ActivityLogStatus.unknown,
    };

    for (final entry in expected.entries) {
      final log = ActivityLogMapper.fromRow(_row(status: entry.key));

      expect(log.status, entry.value, reason: entry.key);
      expect(log.profileId, isNull);
      expect(log.exitCode, isNull);
      expect(log.completedAt, isNull);
    }
  });
}

CommandLog _row({required String status}) => CommandLog(
  id: status,
  profileId: null,
  command: 'codex exec',
  summary: status,
  output: '',
  status: status,
  exitCode: null,
  startedAt: DateTime.utc(2026, 8, 22),
  completedAt: null,
);
