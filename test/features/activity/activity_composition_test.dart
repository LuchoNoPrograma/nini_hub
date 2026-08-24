import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/profiles/data/profile_discovery_service.dart';

void main() {
  test(
    'dashboard bootstraps one activity projection and clear stays focalized',
    () async {
      final counter = _SelectCounter();
      final database = AppDatabase(
        NativeDatabase.memory().interceptWith(counter),
      );
      final startedAt = DateTime.utc(2026, 8, 22, 12);
      await database.batch((batch) {
        for (var index = 0; index < 251; index++) {
          batch.insert(
            database.commandLogs,
            CommandLogsCompanion.insert(
              id: 'activity-$index',
              command: 'internal-$index',
              summary: 'Evento $index',
              output: const Value('Salida local'),
              status: 'success',
              startedAt: startedAt.add(Duration(minutes: index)),
            ),
          );
        }
      });
      counter.statements.clear();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          profileDiscoveryProvider.overrideWithValue(
            _StaticProfileDiscovery(database),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      container.read(activityControllerProvider.notifier);
      expect(container.read(activityControllerProvider).isInitialized, isFalse);
      expect(_activitySelects(counter), isEmpty);

      expect(await container.read(settingsBootstrapProvider.future), isTrue);
      await container.read(appStartupProvider.future);

      final activity = container.read(activityControllerProvider);
      expect(activity.isInitialized, isTrue);
      expect(activity.logs, hasLength(250));
      expect(activity.logs.first.id, 'activity-250');
      expect(activity.logs.last.id, 'activity-1');
      expect(_activitySelects(counter), hasLength(1));

      final calendarBeforeClear = container
          .read(usageControllerProvider)
          .calendar;
      counter.statements.clear();
      expect(
        await container.read(activityControllerProvider.notifier).clear(),
        isTrue,
      );

      expect(container.read(activityControllerProvider).logs, isEmpty);
      expect(
        container.read(usageControllerProvider).calendar,
        same(calendarBeforeClear),
      );
      expect(_activitySelects(counter), hasLength(1));
      expect(await database.select(database.commandLogs).get(), isEmpty);
    },
  );

  test('activity load failure keeps dashboard startup blocked', () async {
    final counter = _SelectCounter()
      ..activityFailure = StateError('activity unavailable');
    final database = AppDatabase(
      NativeDatabase.memory().interceptWith(counter),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        profileDiscoveryProvider.overrideWithValue(
          _StaticProfileDiscovery(database),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    expect(await container.read(settingsBootstrapProvider.future), isTrue);
    await expectLater(
      container.read(appStartupProvider.future),
      throwsA(same(counter.activityFailure)),
    );

    expect(
      container.read(activityControllerProvider).failure,
      same(counter.activityFailure),
    );
    expect(
      container.read(activityControllerProvider).errorMessage,
      'No se pudo cargar el historial.',
    );
  });
}

Iterable<String> _activitySelects(_SelectCounter counter) => counter.statements
    .where((statement) => statement.toLowerCase().contains('command_logs'));

final class _SelectCounter extends QueryInterceptor {
  final List<String> statements = [];
  Object? activityFailure;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    final failure = activityFailure;
    if (failure != null && statement.toLowerCase().contains('command_logs')) {
      throw failure;
    }
    return super.runSelect(executor, statement, args);
  }
}

final class _StaticProfileDiscovery extends ProfileDiscoveryService {
  _StaticProfileDiscovery(super.database);

  @override
  Future<List<CliProfile>> discoverProfiles() =>
      database.select(database.cliProfiles).get();
}
