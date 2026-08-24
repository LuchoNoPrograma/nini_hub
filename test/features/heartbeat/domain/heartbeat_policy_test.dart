import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';

void main() {
  const policy = HeartbeatPolicy();
  final now = DateTime.utc(2026, 8, 22, 12);

  group('HeartbeatPolicy', () {
    test('selects the Codex weekly window and normalizes dates to UTC', () {
      final snapshot = _snapshot(
        now,
        windows: [
          _window(
            limitId: 'secondary',
            windowType: 'b',
            resetAt: now.add(const Duration(days: 7)),
          ),
          _window(
            limitId: 'codex',
            windowType: 'a',
            resetAt: now.add(const Duration(days: 7)),
          ),
        ],
      );

      final observation = policy.observationFrom(snapshot);

      expect(observation, isNotNull);
      expect(observation!.limitId, 'codex');
      expect(observation.observedAt.isUtc, isTrue);
      expect(observation.resetsAt?.isUtc, isTrue);
    });

    test('keeps a verified reset only for the same account identity', () {
      final verifiedReset = now.add(const Duration(days: 7));
      final previous = _observation(
        now.subtract(const Duration(minutes: 1)),
        email: 'first@example.com',
        resetAt: verifiedReset,
      );
      final state = HeartbeatState(
        observation: previous,
        status: HeartbeatStatus.verified,
        verifiedResetAt: verifiedReset,
        verifiedIdentity: previous.identity,
      );
      final sameIdentity = _observation(
        now,
        email: ' FIRST@example.com ',
        resetAt: verifiedReset,
      );

      final sameDecision = policy.decide(
        state: state,
        current: sameIdentity,
        previous: previous,
        now: now,
      );

      expect(sameDecision, isA<SkipHeartbeatDecision>());
      expect(sameDecision.state.status, HeartbeatStatus.verified);
      expect(sameDecision.state.verifiedResetAt, verifiedReset);

      final changedIdentity = _observation(
        now,
        email: 'second@example.com',
        resetAt: now.add(const Duration(days: 8)),
      );
      final changedDecision = policy.decide(
        state: state,
        current: changedIdentity,
        previous: null,
        now: now,
      );

      expect(changedDecision.state.status, HeartbeatStatus.observing);
      expect(changedDecision.state.verifiedResetAt, isNull);
      expect(changedDecision.state.verifiedIdentity, isNull);
    });

    test('executes when a projected reset floats with observations', () {
      final previousAt = now.subtract(const Duration(seconds: 30));
      final previous = _observation(
        previousAt,
        resetAt: previousAt.add(const Duration(days: 7)),
      );
      final current = _observation(
        now,
        resetAt: now.add(const Duration(days: 7)),
      );

      final decision = policy.decide(
        state: HeartbeatState(observation: previous),
        current: current,
        previous: previous,
        now: now,
      );

      expect(decision, isA<ExecuteHeartbeatDecision>());
      expect(decision.state.status, HeartbeatStatus.candidate);
    });

    test('verifies a future reset anchor that remains stable', () {
      final reset = now.add(const Duration(days: 7));

      final verification = policy.verify(
        first: _snapshot(
          now.add(const Duration(seconds: 10)),
          windows: [_window(resetAt: reset)],
        ),
        second: _snapshot(
          now.add(const Duration(seconds: 20)),
          windows: [_window(resetAt: reset)],
        ),
        expectedWindowMinutes: HeartbeatPolicy.weeklyMinutes,
        now: now,
      );

      expect(verification.verified, isTrue);
      expect(verification.observation?.resetsAt, reset);
    });

    test('preserves the persisted retry sequence', () {
      expect(policy.retryDelay(1), const Duration(minutes: 15));
      expect(policy.retryDelay(2), const Duration(hours: 1));
      expect(policy.retryDelay(3), const Duration(hours: 6));
      expect(policy.retryDelay(20), const Duration(hours: 6));
    });
  });
}

HeartbeatObservation _observation(
  DateTime observedAt, {
  String email = 'account@example.com',
  DateTime? resetAt,
}) => HeartbeatObservation(
  limitId: 'codex',
  usedPercent: 0,
  windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
  resetsAt: resetAt,
  observedAt: observedAt,
  accountEmail: email,
  planType: 'pro',
);

UsageSnapshot _snapshot(
  DateTime completedAt, {
  List<UsageQuotaWindow>? windows,
}) => UsageSnapshot(
  status: UsageRefreshStatus.success,
  startedAt: completedAt.subtract(const Duration(seconds: 1)),
  completedAt: completedAt,
  accountEmail: 'account@example.com',
  planType: 'pro',
  windows: windows ?? [_window()],
);

UsageQuotaWindow _window({
  String limitId = 'codex',
  String windowType = 'rolling',
  DateTime? resetAt,
}) => UsageQuotaWindow(
  limitId: limitId,
  windowType: windowType,
  usedPercent: 0,
  windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
  resetsAt: resetAt,
);
