import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/usage/data/serial_usage_operation_gate.dart';

void main() {
  test(
    'manual and automatic callers share the same concurrency limit',
    () async {
      final gate = SerialUsageOperationGate(concurrency: () => 2);
      final release = Completer<void>();
      var running = 0;
      var maximum = 0;
      final tasks = [
        for (var i = 0; i < 6; i++)
          gate.run('$i', () async {
            running++;
            if (running > maximum) maximum = running;
            await release.future;
            running--;
          }),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(running, 2);
      release.complete();
      await Future.wait(tasks);
      expect(maximum, 2);
    },
  );

  test(
    'holds a profile across both verification reads; other profiles progress',
    () async {
      final gate = SerialUsageOperationGate();
      final release = Completer<void>();
      final events = <String>[];
      final heartbeat = gate.run('a', () async {
        events.add('verify-first');
        await release.future;
        events.add('verify-second');
      });
      final manual = gate.run('a', () async => events.add('manual'));
      await gate.run('b', () async => events.add('other'));
      expect(events, ['verify-first', 'other']);
      release.complete();
      await Future.wait([heartbeat, manual]);
      expect(events, ['verify-first', 'other', 'verify-second', 'manual']);
    },
  );

  test(
    'failure releases the profile without failing subsequent operations',
    () async {
      final gate = SerialUsageOperationGate();
      await expectLater(
        gate.run('a', () async => throw StateError('failed')),
        throwsStateError,
      );
      expect(await gate.run('a', () async => 42), 42);
    },
  );
}
