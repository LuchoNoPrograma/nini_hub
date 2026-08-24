import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/features/activity/application/activity_history.dart';
import 'package:multi_cli_ai/features/activity/domain/activity_log.dart';
import 'package:multi_cli_ai/features/activity/domain/activity_repository.dart';
import 'package:multi_cli_ai/features/activity/presentation/controllers/activity_controller.dart';
import 'package:multi_cli_ai/features/activity/presentation/state/activity_state.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  test(
    'loads an immutable snapshot, preserves local choices, and rejects overlap',
    () async {
      final gate = Completer<List<ActivityLog>>();
      fixture.repository.loadGate = gate;

      final load = fixture.controller.load();
      final overlappingLoad = fixture.controller.load();
      final overlappingClear = fixture.controller.clear();
      fixture.controller.setSearch('ERROR');
      fixture.controller.setStatusFilter(ActivityStatusFilter.error);
      fixture.controller.selectLog('error');

      expect(fixture.state.isLoading, isTrue);
      expect(await overlappingLoad, isFalse);
      expect(await overlappingClear, isFalse);
      gate.complete([
        _log('success'),
        _log('error', status: ActivityLogStatus.error),
      ]);
      expect(await load, isTrue);

      expect(fixture.state.isInitialized, isTrue);
      expect(fixture.state.search, 'ERROR');
      expect(fixture.state.statusFilter, ActivityStatusFilter.error);
      expect(fixture.state.selectedLogId, 'error');
      expect(fixture.state.visibleLogs.map((log) => log.id), ['error']);
      expect(fixture.state.selectedLog?.id, 'error');
      expect(() => fixture.state.logs.clear(), throwsUnsupportedError);
      expect(fixture.state.operation, isNull);
    },
  );

  test('filters text and statuses with legacy selection fallback', () async {
    fixture.repository.values = [
      _log('success', summary: 'Alpha result'),
      _log('running', status: ActivityLogStatus.running, command: 'codex beta'),
      _log('error', status: ActivityLogStatus.error, output: 'Gamma failure'),
      _log('timeout', status: ActivityLogStatus.timeout),
    ];
    expect(await fixture.controller.load(), isTrue);

    fixture.controller.setSearch('  ALPHA  ');
    expect(_visibleIds(fixture.state), ['success']);
    fixture.controller.setSearch('codex BETA');
    expect(_visibleIds(fixture.state), ['running']);
    fixture.controller.setSearch('gamma FAILURE');
    expect(_visibleIds(fixture.state), ['error']);

    fixture.controller.setSearch('');
    fixture.controller.selectLog('success');
    fixture.controller.setStatusFilter(ActivityStatusFilter.error);
    expect(_visibleIds(fixture.state), ['error']);
    expect(fixture.state.selectedLogId, 'success');
    expect(fixture.state.selectedLog?.id, 'error');

    fixture.controller.setStatusFilter(ActivityStatusFilter.all);
    expect(fixture.state.selectedLog?.id, 'success');
    fixture.controller.setStatusFilter(ActivityStatusFilter.error);
    expect(_visibleIds(fixture.state), ['error']);
    expect(_visibleIds(fixture.state), isNot(contains('timeout')));
  });

  test('load failure retains the previous snapshot and cause', () async {
    final existing = _log('existing');
    fixture.repository.values = [existing];
    expect(await fixture.controller.load(), isTrue);
    final cause = StateError('load failed');
    fixture.repository.nextLoadFailure = cause;

    expect(await fixture.controller.load(), isFalse);

    expect(fixture.state.logs, [same(existing)]);
    expect(fixture.state.isInitialized, isTrue);
    expect(fixture.state.failure, same(cause));
    expect(fixture.state.errorMessage, 'No se pudo cargar el historial.');
    expect(fixture.state.operation, isNull);
    fixture.controller.clearFailure();
    expect(fixture.state.failure, isNull);
    expect(fixture.state.errorMessage, isNull);
  });

  test(
    'clear is single-flight and retains changes made while awaiting',
    () async {
      fixture.repository.values = [_log('existing')];
      expect(await fixture.controller.load(), isTrue);
      fixture.controller.selectLog('existing');
      fixture.controller.setStatusFilter(ActivityStatusFilter.running);
      final gate = Completer<void>();
      fixture.repository.clearGate = gate;

      final clear = fixture.controller.clear();
      final overlappingLoad = fixture.controller.load();
      final overlappingClear = fixture.controller.clear();
      fixture.controller.setSearch('changed while clearing');

      expect(fixture.state.isClearing, isTrue);
      expect(await overlappingLoad, isFalse);
      expect(await overlappingClear, isFalse);
      gate.complete();
      expect(await clear, isTrue);

      expect(fixture.repository.clearCalls, 1);
      expect(fixture.repository.loadCalls, 2);
      expect(fixture.state.logs, isEmpty);
      expect(fixture.state.search, 'changed while clearing');
      expect(fixture.state.statusFilter, ActivityStatusFilter.running);
      expect(fixture.state.selectedLogId, 'existing');
      expect(fixture.state.selectedLog, isNull);
      expect(fixture.state.operation, isNull);
    },
  );

  test('clear failure keeps the snapshot and does not reload', () async {
    final existing = _log('existing');
    fixture.repository.values = [existing];
    expect(await fixture.controller.load(), isTrue);
    final cause = StateError('clear failed');
    fixture.repository.nextClearFailure = cause;

    expect(await fixture.controller.clear(), isFalse);

    expect(fixture.repository.clearCalls, 1);
    expect(fixture.repository.loadCalls, 1);
    expect(fixture.state.logs, [same(existing)]);
    expect(fixture.state.failure, same(cause));
    expect(fixture.state.errorMessage, 'No se pudo limpiar el historial.');
  });

  test('post-clear reload failure reports the applied clear', () async {
    final existing = _log('existing');
    fixture.repository.values = [existing];
    expect(await fixture.controller.load(), isTrue);
    final cause = StateError('reload failed');
    fixture.repository.nextLoadFailure = cause;

    expect(await fixture.controller.clear(), isFalse);

    expect(fixture.repository.values, isEmpty);
    expect(fixture.state.logs, [same(existing)]);
    expect(
      fixture.state.failure,
      isA<ActivityClearAppliedFailure>().having(
        (failure) => failure.cause,
        'cause',
        same(cause),
      ),
    );
    expect(
      fixture.state.errorMessage,
      'El historial se limpió, pero no se pudo actualizar la lista.',
    );
    expect(fixture.state.operation, isNull);
  });

  test('ignores a late load result after provider disposal', () async {
    final gate = Completer<List<ActivityLog>>();
    fixture.repository.loadGate = gate;

    final load = fixture.controller.load();
    fixture.dispose();
    gate.complete([_log('late')]);

    expect(await load, isFalse);
  });
}

