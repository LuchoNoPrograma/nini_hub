import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/heartbeat/application/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_failure.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  final now = DateTime.utc(2026, 8, 22, 12);

  test('manual run validates the rediscovered current profile', () async {
    final harness = _Harness(
      now: now,
      profiles: [_profile(isAvailable: false, hasAuthFile: false)],
    );

    await expectLater(
      harness.run(profileId: 'profile'),
      throwsA(
        isA<HeartbeatProfileUnavailableFailure>().having(
          (failure) => failure.reason,
          'reason',
          HeartbeatProfileUnavailableReason.deactivated,
        ),
      ),
    );

    expect(harness.discovery.calls, 1);
    expect(harness.scheduler.acquireCalls, 0);
    expect(harness.command.calls, 0);
    expect(harness.repository.saves, isEmpty);
  });

  test('automatic observation asks for one bounded historical value', () async {
    final profile = _profile();
    final previousAt = now.subtract(const Duration(seconds: 30));
    final reset = now.add(const Duration(days: 7));
    final harness = _Harness(now: now, profiles: [profile]);
    harness.history.result = _observation(
      previousAt,
      resetAt: previousAt.add(const Duration(days: 7)),
    );
    harness.probe.results.addAll([
      _snapshot(now.add(const Duration(seconds: 10)), resetAt: reset),
      _snapshot(now.add(const Duration(seconds: 20)), resetAt: reset),
    ]);

    final result = await harness.observe(
      profile: profile,
      snapshot: _snapshot(now, resetAt: reset),
    );

    expect(result.outcome, HeartbeatOutcome.verified);
    expect(harness.history.calls, 1);
    expect(harness.history.expectedWindowMinutes, [10080]);
    expect(harness.command.calls, 1);
    expect(harness.probe.calls, 2);
    expect(harness.repository.saves.last.status, HeartbeatStatus.verified);
    expect(
      harness.repository.saves.last.verifiedIdentity?.accountEmail,
      'account@example.com',
    );
    expect(harness.activity.kinds, [HeartbeatActivityKind.verified]);
    expect(harness.scheduler.acquired, isEmpty);
  });

  test(
    'a scheduled probe cannot persist after the scheduler is disabled',
    () async {
      final profile = _profile();
      final harness = _Harness(now: now, profiles: [profile]);
      harness.scheduler.retained.add(profile.id);
      final pending = Completer<UsageSnapshot>();
      harness.probe.handler = (_) => pending.future;

      final operation = harness.scheduled(profile.id);
      await _waitFor(() => harness.probe.calls == 1);
      harness.scheduler.enabled = false;
      harness.scheduler.retained.clear();
      pending.completeError(StateError('offline after disable'));

      final result = await operation;

      expect(result.outcome, HeartbeatOutcome.skipped);
      expect(harness.profileRepository.findCalls, 1);
      expect(harness.discovery.calls, 0);
      expect(harness.repository.loads, 0);
      expect(harness.repository.saves, isEmpty);
      expect(harness.activity.kinds, isEmpty);
      expect(harness.scheduler.scheduled, isEmpty);
    },
  );

  test(
    'manual command failure persists the first retry and releases the lease',
    () async {
      final profile = _profile();
      final harness = _Harness(now: now, profiles: [profile]);
      harness.command.result = const HeartbeatCommandResult.failure('offline');

      final result = await harness.run(profileId: profile.id);

      expect(result.outcome, HeartbeatOutcome.failed);
      expect(harness.repository.saves.last.status, HeartbeatStatus.failed);
      expect(harness.repository.saves.last.retryCount, 1);
      expect(
        harness.repository.saves.last.retryAfter,
        now.add(const Duration(minutes: 15)),
      );
      expect(
        harness.scheduler.scheduled.single.at,
        now.add(const Duration(minutes: 15)),
      );
      expect(harness.scheduler.acquired, isEmpty);
    },
  );

  test('manual 30 day cycle reports command sent before unverified', () async {
    final profile = _profile();
    final harness = _Harness(now: now, profiles: [profile]);
    const monthlyMinutes = 30 * Duration.hoursPerDay * Duration.minutesPerHour;
    harness.probe.results.addAll([
      _snapshot(
        now.add(const Duration(seconds: 10)),
        resetAt: now.add(const Duration(days: 30, seconds: 10)),
        windowDurationMinutes: monthlyMinutes,
      ),
      _snapshot(
        now.add(const Duration(seconds: 20)),
        resetAt: now.add(const Duration(days: 30, seconds: 20)),
        windowDurationMinutes: monthlyMinutes,
      ),
    ]);

    final result = await harness.run(
      profileId: profile.id,
      expectedWindowMinutes: monthlyMinutes,
    );

    expect(result.outcome, HeartbeatOutcome.unverified);
    expect(
      result.message,
      'Comando enviado; Codex respondió, pero todavía no se pudo confirmar '
      'el ciclo de 30 días.',
    );
    expect(harness.command.calls, 1);
    expect(harness.activity.kinds, [HeartbeatActivityKind.unverified]);
  });

  test(
    'duplicate manual work is skipped without invoking external effects',
    () async {
      final profile = _profile();
      final harness = _Harness(now: now, profiles: [profile]);
      harness.scheduler.busy = true;

      final result = await harness.run(profileId: profile.id);

      expect(result.outcome, HeartbeatOutcome.skipped);
      expect(harness.repository.loads, 0);
      expect(harness.command.calls, 0);
      expect(harness.probe.calls, 0);
    },
  );
}

