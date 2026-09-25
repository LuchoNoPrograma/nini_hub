import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

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
      expect(observation.windowType, 'a');
      expect(observation.observedAt.isUtc, isTrue);
      expect(observation.resetsAt?.isUtc, isTrue);
    });

    test('affected fixture selects the 5 hour cycle before weekly', () {
      final snapshot = _snapshot(
        now,
        windows: [
          _window(
            limitId: 'codex_bengalfox',
            windowType: 'secondary',
            durationMinutes: HeartbeatPolicy.weeklyMinutes,
            resetAt: now.add(const Duration(days: 7)),
          ),
          _window(
            limitId: 'codex_bengalfox',
            windowType: 'primary',
            durationMinutes: HeartbeatPolicy.primaryMinutes,
            resetAt: now.add(const Duration(hours: 5)),
          ),
        ],
      );

      final observation = policy.observationFrom(snapshot);

      expect(observation?.limitId, 'codex_bengalfox');
      expect(observation?.windowType, 'primary');
      expect(
        observation?.windowDurationMinutes,
        HeartbeatPolicy.primaryMinutes,
      );
    });

    test('supports weekly-only and monthly-only account fixtures', () {
      const monthlyMinutes = 30 * 24 * 60;
      final weekly = policy.observationFrom(
        _snapshot(
          now,
          windows: [
            _window(
              limitId: 'codex_weekly_only',
              durationMinutes: HeartbeatPolicy.weeklyMinutes,
            ),
          ],
        ),
      );
      final monthly = policy.observationFrom(
        _snapshot(
          now,
          windows: [
            _window(
              limitId: 'codex_monthly_only',
              durationMinutes: monthlyMinutes,
            ),
          ],
        ),
      );

      expect(weekly?.windowDurationMinutes, HeartbeatPolicy.weeklyMinutes);
      expect(monthly?.windowDurationMinutes, monthlyMinutes);
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

    test('affected 5 hour fixture invalidates stale weekly verification', () {
      final oldWeeklyReset = now.add(const Duration(days: 7));
      final oldWeekly = _observation(
        now.subtract(const Duration(minutes: 2)),
        resetAt: oldWeeklyReset,
      );
      final previousAt = now.subtract(const Duration(seconds: 30));
      final previousPrimary = _observation(
        previousAt,
        limitId: 'codex_bengalfox',
        windowType: 'primary',
        durationMinutes: HeartbeatPolicy.primaryMinutes,
        resetAt: previousAt.add(const Duration(hours: 5)),
      );
      final currentPrimary = _observation(
        now,
        limitId: 'codex_bengalfox',
        windowType: 'primary',
        durationMinutes: HeartbeatPolicy.primaryMinutes,
        resetAt: now.add(const Duration(hours: 5)),
      );

      final decision = policy.decide(
        state: HeartbeatState(
          observation: oldWeekly,
          status: HeartbeatStatus.verified,
          verifiedResetAt: oldWeeklyReset,
          verifiedIdentity: oldWeekly.identity,
        ),
        current: currentPrimary,
        previous: previousPrimary,
        now: now,
      );

      expect(decision, isA<ExecuteHeartbeatDecision>());
      expect(decision.state.verifiedResetAt, isNull);
      expect(
        (decision as ExecuteHeartbeatDecision).expectedWindowMinutes,
        HeartbeatPolicy.primaryMinutes,
      );
    });

    test('healthy stable 5 hour anchor does not execute a heartbeat', () {
      final reset = now.add(const Duration(hours: 5));
      final previous = _observation(
        now.subtract(const Duration(minutes: 2)),
        limitId: 'codex_healthy',
        windowType: 'primary',
        durationMinutes: HeartbeatPolicy.primaryMinutes,
        resetAt: reset,
      );
      final current = _observation(
        now,
        limitId: 'codex_healthy',
        windowType: 'primary',
        durationMinutes: HeartbeatPolicy.primaryMinutes,
        resetAt: reset,
      );

      final decision = policy.decide(
        state: HeartbeatState(observation: previous),
        current: current,
        previous: previous,
        now: now,
      );

      expect(decision, isA<SkipHeartbeatDecision>());
      expect(decision.state.status, HeartbeatStatus.observing);
    });

    test('does not spend a heartbeat when the matching long limit is full', () {
      final target = _observation(
        now,
        limitId: 'codex_guarded',
        windowType: 'primary',
        durationMinutes: HeartbeatPolicy.primaryMinutes,
        resetAt: now.add(const Duration(hours: 5)),
      );
      final snapshot = _snapshot(
        now,
        windows: [
          _window(
            limitId: 'codex_guarded',
            windowType: 'primary',
            durationMinutes: HeartbeatPolicy.primaryMinutes,
          ),
          _window(
            limitId: 'codex_guarded',
            windowType: 'secondary',
            durationMinutes: HeartbeatPolicy.weeklyMinutes,
            usedPercent: 100,
            resetAt: now.add(const Duration(days: 2)),
          ),
        ],
      );

      final decision = policy.decide(
        state: HeartbeatState(),
        current: target,
        previous: null,
        quotaGuard: policy.longQuotaGuardFrom(snapshot, target: target),
        now: now,
      );

      expect(decision, isA<SkipHeartbeatDecision>());
      expect(
        (decision as SkipHeartbeatDecision).nextProbeAt,
        now.add(const Duration(days: 2, minutes: 1)),
      );
    });

    test(
      'missing weekly reset waits an hour even when the short cycle has use',
      () {
        final decision =
            policy.decide(
                  state: HeartbeatState(),
                  current: _observation(
                    now,
                    usedPercent: 20,
                    durationMinutes: HeartbeatPolicy.primaryMinutes,
                    resetAt: now.add(const Duration(minutes: 5)),
                  ),
                  previous: null,
                  quotaGuard: const HeartbeatQuotaGuard(exhausted: true),
                  now: now,
                )
                as SkipHeartbeatDecision;
        expect(decision.nextProbeAt, now.add(const Duration(hours: 1)));
      },
    );

    for (final weeklyUsed in [16.0, 32.0, 61.0, 100.0, null]) {
      test('group reached flag respects known weekly use: $weeklyUsed', () {
        final snapshot = _snapshot(
          now,
          windows: [
            _window(
              windowType: 'primary',
              durationMinutes: 300,
              resetAt: now.subtract(const Duration(minutes: 2)),
            ),
            _window(
              windowType: 'secondary',
              durationMinutes: 10080,
              usedPercent: weeklyUsed,
              reachedType: 'rate_limit_reached',
              resetAt: now.add(const Duration(days: 5)),
            ),
          ],
        );
        final target = policy.observationFrom(snapshot)!;
        final guard = policy.longQuotaGuardFrom(snapshot, target: target);
        final shouldBlock = weeklyUsed == null || weeklyUsed == 100;
        expect(guard.exhausted, shouldBlock);
        final decision = policy.decide(
          state: HeartbeatState(),
          current: target,
          previous: null,
          quotaGuard: guard,
          now: now,
        );
        expect(
          decision,
          shouldBlock
              ? isA<SkipHeartbeatDecision>()
              : isA<ExecuteHeartbeatDecision>(),
        );
      });
    }

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
  double usedPercent = 0,
  String email = 'account@example.com',
  String limitId = 'codex',
  String windowType = 'rolling',
  int durationMinutes = HeartbeatPolicy.weeklyMinutes,
  DateTime? resetAt,
}) => HeartbeatObservation(
  limitId: limitId,
  windowType: windowType,
  usedPercent: usedPercent,
  windowDurationMinutes: durationMinutes,
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
  int durationMinutes = HeartbeatPolicy.weeklyMinutes,
  double? usedPercent = 0,
  String? reachedType,
  DateTime? resetAt,
}) => UsageQuotaWindow(
  limitId: limitId,
  windowType: windowType,
  usedPercent: usedPercent,
  windowDurationMinutes: durationMinutes,
  resetsAt: resetAt,
  reachedType: reachedType,
);
