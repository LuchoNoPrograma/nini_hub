import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/usage/data/dart_usage_auto_refresh_scheduler.dart';

void main() {
  test('uses one timer, catches late wake, and cancels at disposal', () async {
    var now = DateTime.utc(2026, 9, 10, 12);
    var deadline = now.add(const Duration(minutes: 1));
    final timers = <_Timer>[];
    final observed = <DateTime>[];
    final scheduler = DartUsageAutoRefreshScheduler(
      now: () => now,
      nextAt: () => deadline,
      timerFactory: (delay, callback) {
        final timer = _Timer(delay, callback);
        timers.add(timer);
        return timer;
      },
      check: () async {
        observed.add(now);
        deadline = now.add(const Duration(hours: 5));
      },
    );
    scheduler.start();
    scheduler.reschedule();
    expect(timers.where((timer) => timer.isActive), hasLength(1));
    expect(timers.last.duration, const Duration(seconds: 30));
    now = now.add(const Duration(hours: 7));
    timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(observed, [now]);
    expect(timers.last.duration, const Duration(seconds: 30));
    scheduler.dispose();
    expect(timers.where((timer) => timer.isActive), isEmpty);
  });

  test(
    'never overlaps checks, even when consumers reschedule during a read',
    () async {
      final release = Completer<void>();
      final timers = <_Timer>[];
      var count = 0;
      final scheduler = DartUsageAutoRefreshScheduler(
        nextAt: () => DateTime.utc(2000),
        timerFactory: (delay, callback) {
          final timer = _Timer(delay, callback);
          timers.add(timer);
          return timer;
        },
        check: () async {
          count++;
          await release.future;
        },
      );
      scheduler.start();
      expect(timers.last.duration, Duration.zero);
      timers.last.fire();
      scheduler.reschedule();
      expect(timers, hasLength(1));
      expect(count, 1);
      scheduler.dispose();
      release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(timers, hasLength(1));
    },
  );
}

final class _Timer implements Timer {
  _Timer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool active = true;
  void fire() {
    if (active) {
      active = false;
      callback();
    }
  }

  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
}