final class _Fixture {
  _Fixture() : repository = _MemoryActivityRepository() {
    provider = NotifierProvider<ActivityController, ActivityState>(
      () => ActivityController(
        loadActivityHistory: LoadActivityHistory(repository: repository),
        clearActivityHistory: ClearActivityHistory(repository: repository),
      ),
    );
    container = ProviderContainer();
    controller = container.read(provider.notifier);
  }

  final _MemoryActivityRepository repository;
  late final NotifierProvider<ActivityController, ActivityState> provider;
  late final ProviderContainer container;
  late final ActivityController controller;
  bool _isDisposed = false;

  ActivityState get state => container.read(provider);

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    container.dispose();
  }
}

final class _MemoryActivityRepository implements ActivityRepository {
  List<ActivityLog> values = [];
  Completer<List<ActivityLog>>? loadGate;
  Completer<void>? clearGate;
  Object? nextLoadFailure;
  Object? nextClearFailure;
  int loadCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> clearAll() async {
    clearCalls++;
    final gate = clearGate;
    clearGate = null;
    if (gate != null) await gate.future;
    final failure = nextClearFailure;
    nextClearFailure = null;
    if (failure != null) throw failure;
    values = [];
  }

  @override
  Future<List<ActivityLog>> loadRecent({required int limit}) async {
    loadCalls++;
    final gate = loadGate;
    loadGate = null;
    if (gate != null) return gate.future;
    final failure = nextLoadFailure;
    nextLoadFailure = null;
    if (failure != null) throw failure;
    return List.unmodifiable(values.take(limit));
  }
}

ActivityLog _log(
  String id, {
  ActivityLogStatus status = ActivityLogStatus.success,
  String? summary,
  String? command,
  String output = '',
}) => ActivityLog(
  id: id,
  profileId: 'profile-$id',
  command: command ?? 'command-$id',
  summary: summary ?? id,
  output: output,
  status: status,
  exitCode: status == ActivityLogStatus.success ? 0 : 1,
  startedAt: DateTime.utc(2026, 8, 22, 12),
  completedAt: DateTime.utc(2026, 8, 22, 12, 1),
);

List<String> _visibleIds(ActivityState state) =>
    state.visibleLogs.map((log) => log.id).toList();