final class _Harness {
  _Harness({required DateTime now, required List<Profile> profiles}) {
    discovery = _Discovery(profiles);
    profileRepository = _ProfileRepository(profiles);
    repository = _Repository();
    history = _History();
    command = _Command();
    probe = _Probe();
    scheduler = _Scheduler();
    clock = _Clock(now);
    delay = _Delay();
    activity = _Activity();
    execute = ExecuteHeartbeat(
      policy: const HeartbeatPolicy(),
      repository: repository,
      command: command,
      probe: probe,
      scheduler: scheduler,
      clock: clock,
      delay: delay,
      activity: activity,
      verificationDelay: Duration.zero,
    );
    observe = ObserveHeartbeatUsage(
      policy: const HeartbeatPolicy(),
      repository: repository,
      history: history,
      scheduler: scheduler,
      clock: clock,
      activity: activity,
      execute: execute,
    );
    run = RunHeartbeat(
      discovery: discovery,
      repository: repository,
      scheduler: scheduler,
      execute: execute,
    );
    scheduled = ProbeHeartbeat(
      profiles: profileRepository,
      probe: probe,
      scheduler: scheduler,
      observe: observe,
    );
  }

  late final _Discovery discovery;
  late final _ProfileRepository profileRepository;
  late final _Repository repository;
  late final _History history;
  late final _Command command;
  late final _Probe probe;
  late final _Scheduler scheduler;
  late final _Clock clock;
  late final _Delay delay;
  late final _Activity activity;
  late final ExecuteHeartbeat execute;
  late final ObserveHeartbeatUsage observe;
  late final RunHeartbeat run;
  late final ProbeHeartbeat scheduled;
}

final class _ProfileRepository implements ProfileRepository {
  _ProfileRepository(List<Profile> profiles)
    : _profiles = {for (final profile in profiles) profile.id: profile};

  final Map<String, Profile> _profiles;
  int findCalls = 0;

  @override
  Future<Profile?> findById(String profileId) async {
    findCalls++;
    return _profiles[profileId];
  }

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {}
}

final class _Discovery implements ProfileDiscovery {
  _Discovery(this.profiles);

  final List<Profile> profiles;
  int calls = 0;

  @override
  Future<List<Profile>> discover() async {
    calls++;
    return profiles;
  }
}

final class _Repository implements HeartbeatStateRepository {
  final Map<String, HeartbeatState> states = {};
  final List<HeartbeatState> saves = [];
  int loads = 0;

  @override
  Future<HeartbeatState> load(String profileId) async {
    loads++;
    return states[profileId] ?? HeartbeatState();
  }

  @override
  Future<void> save({
    required String profileId,
    required HeartbeatState state,
  }) async {
    states[profileId] = state;
    saves.add(state);
  }
}

