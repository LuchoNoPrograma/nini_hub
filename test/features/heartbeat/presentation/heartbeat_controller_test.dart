import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_failure.dart';
import 'package:nini_hub/features/heartbeat/presentation/controllers/heartbeat_controller.dart';
import 'package:nini_hub/features/heartbeat/presentation/state/heartbeat_state.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  test(
    'allows different profiles concurrently and rejects the same duplicate',
    () async {
      final firstGate = Completer<HeartbeatRunResult>();
      final secondGate = Completer<HeartbeatRunResult>();
      fixture.runner.gates['first'] = firstGate;
      fixture.runner.gates['second'] = secondGate;

      final first = fixture.controller.run(
        profileId: 'first',
        expectedWindowMinutes: 10080,
      );
      final duplicate = fixture.controller.run(profileId: 'first');
      final second = fixture.controller.run(profileId: 'second');

      expect(await duplicate, isFalse);
      expect(fixture.state.runningProfileIds, {'first', 'second'});
      expect(fixture.runner.calls, [
        const _RunCall('first', 10080),
        const _RunCall('second', null),
      ]);
      expect(
        () => fixture.state.runningProfileIds.add('forbidden'),
        throwsUnsupportedError,
      );

      secondGate.complete(
        const HeartbeatRunResult(
          outcome: HeartbeatOutcome.unverified,
          message: 'Verificación pendiente.',
        ),
      );
      expect(await second, isTrue);
      expect(fixture.state.runningProfileIds, {'first'});
      firstGate.complete(
        HeartbeatRunResult(
          outcome: HeartbeatOutcome.verified,
          message: 'Confirmado.',
          verifiedResetAt: DateTime.utc(2026, 8, 30),
        ),
      );
      expect(await first, isTrue);

      expect(fixture.state.runningProfileIds, isEmpty);
      expect(
        fixture.state.resultForProfile('first')?.outcome,
        HeartbeatOutcome.verified,
      );
      expect(
        fixture.state.resultForProfile('second')?.outcome,
        HeartbeatOutcome.unverified,
      );
      expect(fixture.state.failuresByProfile, isEmpty);
      expect(
        () => fixture.state.resultsByProfile.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'failed and skipped results remain visible as profile failures',
    () async {
      const failed = HeartbeatRunResult(
        outcome: HeartbeatOutcome.failed,
        message: 'Codex no respondió.',
      );
      const skipped = HeartbeatRunResult(
        outcome: HeartbeatOutcome.skipped,
        message: 'El heartbeat está desactivado.',
      );
      fixture.runner.results['failed'] = failed;
      fixture.runner.results['skipped'] = skipped;

      expect(await fixture.controller.run(profileId: 'failed'), isFalse);
      expect(await fixture.controller.run(profileId: 'skipped'), isFalse);

      expect(fixture.state.resultForProfile('failed'), same(failed));
      expect(fixture.state.failureForProfile('failed')?.cause, same(failed));
      expect(
        fixture.state.failureForProfile('failed')?.message,
        'Codex no respondió.',
      );
      expect(fixture.state.resultForProfile('skipped'), same(skipped));
      expect(
        fixture.state.failureForProfile('skipped')?.message,
        'El heartbeat está desactivado.',
      );

      fixture.controller.clearFailure('failed');
      expect(fixture.state.failureForProfile('failed'), isNull);
      expect(fixture.state.failureForProfile('skipped'), isNotNull);
      expect(fixture.state.resultForProfile('failed'), same(failed));
    },
  );

  test('translates typed failures and retains each original cause', () async {
    const missing = HeartbeatProfileNotFoundFailure('missing');
    const unsupported = HeartbeatUnsupportedProviderFailure(
      profileId: 'claude',
      toolKey: 'claude',
    );
    const unavailable = HeartbeatProfileUnavailableFailure(
      profileId: 'offline',
      reason: HeartbeatProfileUnavailableReason.unavailable,
    );
    const applied = HeartbeatAppliedFailure(
      profileId: 'applied',
      progress: HeartbeatAppliedProgress.verificationPersisted,
      cause: 'activity failed',
    );
    final unexpected = StateError('unexpected');
    fixture.runner.errors.addAll({
      'missing': missing,
      'claude': unsupported,
      'offline': unavailable,
      'applied': applied,
      'unexpected': unexpected,
    });

    for (final profileId in fixture.runner.errors.keys.toList()) {
      expect(await fixture.controller.run(profileId: profileId), isFalse);
    }

    expect(
      fixture.state.failureForProfile('missing')?.message,
      'El perfil ya no está disponible en este equipo.',
    );
    expect(
      fixture.state.failureForProfile('claude')?.message,
      'El heartbeat sólo está disponible para Codex.',
    );
    expect(
      fixture.state.failureForProfile('offline')?.message,
      'La cuenta debe estar disponible y vinculada.',
    );
    expect(
      fixture.state.failureForProfile('applied')?.message,
      'El heartbeat se aplicó, pero no se pudo registrar la actividad.',
    );
    expect(
      fixture.state.failureForProfile('unexpected')?.message,
      'No se pudo completar el heartbeat.',
    );
    expect(fixture.state.failureForProfile('missing')?.cause, same(missing));
    expect(fixture.state.failureForProfile('applied')?.cause, same(applied));
    expect(
      fixture.state.failureForProfile('unexpected')?.cause,
      same(unexpected),
    );
  });

  test('retry clears only its profile failure while awaiting', () async {
    fixture.runner.errors['first'] = StateError('first failure');
    fixture.runner.errors['second'] = StateError('second failure');
    expect(await fixture.controller.run(profileId: 'first'), isFalse);
    expect(await fixture.controller.run(profileId: 'second'), isFalse);
    fixture.runner.errors.remove('first');
    final retryGate = Completer<HeartbeatRunResult>();
    fixture.runner.gates['first'] = retryGate;

    final retry = fixture.controller.run(profileId: 'first');

    expect(fixture.state.failureForProfile('first'), isNull);
    expect(fixture.state.failureForProfile('second'), isNotNull);
    retryGate.complete(
      const HeartbeatRunResult(
        outcome: HeartbeatOutcome.verified,
        message: 'Confirmado.',
      ),
    );
    expect(await retry, isTrue);
    expect(fixture.state.failureForProfile('second'), isNotNull);
  });

  test('ignores a late result after provider disposal', () async {
    final gate = Completer<HeartbeatRunResult>();
    fixture.runner.gates['late'] = gate;

    final run = fixture.controller.run(profileId: 'late');
    fixture.dispose();
    gate.complete(
      const HeartbeatRunResult(
        outcome: HeartbeatOutcome.verified,
        message: 'Tarde.',
      ),
    );

    expect(await run, isFalse);
  });
}

