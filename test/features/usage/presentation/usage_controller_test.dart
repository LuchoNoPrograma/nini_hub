import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_ports.dart';
import 'package:multi_cli_ai/features/usage/application/usage_calendar.dart';
import 'package:multi_cli_ai/features/usage/application/usage_refresh.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_failure.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_ports.dart';
import 'package:multi_cli_ai/features/usage/presentation/controllers/usage_controller.dart';
import 'package:multi_cli_ai/features/usage/presentation/state/usage_state.dart';

void main() {
  test('state normalizes selection and protects operation collections', () {
    final snapshot = _snapshot();
    final failure = UsageOperationFailure(
      cause: StateError('failure'),
      message: 'Falló.',
    );
    final state = UsageState(
      selectedDay: DateTime.utc(2026, 8, 22, 23, 59),
      refreshingProfileIds: const {'primary'},
      completedBatchByProfile: {'primary': snapshot},
      profileFailures: {'secondary': failure},
    );

    expect(state.selectedDay, DateTime(2026, 8, 22));
    expect(state.isRefreshing, isTrue);
    expect(state.isRefreshingProfile('primary'), isTrue);
    expect(state.failureForProfile('secondary'), same(failure));
    expect(
      () => state.refreshingProfileIds.add('other'),
      throwsUnsupportedError,
    );
    expect(
      () => state.completedBatchByProfile['other'] = snapshot,
      throwsUnsupportedError,
    );
    expect(
      () => state.profileFailures['other'] = failure,
      throwsUnsupportedError,
    );
  });

  group('UsageController', () {
    late _Fixture fixture;

    tearDown(() => fixture.dispose());

    test(
      'latest calendar request wins and failure retains the prior snapshot',
      () async {
        fixture = _Fixture(profiles: const []);
        final original = _calendar(DateTime(2026, 8, 20), tokens: 10);
        fixture.calendar.responses.add(Future.value(original));

        expect(await fixture.controller.loadCalendar(), isTrue);
        expect(fixture.state.calendar, same(original));
        expect(fixture.state.isCalendarInitialized, isTrue);

        final older = Completer<UsageCalendar>();
        final newer = Completer<UsageCalendar>();
        fixture.calendar.responses.addAll([older.future, newer.future]);
        final olderLoad = fixture.controller.loadCalendar();
        final newerLoad = fixture.controller.loadCalendar();
        fixture.controller.selectDay(DateTime.utc(2026, 8, 23, 17));

        older.complete(_calendar(DateTime(2026, 8, 21), tokens: 20));
        expect(await olderLoad, isFalse);
        expect(fixture.state.isCalendarLoading, isTrue);
        expect(fixture.state.calendar, same(original));

        final latest = _calendar(DateTime(2026, 8, 22), tokens: 30);
        newer.complete(latest);
        expect(await newerLoad, isTrue);
        expect(fixture.state.calendar, same(latest));
        expect(fixture.state.selectedDay, DateTime(2026, 8, 23));
        expect(fixture.state.isCalendarLoading, isFalse);

        final cause = StateError('calendar failed');
        final failing = Completer<UsageCalendar>();
        fixture.calendar.responses.add(failing.future);
        final failedLoad = fixture.controller.loadCalendar();
        failing.completeError(cause);

        expect(await failedLoad, isFalse);
        expect(fixture.state.calendar, same(latest));
        expect(fixture.state.isCalendarInitialized, isTrue);
        expect(fixture.state.calendarFailure?.cause, same(cause));
        expect(
          fixture.state.calendarFailure?.message,
          'No se pudo cargar el calendario de uso.',
        );
        fixture.controller.clearCalendarFailure();
        expect(fixture.state.calendarFailure, isNull);
      },
    );

    test(
      'different profiles refresh concurrently while duplicate and batch overlap are rejected',
      () async {
        fixture = _Fixture(profiles: [_profile('first'), _profile('second')]);
        final firstGate = fixture.provider.gate('first');
        final secondGate = fixture.provider.gate('second');

        final first = fixture.controller.refreshOne('first');
        final second = fixture.controller.refreshOne('second');
        expect(await fixture.controller.refreshOne('first'), isFalse);
        expect(await fixture.controller.refreshAll(), isFalse);
        await _flushMicrotasks();

        expect(fixture.state.refreshingProfileIds, {'first', 'second'});
        expect(fixture.provider.maxActive, 2);
        fixture.calendar.responses.add(
          Future.value(_calendar(DateTime(2026, 8, 22), tokens: 40)),
        );
        expect(await fixture.controller.loadCalendar(), isTrue);
        expect(fixture.state.refreshingProfileIds, {'first', 'second'});

        firstGate.complete();
        expect(await first, isTrue);
        expect(fixture.state.refreshingProfileIds, {'second'});
        secondGate.complete();
        expect(await second, isTrue);

        expect(fixture.state.isRefreshing, isFalse);
        expect(fixture.provider.profileIds, ['first', 'second']);
        expect(fixture.calendar.calls, 1);
      },
    );

    test('typed individual failures remain isolated by profile', () async {
      fixture = _Fixture(
        profiles: [
          _profile(
            'deactivated',
            isAvailable: false,
            kind: ProfileKind.deactivated,
          ),
          _profile('unsupported', toolKey: 'claude-cli'),
          _profile('applied'),
        ],
      );
      fixture.activity.failures['applied'] = StateError('activity failed');

      expect(await fixture.controller.refreshOne('missing'), isFalse);
      expect(await fixture.controller.refreshOne('deactivated'), isFalse);
      expect(await fixture.controller.refreshOne('unsupported'), isFalse);
      expect(await fixture.controller.refreshOne('applied'), isFalse);

      expect(
        fixture.state.failureForProfile('missing')?.cause,
        isA<UsageProfileNotFoundFailure>(),
      );
      expect(
        fixture.state.failureForProfile('missing')?.message,
        'El perfil ya no está disponible en este equipo. '
        'No se realizó ninguna consulta.',
      );
      expect(
        fixture.state.failureForProfile('deactivated')?.cause,
        isA<UsageProfileUnavailableFailure>(),
      );
      expect(
        fixture.state.failureForProfile('deactivated')?.message,
        'La cuenta está desactivada en este equipo. '
        'No se realizó ninguna consulta.',
      );
      expect(
        fixture.state.failureForProfile('unsupported')?.cause,
        isA<UsageUnsupportedProviderFailure>(),
      );
      expect(
        fixture.state.failureForProfile('unsupported')?.message,
        'Esta herramienta todavía no expone cuotas en esta aplicación.',
      );
      expect(
        fixture.state.failureForProfile('applied')?.cause,
        isA<UsageRefreshAppliedFailure>().having(
          (failure) => failure.progress,
          'progress',
          UsageRefreshProgress.snapshotPersisted,
        ),
      );
      expect(
        fixture.state.failureForProfile('applied')?.message,
        'El uso se guardó, pero no se pudo registrar la actividad.',
      );
      expect(fixture.state.profileFailures, hasLength(4));

      fixture.controller.clearProfileFailure('missing');
      expect(fixture.state.failureForProfile('missing'), isNull);
      expect(fixture.state.profileFailures, hasLength(3));
    });

    test(
      'batch reports immutable progress and keeps all completed profiles on partial failure',
      () async {
        var concurrencyCalls = 0;
        fixture = _Fixture(
          profiles: [_profile('first'), _profile('failing'), _profile('last')],
          refreshConcurrency: () {
            concurrencyCalls++;
            return 2;
          },
        );
        final firstGate = fixture.provider.gate('first');
        final failingGate = fixture.provider.gate('failing');
        final lastGate = fixture.provider.gate('last');
        fixture.activity.failures['failing'] = StateError('activity failed');

        final batch = fixture.controller.refreshAll();
        await _flushMicrotasks();
        expect(fixture.state.isRefreshingAll, isTrue);
        expect(fixture.provider.profileIds, ['first', 'failing']);
        expect(await fixture.controller.refreshOne('first'), isFalse);

        firstGate.complete();
        await _flushMicrotasks();
        expect(fixture.state.completedBatchByProfile.keys, ['first']);
        expect(fixture.provider.profileIds, ['first', 'failing', 'last']);

        failingGate.complete();
        lastGate.complete();
        expect(await batch, isFalse);

        expect(concurrencyCalls, 1);
        expect(fixture.provider.maxActive, 2);
        expect(fixture.state.isRefreshingAll, isFalse);
        expect(fixture.state.completedBatchByProfile.keys.toSet(), {
          'first',
          'last',
        });
        expect(
          fixture.state.batchFailure?.cause,
          isA<UsageBatchFailure>()
              .having(
                (failure) => failure.failedProfileId,
                'failedProfileId',
                'failing',
              )
              .having(
                (failure) => failure.cause,
                'cause',
                isA<UsageRefreshAppliedFailure>(),
              ),
        );
        expect(
          fixture.state.batchFailure?.message,
          'La actualización múltiple quedó incompleta. '
          'El uso se guardó, pero no se pudo registrar la actividad.',
        );
        expect(
          () => fixture.state.completedBatchByProfile['other'] = _snapshot(),
          throwsUnsupportedError,
        );
        fixture.controller.clearBatchFailure();
        expect(fixture.state.batchFailure, isNull);
        expect(fixture.calendar.calls, 0);
      },
    );

    test(
      'late calendar and refresh results are ignored after disposal',
      () async {
        fixture = _Fixture(profiles: [_profile('primary')]);
        final refreshGate = fixture.provider.gate('primary');
        final calendarGate = Completer<UsageCalendar>();
        fixture.calendar.responses.add(calendarGate.future);

        final refresh = fixture.controller.refreshOne('primary');
        final calendar = fixture.controller.loadCalendar();
        await _flushMicrotasks();
        fixture.dispose();
        refreshGate.complete();
        calendarGate.complete(_calendar(DateTime(2026, 8, 22), tokens: 50));

        expect(await refresh, isFalse);
        expect(await calendar, isFalse);
      },
    );
  });
}

