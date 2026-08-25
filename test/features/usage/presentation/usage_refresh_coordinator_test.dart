import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/usage/application/usage_calendar.dart';
import 'package:nini_hub/features/usage/application/usage_refresh.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/features/usage/presentation/controllers/usage_controller.dart';
import 'package:nini_hub/features/usage/presentation/controllers/usage_refresh_coordinator.dart';
import 'package:nini_hub/features/usage/presentation/state/usage_state.dart';

void main() {
  late _Fixture fixture;

  tearDown(() => fixture.dispose());

  test('refresh keeps effect and visible synchronization order', () async {
    fixture = _Fixture(profiles: [_profile('primary')]);

    await fixture.coordinator.refreshOne('primary');

    expect(fixture.events, [
      'discover',
      'provider:primary',
      'persist:primary',
      'activity-write:primary',
      'keep-alive:primary',
      'activity-reload:1',
      'calendar:1',
      'accounts-reload:1',
    ]);
    expect(fixture.state.isCalendarInitialized, isTrue);
  });

  test('concurrent refresh completions serialize visible reloads', () async {
    fixture = _Fixture(profiles: [_profile('first'), _profile('second')]);
    final firstProvider = fixture.provider.gate('first');
    final secondProvider = fixture.provider.gate('second');
    final firstReload = Completer<void>();
    fixture.activityReloadGate = firstReload;

    final first = fixture.coordinator.refreshOne('first');
    final second = fixture.coordinator.refreshOne('second');
    await _flushMicrotasks();
    firstProvider.complete();
    secondProvider.complete();
    await _flushMicrotasks();

    expect(fixture.activityReloads, 1);
    expect(fixture.calendar.calls, 0);
    firstReload.complete();
    await Future.wait([first, second]);

    expect(fixture.activityReloads, 2);
    expect(fixture.calendar.calls, 2);
    expect(fixture.accountReloads, 2);
    expect(
      fixture.events.where(
        (event) =>
            event.startsWith('activity-reload') ||
            event.startsWith('calendar') ||
            event.startsWith('accounts-reload'),
      ),
      [
        'activity-reload:1',
        'calendar:1',
        'accounts-reload:1',
        'activity-reload:2',
        'calendar:2',
        'accounts-reload:2',
      ],
    );
  });

  test('typed refresh failure skips every downstream reload', () async {
    fixture = _Fixture(profiles: [_profile('disabled', isAvailable: false)]);

    await expectLater(
      fixture.coordinator.refreshOne('disabled'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('No se realizó ninguna consulta'),
        ),
      ),
    );

    expect(fixture.events, ['discover']);
    expect(fixture.activityReloads, 0);
    expect(fixture.calendar.calls, 0);
    expect(fixture.accountReloads, 0);
  });

  test('batch success performs one downstream synchronization', () async {
    fixture = _Fixture(profiles: [_profile('first'), _profile('second')]);

    await fixture.coordinator.refreshAll();

    expect(fixture.provider.profileIds.toSet(), {'first', 'second'});
    expect(fixture.activityReloads, 1);
    expect(fixture.calendar.calls, 1);
    expect(fixture.accountReloads, 1);
  });
}

final class _Fixture {
  _Fixture({required List<Profile> profiles})
    : discovery = _FakeDiscovery(profiles),
      provider = _FakeUsageProvider(),
      calendar = _FakeCalendarRepository() {
    final refreshProfile = RefreshProfileUsage(
      provider: provider,
      repository: _FakeSnapshotRepository(events),
      activity: _FakeActivityRecorder(events),
      keepAlive: _FakeKeepAliveScheduler(events),
    );
    provider.events = events;
    calendar.events = events;
    definition = NotifierProvider<UsageController, UsageState>(
      () => UsageController(
        refreshUsage: RefreshUsage(
          discovery: discovery.withEvents(events),
          refreshProfile: refreshProfile,
        ),
        refreshAllUsage: RefreshAllUsage(
          discovery: discovery.withEvents(events),
          refreshProfile: refreshProfile,
        ),
        loadUsageCalendar: LoadUsageCalendar(repository: calendar),
      ),
    );
    container = ProviderContainer();
    controller = container.read(definition.notifier);
    coordinator = UsageRefreshCoordinator(
      controller: controller,
      readState: () => container.read(definition),
      reloadActivity: () async {
        activityReloads++;
        events.add('activity-reload:$activityReloads');
        final gate = activityReloadGate;
        activityReloadGate = null;
        if (gate != null) await gate.future;
      },
      reloadAccounts: () async {
        accountReloads++;
        events.add('accounts-reload:$accountReloads');
      },
    );
  }

  final List<String> events = [];
  final _FakeDiscovery discovery;
  final _FakeUsageProvider provider;
  final _FakeCalendarRepository calendar;
  late final NotifierProvider<UsageController, UsageState> definition;
  late final ProviderContainer container;
  late final UsageController controller;
  late final UsageRefreshCoordinator coordinator;
  Completer<void>? activityReloadGate;
  int activityReloads = 0;
  int accountReloads = 0;
  bool _disposed = false;

  UsageState get state => container.read(definition);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }
}

final class _FakeDiscovery implements ProfileDiscovery {
  _FakeDiscovery(this.profiles, [this.events]);

  final List<Profile> profiles;
  final List<String>? events;

  _FakeDiscovery withEvents(List<String> target) =>
      _FakeDiscovery(profiles, target);

  @override
  Future<List<Profile>> discover() async {
    events?.add('discover');
    return List.of(profiles);
  }
}

final class _FakeUsageProvider implements UsageProvider {
  final Map<String, Completer<void>> _gates = {};
  final List<String> profileIds = [];
  List<String>? events;

  Completer<void> gate(String profileId) =>
      _gates.putIfAbsent(profileId, Completer<void>.new);

  @override
  Future<UsageSnapshot> refresh(Profile profile) async {
    profileIds.add(profile.id);
    events?.add('provider:${profile.id}');
    final gate = _gates[profile.id];
    if (gate != null) await gate.future;
    return _snapshot();
  }
}

final class _FakeSnapshotRepository implements UsageSnapshotRepository {
  const _FakeSnapshotRepository(this.events);

  final List<String> events;

  @override
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  }) async {
    events.add('persist:$profileId');
  }
}

final class _FakeActivityRecorder implements UsageActivityRecorder {
  const _FakeActivityRecorder(this.events);

  final List<String> events;

  @override
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) async {
    events.add('activity-write:${profile.id}');
  }
}

final class _FakeKeepAliveScheduler implements UsageKeepAliveScheduler {
  const _FakeKeepAliveScheduler(this.events);

  final List<String> events;

  @override
  bool scheduleIfEligible({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) {
    events.add('keep-alive:${profile.id}');
    return true;
  }
}

final class _FakeCalendarRepository implements UsageCalendarRepository {
  List<String>? events;
  int calls = 0;

  @override
  Future<UsageCalendar> loadCalendar() async {
    calls++;
    events?.add('calendar:$calls');
    return UsageCalendar(const []);
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

Profile _profile(String id, {bool isAvailable = true}) => Profile(
  id: id,
  toolKey: 'codex',
  profileName: id,
  commandName: 'codex-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: true,
  isAvailable: isAvailable,
  isFavorite: false,
);
