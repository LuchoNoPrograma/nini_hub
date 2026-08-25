import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/heartbeat/data/dart_heartbeat_scheduler.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

void main() {
  test('schedules one replaceable UTC timer per profile', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 23, 10));
    final timers = _TimerFactory();
    final probes = <String>[];
    final scheduler = DartHeartbeatScheduler(
      onScheduledProbe: (profileId) async => probes.add(profileId),
      clock: clock,
      timerFactory: timers.call,
    );
    addTearDown(scheduler.dispose);

    scheduler.schedule(
      profile: _profile('first'),
      at: DateTime.utc(2026, 8, 23, 10, 1),
    );
    final replaced = timers.timers.single;
    expect(replaced.duration, const Duration(minutes: 1));
    expect(scheduler.nextProbeAt('first'), DateTime.utc(2026, 8, 23, 10, 1));

    scheduler.schedule(
      profile: _profile('first'),
      at: DateTime.utc(2026, 8, 23, 9, 59),
    );
    expect(replaced.isActive, isFalse);
    expect(timers.timers.last.duration, Duration.zero);

    timers.timers.last.fire();
    await scheduler.waitUntilIdle();
    expect(probes, ['first']);
    expect(scheduler.nextProbeAt('first'), isNull);

    scheduler.schedule(
      profile: _profile('first'),
      at: DateTime.utc(2026, 8, 23, 11),
    );
    final cancelled = timers.timers.last;
    scheduler.cancel('first');
    expect(cancelled.isActive, isFalse);
    expect(scheduler.nextProbeAt('first'), isNull);
  });

  test('monitor queues one initial probe per continuous retention', () async {
    final firstGate = Completer<void>();
    final probes = <String>[];
    final scheduler = DartHeartbeatScheduler(
      onScheduledProbe: (profileId) async {
        probes.add(profileId);
        if (profileId == 'first' && !firstGate.isCompleted) {
          await firstGate.future;
        }
      },
    );
    addTearDown(scheduler.dispose);

    scheduler.monitorProfileIds(['first', 'second']);
    scheduler.monitorProfileIds(['first', 'second']);
    await _flush();
    expect(probes, ['first']);

    firstGate.complete();
    await scheduler.waitUntilIdle();
    expect(probes, ['first', 'second']);

    scheduler.monitorProfileIds(['first']);
    await scheduler.waitUntilIdle();
    expect(probes, ['first', 'second']);

    scheduler.monitorProfileIds(['first', 'second']);
    await scheduler.waitUntilIdle();
    expect(probes, ['first', 'second', 'second']);
  });

  test('scheduled probes are FIFO and recheck retained profiles', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 23, 10));
    final timers = _TimerFactory();
    final firstGate = Completer<void>();
    final probes = <String>[];
    final scheduler = DartHeartbeatScheduler(
      onScheduledProbe: (profileId) async {
        probes.add(profileId);
        if (profileId == 'first') await firstGate.future;
      },
      clock: clock,
      timerFactory: timers.call,
    );
    addTearDown(scheduler.dispose);
    scheduler.retainProfiles(['first', 'second']);
    scheduler.schedule(profile: _profile('first'), at: clock.value);
    scheduler.schedule(profile: _profile('second'), at: clock.value);

    timers.timers[0].fire();
    timers.timers[1].fire();
    await _flush();
    expect(probes, ['first']);

    scheduler.retainProfiles(['first']);
    firstGate.complete();
    await scheduler.waitUntilIdle();
    expect(probes, ['first']);
  });

  test(
    'operation queue is FIFO and rejects the same profile duplicate',
    () async {
      final firstGate = Completer<void>();
      final order = <String>[];
      final scheduler = DartHeartbeatScheduler(onScheduledProbe: (_) async {});
      addTearDown(scheduler.dispose);

      final first = scheduler.enqueueOperation<String>(
        profileId: 'first',
        operation: () async {
          order.add('first:start');
          await firstGate.future;
          order.add('first:end');
          return 'first';
        },
      );
      final duplicate = scheduler.enqueueOperation<String>(
        profileId: 'first',
        operation: () async {
          order.add('duplicate');
          return 'duplicate';
        },
      );
      final second = scheduler.enqueueOperation<String>(
        profileId: 'second',
        operation: () async {
          order.add('second');
          return 'second';
        },
      );

      expect(await duplicate, isNull);
      await _flush();
      expect(order, ['first:start']);
      firstGate.complete();
      expect(await first, 'first');
      expect(await second, 'second');
      expect(order, ['first:start', 'first:end', 'second']);
    },
  );

  test('disable cancels queued work but not an operation in flight', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 23, 10));
    final timers = _TimerFactory();
    final firstGate = Completer<void>();
    final order = <String>[];
    final scheduler = DartHeartbeatScheduler(
      onScheduledProbe: (_) async {},
      clock: clock,
      timerFactory: timers.call,
    );
    addTearDown(scheduler.dispose);
    scheduler.schedule(
      profile: _profile('timer'),
      at: clock.value.add(const Duration(minutes: 1)),
    );

    final first = scheduler.enqueueOperation<String>(
      profileId: 'first',
      operation: () async {
        order.add('first:start');
        await firstGate.future;
        order.add('first:end');
        return 'first';
      },
    );
    final queued = scheduler.enqueueOperation<String>(
      profileId: 'second',
      operation: () async {
        order.add('second');
        return 'second';
      },
    );
    await _flush();

    scheduler.enabled = false;
    expect(timers.timers.single.isActive, isFalse);
    expect(scheduler.nextProbeAt('timer'), isNull);
    expect(await queued, isNull);
    expect(order, ['first:start']);
    expect(scheduler.acquire('new'), isFalse);

    firstGate.complete();
    expect(await first, 'first');
    expect(order, ['first:start', 'first:end']);
  });

  test(
    'background work shares the FIFO, rejects duplicates, and absorbs errors',
    () async {
      final firstGate = Completer<void>();
      final order = <String>[];
      final failures = <Object>[];
      final scheduler = DartHeartbeatScheduler(onScheduledProbe: (_) async {});
      addTearDown(scheduler.dispose);

      final first = scheduler.enqueueOperation<String>(
        profileId: 'first',
        operation: () async {
          order.add('first:start');
          await firstGate.future;
          order.add('first:end');
          return 'first';
        },
      );
      expect(
        scheduler.enqueueBackgroundOperation(
          profileId: 'background',
          operation: () async {
            order.add('background');
            throw StateError('background failed');
          },
          onError: (error, _) => failures.add(error),
        ),
        isTrue,
      );
      expect(
        scheduler.enqueueBackgroundOperation(
          profileId: 'background',
          operation: () async => order.add('duplicate'),
        ),
        isFalse,
      );
      final last = scheduler.enqueueOperation<String>(
        profileId: 'last',
        operation: () async {
          order.add('last');
          return 'last';
        },
      );

      await _flush();
      expect(order, ['first:start']);
      firstGate.complete();
      expect(await first, 'first');
      expect(await last, 'last');
      await scheduler.waitUntilIdle();

      expect(order, ['first:start', 'first:end', 'background', 'last']);
      expect(failures.single, isA<StateError>());
    },
  );

  test('leases reject only the same profile and are releasable', () {
    final scheduler = DartHeartbeatScheduler(onScheduledProbe: (_) async {});
    addTearDown(scheduler.dispose);

    expect(scheduler.acquire('first'), isTrue);
    expect(scheduler.acquire('first'), isFalse);
    expect(scheduler.acquire('second'), isTrue);
    scheduler.release('first');
    expect(scheduler.acquire('first'), isTrue);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Clock implements HeartbeatClock {
  _Clock(this.value);

  DateTime value;

  @override
  DateTime nowUtc() => value;
}

final class _TimerFactory {
  final List<_FakeTimer> timers = [];

  Timer call(Duration duration, void Function() callback) {
    final timer = _FakeTimer(duration, callback);
    timers.add(timer);
    return timer;
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

Profile _profile(String id) => Profile(
  id: id,
  toolKey: 'codex',
  profileName: id,
  displayName: id,
  profileHome: '/profiles/$id',
  source: ProfileSource.multiCli,
  kind: ProfileKind.shared,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);