final class _Fixture {
  _Fixture({
    required List<Profile> profiles,
    int Function()? refreshConcurrency,
  }) : discovery = _FakeDiscovery(profiles),
       provider = _ControlledUsageProvider(),
       repository = _FakeSnapshotRepository(),
       activity = _FakeActivityRecorder(),
       keepAlive = _FakeKeepAliveScheduler(),
       calendar = _FakeCalendarRepository() {
    final refreshProfile = RefreshProfileUsage(
      provider: provider,
      repository: repository,
      activity: activity,
      keepAlive: keepAlive,
    );
    refreshUsage = RefreshUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    );
    refreshAllUsage = RefreshAllUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    );
    loadUsageCalendar = LoadUsageCalendar(repository: calendar);
    providerDefinition = NotifierProvider<UsageController, UsageState>(
      () => UsageController(
        refreshUsage: refreshUsage,
        refreshAllUsage: refreshAllUsage,
        loadUsageCalendar: loadUsageCalendar,
        refreshConcurrency: refreshConcurrency,
      ),
    );
    container = ProviderContainer();
    controller = container.read(providerDefinition.notifier);
  }

  final _FakeDiscovery discovery;
  final _ControlledUsageProvider provider;
  final _FakeSnapshotRepository repository;
  final _FakeActivityRecorder activity;
  final _FakeKeepAliveScheduler keepAlive;
  final _FakeCalendarRepository calendar;
  late final RefreshUsage refreshUsage;
  late final RefreshAllUsage refreshAllUsage;
  late final LoadUsageCalendar loadUsageCalendar;
  late final NotifierProvider<UsageController, UsageState> providerDefinition;
  late final ProviderContainer container;
  late final UsageController controller;
  bool _isDisposed = false;

  UsageState get state => container.read(providerDefinition);

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    container.dispose();
  }
}

