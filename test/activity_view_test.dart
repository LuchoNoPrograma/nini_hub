import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/activity/application/activity_history.dart';
import 'package:nini_hub/features/activity/domain/activity_log.dart';
import 'package:nini_hub/features/activity/domain/activity_repository.dart';
import 'package:nini_hub/features/activity/presentation/activity_view.dart';
import 'package:nini_hub/features/activity/presentation/controllers/activity_controller.dart';
import 'package:nini_hub/features/activity/presentation/state/activity_state.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('activity uses a selectable log and detail layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime(2026, 8, 13, 10, 30);
    const longCommand =
        '/usr/bin/gnome-terminal --title=codex-ari '
        '--working-directory=/home/nini/StudioProjects/nini_hub -- '
        '/home/nini/.local/bin/multi-cli launch codex/ari';
    await database.batch((batch) {
      batch.insertAll(database.commandLogs, [
        CommandLog(
          id: 'refresh-ari',
          profileId: 'ari',
          command: longCommand,
          summary: 'Consultar cuota de Ari',
          output: 'Cuota actualizada correctamente.',
          status: 'success',
          exitCode: 0,
          startedAt: now,
          completedAt: now,
        ),
        CommandLog(
          id: 'refresh-sol',
          profileId: 'sol',
          command: 'codex app-server account/read',
          summary: 'Consultar cuenta de Sol',
          output: 'La sesión expiró.',
          status: 'error',
          exitCode: 1,
          startedAt: now.subtract(const Duration(minutes: 8)),
          completedAt: now.subtract(const Duration(minutes: 7, seconds: 59)),
        ),
        CommandLog(
          id: 'heartbeat-zoe',
          profileId: 'zoe',
          command: 'codex exec --ephemeral',
          summary: 'Esperar heartbeat de Zoe',
          output: '',
          status: 'running',
          startedAt: now.subtract(const Duration(minutes: 10)),
        ),
      ]);
    });
    final container = _activityContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(activityControllerProvider.notifier).load(),
      isTrue,
    );

    await _pumpActivity(tester, container);

    expect(find.text('Log'), findsOneWidget);
    expect(find.text('3 eventos'), findsOneWidget);
    expect(find.text('0 ms'), findsNothing);
    expect(find.text('Cuota actualizada correctamente.'), findsOneWidget);
    final commandText = tester.widget<Text>(find.text(longCommand));
    expect(commandText.maxLines, 2);
    expect(commandText.style?.fontWeight, FontWeight.w400);
    await tester.tap(find.text('Consultar cuenta de Sol'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('La sesión expiró.'), findsOneWidget);
    expect(find.text('Código 1'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('activity-search')),
      'Ari',
    );
    await tester.pump();
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('Consultar cuenta de Sol'), findsNothing);

    await tester.tap(find.byTooltip('Borrar búsqueda'));
    await tester.pump();
    final statusMenu = tester.widget<PopupMenuButton<ActivityStatusFilter>>(
      find.byType(PopupMenuButton<ActivityStatusFilter>),
    );
    statusMenu.onSelected?.call(ActivityStatusFilter.running);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('Esperar heartbeat de Zoe'), findsNWidgets(2));
    expect(find.text('Consultar cuota de Ari'), findsNothing);
    expect(find.text('Consultar cuenta de Sol'), findsNothing);
    expect(find.text('Esperando salida…'), findsOneWidget);
    tester
        .widget<PopupMenuButton<ActivityStatusFilter>>(
          find.byType(PopupMenuButton<ActivityStatusFilter>),
        )
        .onSelected
        ?.call(ActivityStatusFilter.error);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity opens log detail on a narrow surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.commandLogs)
        .insert(
          CommandLog(
            id: 'narrow-log',
            command: 'multi-cli create codex/ari',
            summary: 'Crear perfil Ari',
            output: 'Perfil creado.',
            status: 'success',
            exitCode: 0,
            startedAt: DateTime(2026, 8, 13),
            completedAt: DateTime(2026, 8, 13, 0, 0, 1),
          ),
        );
    final container = _activityContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(activityControllerProvider.notifier).load(),
      isTrue,
    );

    await _pumpActivity(tester, container);
    await tester.tap(find.text('Crear perfil Ari'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Perfil creado.'), findsOneWidget);
    expect(find.text('SALIDA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity shows a running command and its completion live', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = _activityContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(activityControllerProvider.notifier).load(),
      isTrue,
    );
    await _pumpActivity(tester, container);

    final startedAt = DateTime.utc(2026, 8, 25, 12);
    await database
        .into(database.commandLogs)
        .insert(
          CommandLogsCompanion.insert(
            id: 'live-heartbeat',
            profileId: const Value('ari'),
            command: 'nini-agents exec codex/ari -- exec --ephemeral',
            summary: 'Iniciar ventana de Ari',
            status: 'running',
            startedAt: startedAt,
          ),
        );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Iniciar ventana de Ari'), findsWidgets);
    expect(
      find.text('nini-agents exec codex/ari -- exec --ephemeral'),
      findsOneWidget,
    );
    expect(find.text('Esperando salida…'), findsOneWidget);

    await (database.update(
      database.commandLogs,
    )..where((row) => row.id.equals('live-heartbeat'))).write(
      CommandLogsCompanion(
        status: const Value('success'),
        exitCode: const Value(0),
        output: const Value('OK'),
        completedAt: Value(startedAt.add(const Duration(seconds: 5))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Esperando salida…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity clear requires confirmation and removes all logs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final startedAt = DateTime.utc(2026, 8, 22, 12);
    await database.batch((batch) {
      for (var index = 0; index < 251; index++) {
        batch.insert(
          database.commandLogs,
          CommandLogsCompanion.insert(
            id: 'clear-$index',
            command: 'internal-$index',
            summary: 'Evento $index',
            output: const Value('Salida local'),
            status: 'success',
            startedAt: startedAt.add(Duration(minutes: index)),
            completedAt: Value(
              startedAt.add(Duration(minutes: index, seconds: 1)),
            ),
          ),
        );
      }
    });
    final container = _activityContainer(database);
    addTearDown(container.dispose);
    expect(
      await container.read(activityControllerProvider.notifier).load(),
      isTrue,
    );

    await _pumpActivity(tester, container);

    expect(find.text('250 eventos'), findsOneWidget);
    await tester.tap(find.byTooltip('Limpiar historial'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(await database.select(database.commandLogs).get(), hasLength(251));
    expect(find.text('250 eventos'), findsOneWidget);

    await tester.tap(find.byTooltip('Limpiar historial'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Limpiar'));
    await tester.pumpAndSettle();

    expect(await database.select(database.commandLogs).get(), isEmpty);
    expect(find.text('Aún no hay registros'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity exposes a recoverable initial load failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FailOnceActivityRepository([
      ActivityLog(
        id: 'recovered',
        profileId: null,
        command: 'codex app-server account/read',
        summary: 'Historial recuperado',
        output: 'Disponible otra vez.',
        status: ActivityLogStatus.success,
        exitCode: 0,
        startedAt: DateTime.utc(2026, 8, 22),
        completedAt: DateTime.utc(2026, 8, 22, 0, 0, 1),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        activityControllerProvider.overrideWith(
          () => ActivityController(
            observeActivityHistory: ObserveActivityHistory(
              repository: repository,
            ),
            clearActivityHistory: ClearActivityHistory(repository: repository),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(activityControllerProvider.notifier).load(),
      isFalse,
    );
    await _pumpActivity(tester, container);

    expect(find.text('No se pudo cargar el historial'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Historial recuperado'), findsWidgets);
    expect(find.text('No se pudo cargar el historial'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _activityContainer(AppDatabase database) => ProviderContainer(
  overrides: [databaseProvider.overrideWithValue(database)],
);

Future<void> _pumpActivity(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: const Scaffold(body: ActivityView()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

final class _FailOnceActivityRepository implements ActivityRepository {
  _FailOnceActivityRepository(this.values);

  List<ActivityLog> values;
  bool _shouldFail = true;

  @override
  Future<void> clearAll() async => values = [];

  @override
  Future<List<ActivityLog>> loadRecent({required int limit}) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('temporary failure');
    }
    return values.take(limit).toList(growable: false);
  }

  @override
  Stream<List<ActivityLog>> watchRecent({required int limit}) async* {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('temporary failure');
    }
    yield values.take(limit).toList(growable: false);
  }
}
