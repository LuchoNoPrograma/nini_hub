import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/activity/application/activity_history.dart';
import 'package:nini_hub/features/activity/domain/activity_log.dart';
import 'package:nini_hub/features/activity/domain/activity_repository.dart';

void main() {
  test(
    'activity log preserves statuses, nullable fields, and UTC instants',
    () {
      final startedAt = DateTime.utc(2026, 8, 22, 12, 30);
      final completedAt = DateTime.utc(2026, 8, 22, 12, 31);
      final log = ActivityLog(
        id: 'log-1',
        profileId: null,
        command: 'codex exec',
        summary: 'Finished command',
        output: 'done',
        status: ActivityLogStatus.success,
        exitCode: null,
        startedAt: startedAt,
        completedAt: completedAt,
      );

      expect(
        ActivityLogStatus.values,
        equals([
          ActivityLogStatus.success,
          ActivityLogStatus.running,
          ActivityLogStatus.error,
          ActivityLogStatus.timeout,
          ActivityLogStatus.unknown,
        ]),
      );
      expect(log.id, 'log-1');
      expect(log.profileId, isNull);
      expect(log.command, 'codex exec');
      expect(log.summary, 'Finished command');
      expect(log.output, 'done');
      expect(log.status, ActivityLogStatus.success);
      expect(log.exitCode, isNull);
      expect(log.startedAt, same(startedAt));
      expect(log.completedAt, same(completedAt));
      expect(log.startedAt.isUtc, isTrue);
      expect(log.completedAt!.isUtc, isTrue);
    },
  );

  test('load requests 250 and preserves repository order immutably', () async {
    final newest = _log('newest');
    final older = _log('older');
    final repository = _FakeActivityRepository(loaded: [newest, older]);

    final snapshot = await LoadActivityHistory(repository: repository)();

    expect(repository.events, ['load:250']);
    expect(snapshot.logs, [same(newest), same(older)]);
    expect(() => snapshot.logs.clear(), throwsUnsupportedError);
  });

  test('observe streams the latest 250 in repository order', () async {
    final newest = _log('newest');
    final repository = _FakeActivityRepository(loaded: [newest]);

    final snapshot = await ObserveActivityHistory(
      repository: repository,
    )().first;

    expect(repository.events, ['watch:250']);
    expect(snapshot.logs, [same(newest)]);
    expect(() => snapshot.logs.clear(), throwsUnsupportedError);
  });

  test('clear deletes before reloading recent history', () async {
    final remaining = _log('remaining');
    final repository = _FakeActivityRepository(loaded: [remaining]);

    final snapshot = await ClearActivityHistory(repository: repository)();

    expect(repository.events, ['clear', 'load:250']);
    expect(snapshot.logs, [same(remaining)]);
  });

  test('clear failure prevents reload and preserves original error', () async {
    final cause = StateError('clear failed');
    final repository = _FakeActivityRepository(clearError: cause);

    await expectLater(
      ClearActivityHistory(repository: repository)(),
      throwsA(same(cause)),
    );
    expect(repository.events, ['clear']);
  });

  test('reload failure after clear reports that clear was applied', () async {
    final cause = StateError('reload failed');
    final repository = _FakeActivityRepository(loadError: cause);

    await expectLater(
      ClearActivityHistory(repository: repository)(),
      throwsA(
        isA<ActivityClearAppliedFailure>().having(
          (failure) => failure.cause,
          'cause',
          same(cause),
        ),
      ),
    );
    expect(repository.events, ['clear', 'load:250']);
  });
}

ActivityLog _log(String id) {
  return ActivityLog(
    id: id,
    profileId: 'profile-1',
    command: 'codex exec',
    summary: id,
    output: '',
    status: ActivityLogStatus.success,
    exitCode: 0,
    startedAt: DateTime.utc(2026, 8, 22, 12),
    completedAt: DateTime.utc(2026, 8, 22, 12, 1),
  );
}

final class _FakeActivityRepository implements ActivityRepository {
  _FakeActivityRepository({
    this.loaded = const [],
    this.clearError,
    this.loadError,
  });

  final List<ActivityLog> loaded;
  final Object? clearError;
  final Object? loadError;
  final List<String> events = [];

  @override
  Future<void> clearAll() async {
    events.add('clear');
    if (clearError case final error?) throw error;
  }

  @override
  Future<List<ActivityLog>> loadRecent({required int limit}) async {
    events.add('load:$limit');
    if (loadError case final error?) throw error;
    return List.of(loaded);
  }

  @override
  Stream<List<ActivityLog>> watchRecent({required int limit}) {
    events.add('watch:$limit');
    return Stream.value(List.of(loaded));
  }
}
