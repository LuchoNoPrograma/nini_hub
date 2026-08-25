import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/activity/data/drift_activity_repository.dart';
import 'package:nini_hub/features/activity/domain/activity_log.dart';

void main() {
  test('activity loads the latest 250 logs in descending order', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final startedAt = DateTime.utc(2026, 8, 22, 10);

    await database.batch((batch) {
      for (var index = 0; index < 260; index++) {
        final started = startedAt.add(Duration(minutes: index));
        batch.insert(
          database.commandLogs,
          CommandLogsCompanion.insert(
            id: 'log-$index',
            profileId: Value(index.isEven ? 'profile-$index' : null),
            command: 'command-$index --flag',
            summary: 'Operation $index',
            output: Value('output-$index'),
            status: switch (index % 4) {
              0 => 'success',
              1 => 'running',
              2 => 'error',
              _ => 'timeout',
            },
            exitCode: Value(index.isEven ? 0 : null),
            startedAt: started,
            completedAt: Value(started.add(const Duration(seconds: 3))),
          ),
        );
      }
    });

    final logs = await DriftActivityRepository(database).loadRecent(limit: 250);

    expect(logs, hasLength(250));
    expect(logs.first.id, 'log-259');
    expect(logs.last.id, 'log-10');
    expect(logs.first.profileId, isNull);
    expect(logs.first.command, 'command-259 --flag');
    expect(logs.first.summary, 'Operation 259');
    expect(logs.first.output, 'output-259');
    expect(logs.first.status, ActivityLogStatus.timeout);
    expect(logs.first.exitCode, isNull);
    expect(
      logs.first.completedAt?.millisecondsSinceEpoch,
      startedAt
          .add(const Duration(minutes: 259, seconds: 3))
          .millisecondsSinceEpoch,
    );
    expect(logs.map((log) => log.status).toSet(), {
      ActivityLogStatus.success,
      ActivityLogStatus.running,
      ActivityLogStatus.error,
      ActivityLogStatus.timeout,
    });
  });

  test('internal activity logs persist sanitized and bounded output', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final runner = ProcessRunner(database);
    final longOutput = List.filled(12050, 'x').join();

    await runner.addInternalLog(
      summary: 'Inspect profile',
      status: 'error',
      output: 'access_token=secret-value $longOutput',
      profileId: 'profile-id',
      command: 'codex app-server account/read',
    );

    final log = await database.select(database.commandLogs).getSingle();
    expect(log.id, isNotEmpty);
    expect(log.profileId, 'profile-id');
    expect(log.command, 'codex app-server account/read');
    expect(log.summary, 'Inspect profile');
    expect(log.status, 'error');
    expect(log.exitCode, isNull);
    expect(log.output, isNot(contains('secret-value')));
    expect(log.output, contains('[REDACTADO]'));
    expect(log.output, endsWith('[truncado]'));
    expect(log.completedAt, isNotNull);
    expect(
      log.completedAt!.millisecondsSinceEpoch,
      greaterThanOrEqualTo(log.startedAt.millisecondsSinceEpoch),
    );
  });
}