final class _FakeDiscovery implements ProfileDiscovery {
  _FakeDiscovery(this.profiles);

  final List<Profile> profiles;

  @override
  Future<List<Profile>> discover() async => List.of(profiles);
}

final class _ControlledUsageProvider implements UsageProvider {
  final Map<String, Completer<void>> _gates = {};
  final Map<String, Object> failures = {};
  final List<String> profileIds = [];
  int active = 0;
  int maxActive = 0;

  Completer<void> gate(String profileId) =>
      _gates.putIfAbsent(profileId, Completer<void>.new);

  @override
  Future<UsageSnapshot> refresh(Profile profile) async {
    profileIds.add(profile.id);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      final gate = _gates[profile.id];
      if (gate != null) await gate.future;
      final failure = failures[profile.id];
      if (failure != null) throw failure;
      return _snapshot();
    } finally {
      active--;
    }
  }
}

final class _FakeSnapshotRepository implements UsageSnapshotRepository {
  final List<String> savedProfileIds = [];

  @override
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  }) async {
    savedProfileIds.add(profileId);
  }
}

final class _FakeActivityRecorder implements UsageActivityRecorder {
  final Map<String, Object> failures = {};
  final List<String> recordedProfileIds = [];

  @override
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) async {
    final failure = failures[profile.id];
    if (failure != null) throw failure;
    recordedProfileIds.add(profile.id);
  }
}

final class _FakeKeepAliveScheduler implements UsageKeepAliveScheduler {
  final List<String> scheduledProfileIds = [];

  @override
  bool scheduleIfEligible({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) {
    scheduledProfileIds.add(profile.id);
    return true;
  }
}

final class _FakeCalendarRepository implements UsageCalendarRepository {
  final List<Future<UsageCalendar>> responses = [];
  int calls = 0;

  @override
  Future<UsageCalendar> loadCalendar() {
    calls++;
    if (responses.isEmpty) return Future.value(UsageCalendar(const []));
    return responses.removeAt(0);
  }
}

Future<void> _flushMicrotasks() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

UsageSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 22, 12);
  return UsageSnapshot(
    status: UsageRefreshStatus.success,
    startedAt: now,
    completedAt: now,
  );
}

UsageCalendar _calendar(DateTime day, {required int tokens}) => UsageCalendar([
  UsageCalendarDay(
    day: day,
    tokens: tokens,
    successfulChecks: 1,
    failedChecks: 0,
    lowestRemaining: 50,
    resetCount: 0,
    renewalCount: 0,
  ),
]);

Profile _profile(
  String id, {
  String toolKey = 'codex',
  bool isAvailable = true,
  ProfileKind kind = ProfileKind.full,
}) => Profile(
  id: id,
  toolKey: toolKey,
  profileName: id,
  commandName: '$toolKey-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  source: ProfileSource.multiCli,
  kind: kind,
  hasAuthFile: true,
  isAvailable: isAvailable,
  isFavorite: false,
);