final class _Fixture {
  _Fixture() {
    provider =
        NotifierProvider<HeartbeatController, HeartbeatPresentationState>(
          () => HeartbeatController.composed(
            (_) => HeartbeatControllerDependencies(runHeartbeat: runner.call),
          ),
        );
    container = ProviderContainer();
    controller = container.read(provider.notifier);
  }

  final _Runner runner = _Runner();
  late final NotifierProvider<HeartbeatController, HeartbeatPresentationState>
  provider;
  late final ProviderContainer container;
  late final HeartbeatController controller;
  bool _disposed = false;

  HeartbeatPresentationState get state => container.read(provider);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }
}

final class _Runner {
  final List<_RunCall> calls = [];
  final Map<String, Completer<HeartbeatRunResult>> gates = {};
  final Map<String, HeartbeatRunResult> results = {};
  final Map<String, Object> errors = {};

  Future<HeartbeatRunResult> call({
    required String profileId,
    int? expectedWindowMinutes,
  }) async {
    calls.add(_RunCall(profileId, expectedWindowMinutes));
    final gate = gates.remove(profileId);
    if (gate != null) return gate.future;
    final error = errors[profileId];
    if (error != null) throw error;
    return results[profileId] ??
        const HeartbeatRunResult(
          outcome: HeartbeatOutcome.verified,
          message: 'Confirmado.',
        );
  }
}

final class _RunCall {
  const _RunCall(this.profileId, this.expectedWindowMinutes);

  final String profileId;
  final int? expectedWindowMinutes;

  @override
  bool operator ==(Object other) =>
      other is _RunCall &&
      profileId == other.profileId &&
      expectedWindowMinutes == other.expectedWindowMinutes;

  @override
  int get hashCode => Object.hash(profileId, expectedWindowMinutes);
}
