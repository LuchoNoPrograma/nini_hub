import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/activity/data/drift_activity_repository.dart';
import 'package:nini_hub/features/activity/domain/activity_log.dart';

void main() {
  late _SelectCounter counter;
  late AppDatabase database;
  late DriftActivityRepository repository;

  setUp(() {
    counter = _SelectCounter();
    database = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    repository = DriftActivityRepository(database);
  });

  tearDown(() => database.close());

  test('loads the requested limit in legacy order with one select', () async {
    final startedAt = DateTime.utc(2026, 8, 22, 10);
    await database.batch((batch) {
      for (var index = 0; index < 4; index++) {
        batch.insert(
          database.commandLogs,
          _log(index, startedAt.add(Duration(minutes: index))),
        );
      }
    });
    counter.selects = 0;

    final logs = await repository.loadRecent(limit: 2);

    expect(counter.selects, 1);
    expect(logs.map((log) => log.id), ['log-3', 'log-2']);
    expect(logs.map((log) => log.status), [
      ActivityLogStatus.timeout,
      ActivityLogStatus.error,
    ]);
    expect(logs.every((log) => log.startedAt.isUtc), isTrue);
    expect(logs.every((log) => log.completedAt?.isUtc == true), isTrue);
  });

  test('clearAll deletes rows beyond the visible history limit', () async {
    final startedAt = DateTime.utc(2026, 8, 22, 10);
    await database.batch((batch) {
      for (var index = 0; index < 251; index++) {
        batch.insert(
          database.commandLogs,
          _log(index, startedAt.add(Duration(minutes: index))),
        );
      }
    });

    await repository.clearAll();

    expect(await database.select(database.commandLogs).get(), isEmpty);
  });

  test('watchRecent publishes a running command and its completion', () async {
    final startedAt = DateTime.utc(2026, 8, 25, 12);
    final iterator = StreamIterator(repository.watchRecent(limit: 2));
    addTearDown(iterator.cancel);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isEmpty);

    await database.into(database.commandLogs).insert(_log(1, startedAt));
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.single.status, ActivityLogStatus.running);
    expect(iterator.current.single.command, 'command-1');

    await (database.update(
      database.commandLogs,
    )..where((row) => row.id.equals('log-1'))).write(
      CommandLogsCompanion(
        status: const Value('success'),
        exitCode: const Value(0),
        output: const Value('done'),
        completedAt: Value(startedAt.add(const Duration(seconds: 3))),
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.single.status, ActivityLogStatus.success);
    expect(iterator.current.single.output, 'done');
  });
}

CommandLogsCompanion _log(int index, DateTime startedAt) =>
    CommandLogsCompanion.insert(
      id: 'log-$index',
      profileId: Value(index.isEven ? 'profile-$index' : null),
      command: 'command-$index',
      summary: 'Operation $index',
      output: Value('output-$index'),
      status: switch (index % 4) {
        0 => 'success',
        1 => 'running',
        2 => 'error',
        _ => 'timeout',
      },
      exitCode: Value(index.isEven ? 0 : null),
      startedAt: startedAt,
      completedAt: Value(startedAt.add(const Duration(seconds: 3))),
    );

final class _SelectCounter extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return super.runSelect(executor, statement, args);
  }
}