final class _History implements HeartbeatHistoryRepository {
  HeartbeatObservation? result;
  int calls = 0;
  final List<int> expectedWindowMinutes = [];

  @override
  Future<HeartbeatObservation?> loadLatestBefore({
    required String profileId,
    required DateTime before,
    required int expectedWindowMinutes,
  }) async {
    calls++;
    this.expectedWindowMinutes.add(expectedWindowMinutes);
    return result;
  }
}

final class _Command implements HeartbeatCommandGateway {
  HeartbeatCommandResult result = const HeartbeatCommandResult.success();
  int calls = 0;

  @override
  Future<HeartbeatCommandResult> execute({
    required Profile profile,
    required String prompt,
  }) async {
    calls++;
    expect(prompt, contains('Responde exactamente OK'));
    return result;
  }
}

final class _Probe implements HeartbeatQuotaProbe {
  final List<UsageSnapshot> results = [];
  Future<UsageSnapshot> Function(Profile)? handler;
  int calls = 0;

  @override
  Future<UsageSnapshot> probe(Profile profile) {
    calls++;
    final callback = handler;
    if (callback != null) return callback(profile);
    if (results.isEmpty) throw StateError('missing probe result');
    return Future.value(results.removeAt(0));
  }
}

final class _Scheduler implements HeartbeatScheduler {
  @override
  bool enabled = true;

  bool busy = false;
  int acquireCalls = 0;
  final Set<String> retained = {};
  final Set<String> acquired = {};
  final List<_Scheduled> scheduled = [];
  final List<String> cancelled = [];

  @override
  bool acquire(String profileId) {
    acquireCalls++;
    return !busy && acquired.add(profileId);
  }

  @override
  void cancel(String profileId) => cancelled.add(profileId);

  @override
  bool isRetained(String profileId) => retained.contains(profileId);

  @override
  void release(String profileId) => acquired.remove(profileId);

  @override
  void schedule({required Profile profile, required DateTime at}) {
    scheduled.add(_Scheduled(profile.id, at));
  }
}

final class _Scheduled {
  const _Scheduled(this.profileId, this.at);

  final String profileId;
  final DateTime at;
}

final class _Clock implements HeartbeatClock {
  const _Clock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}

final class _Delay implements HeartbeatDelay {
  final List<Duration> calls = [];

  @override
  Future<void> wait(Duration duration) async => calls.add(duration);
}

final class _Activity implements HeartbeatActivityRecorder {
  final List<HeartbeatActivityKind> kinds = [];

  @override
  Future<void> record({
    required Profile profile,
    required HeartbeatActivityKind kind,
    required String message,
  }) async {
    kinds.add(kind);
  }
}

Profile _profile({bool isAvailable = true, bool hasAuthFile = true}) => Profile(
  id: 'profile',
  toolKey: 'codex',
  profileName: 'profile',
  displayName: 'Profile',
  profileHome: '/tmp/profile',
  source: ProfileSource.multiCli,
  kind: isAvailable ? ProfileKind.shared : ProfileKind.deactivated,
  hasAuthFile: hasAuthFile,
  isAvailable: isAvailable,
  isFavorite: false,
);

HeartbeatObservation _observation(
  DateTime observedAt, {
  required DateTime resetAt,
}) => HeartbeatObservation(
  limitId: 'codex',
  usedPercent: 0,
  windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
  resetsAt: resetAt,
  observedAt: observedAt,
  accountEmail: 'account@example.com',
  planType: 'pro',
);

UsageSnapshot _snapshot(
  DateTime completedAt, {
  required DateTime resetAt,
  int windowDurationMinutes = HeartbeatPolicy.weeklyMinutes,
}) => UsageSnapshot(
  status: UsageRefreshStatus.success,
  startedAt: completedAt.subtract(const Duration(seconds: 1)),
  completedAt: completedAt,
  accountEmail: 'account@example.com',
  planType: 'pro',
  windows: [
    UsageQuotaWindow(
      limitId: 'codex',
      windowType: 'rolling',
      usedPercent: 0,
      windowDurationMinutes: windowDurationMinutes,
      resetsAt: resetAt,
    ),
  ],
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}
