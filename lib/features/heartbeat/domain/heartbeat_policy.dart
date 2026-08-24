import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';

sealed class HeartbeatDecision {
  const HeartbeatDecision(this.state);

  final HeartbeatState state;
}

final class SkipHeartbeatDecision extends HeartbeatDecision {
  const SkipHeartbeatDecision({
    required HeartbeatState state,
    required this.result,
    this.nextProbeAt,
  }) : super(state);

  final HeartbeatRunResult result;
  final DateTime? nextProbeAt;
}

final class ExecuteHeartbeatDecision extends HeartbeatDecision {
  const ExecuteHeartbeatDecision({
    required HeartbeatState state,
    required this.before,
    required this.expectedWindowMinutes,
  }) : super(state);

  final HeartbeatObservation before;
  final int expectedWindowMinutes;
}

final class HeartbeatVerification {
  const HeartbeatVerification({required this.verified, this.observation});

  final bool verified;
  final HeartbeatObservation? observation;
}

final class HeartbeatPolicy {
  const HeartbeatPolicy();

  static const weeklyMinutes = 7 * 24 * 60;
  static const virginUsageThreshold = 1.0;
  static const ambiguousProbeDelay = Duration(seconds: 45);
  static const resetProbeMargin = Duration(seconds: 30);
  static const projectionTolerance = Duration(minutes: 3);
  static const stableAnchorTolerance = Duration(seconds: 2);
  static const minimumDriftSample = Duration(seconds: 20);

  HeartbeatObservation? observationFrom(
    UsageSnapshot snapshot, {
    int expectedWindowMinutes = weeklyMinutes,
  }) {
    final matching = snapshot.windows.where((window) {
      final duration = window.windowDurationMinutes;
      return duration != null && (duration - expectedWindowMinutes).abs() <= 60;
    }).toList();
    if (matching.isEmpty) return null;
    matching.sort((left, right) {
      final leftCore = left.limitId.toLowerCase() == 'codex' ? 0 : 1;
      final rightCore = right.limitId.toLowerCase() == 'codex' ? 0 : 1;
      final byCore = leftCore.compareTo(rightCore);
      return byCore != 0 ? byCore : left.windowType.compareTo(right.windowType);
    });
    final window = matching.first;
    return HeartbeatObservation(
      limitId: window.limitId,
      usedPercent: window.usedPercent,
      windowDurationMinutes:
          window.windowDurationMinutes ?? expectedWindowMinutes,
      resetsAt: window.resetsAt,
      observedAt: snapshot.completedAt,
      accountEmail: snapshot.accountEmail,
      planType: snapshot.planType,
    );
  }

  bool needsHistoricalObservation({
    required HeartbeatState state,
    required HeartbeatObservation current,
  }) {
    final previous = state.observation;
    return previous == null ||
        !previous.observedAt.isBefore(current.observedAt) ||
        !previous.identity.isCompatibleWith(current.identity);
  }

  HeartbeatDecision decide({
    required HeartbeatState state,
    required HeartbeatObservation current,
    required HeartbeatObservation? previous,
    required DateTime now,
  }) {
    final currentTime = now.toUtc();
    final verifiedIdentity = state.effectiveVerifiedIdentity;
    final verifiedReset = state.verifiedResetAt;
    final identityStillVerified =
        verifiedIdentity != null && verifiedIdentity.isSameAs(current.identity);
    if (verifiedReset != null &&
        verifiedReset.isAfter(currentTime) &&
        identityStillVerified) {
      return SkipHeartbeatDecision(
        state: _observedState(
          state,
          current,
          status: HeartbeatStatus.verified,
          message: 'La ventana ya fue verificada.',
          clearRetry: true,
        ),
        result: HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'La ventana semanal ya está activa y verificada.',
          verifiedResetAt: verifiedReset,
        ),
        nextProbeAt: verifiedReset.add(resetProbeMargin),
      );
    }

    final retainedState = identityStillVerified
        ? state
        : HeartbeatState(
            observation: state.observation,
            status: state.status,
            message: state.message,
            lastAttemptAt: state.lastAttemptAt,
            lastSuccessAt: state.lastSuccessAt,
            retryAfter: state.retryAfter,
            retryCount: state.retryCount,
          );
    final used = current.usedPercent;
    final reset = current.resetsAt;
    if (used == null || used > virginUsageThreshold) {
      final nextProbe =
          used != null && reset != null && reset.isAfter(currentTime)
          ? reset.add(resetProbeMargin)
          : null;
      return SkipHeartbeatDecision(
        state: _observedState(
          retainedState,
          current,
          status: HeartbeatStatus.active,
          message: used == null
              ? 'La cuota no informó porcentaje; no se enviará un heartbeat.'
              : 'La ventana semanal ya registra uso.',
          clearRetry: true,
        ),
        result: const HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'La ventana semanal ya registra actividad.',
        ),
        nextProbeAt: nextProbe,
      );
    }

    final retryAfter = retainedState.retryAfter;
    if (retryAfter != null && retryAfter.isAfter(currentTime)) {
      return SkipHeartbeatDecision(
        state: _observedState(
          retainedState,
          current,
          status: retainedState.status,
          message: retainedState.message,
        ),
        result: HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message:
              'El próximo reintento será después de ${retryAfter.toLocal()}.',
        ),
        nextProbeAt: retryAfter,
      );
    }

    final clearlyInactive = reset == null || !reset.isAfter(currentTime);
    final resetTransition = _isResetTransition(previous, current, currentTime);
    final floatingProjection = _isFloatingProjection(previous, current);
    if (!clearlyInactive && !resetTransition && !floatingProjection) {
      final sampleAge = previous == null
          ? Duration.zero
          : current.observedAt.difference(previous.observedAt);
      final nextProbe = previous == null || sampleAge < minimumDriftSample
          ? currentTime.add(ambiguousProbeDelay)
          : reset.add(resetProbeMargin);
      return SkipHeartbeatDecision(
        state: _observedState(
          retainedState,
          current,
          status: HeartbeatStatus.observing,
          message: previous == null
              ? 'Se necesita otra lectura para distinguir una ventana activa '
                    'de una proyección.'
              : 'El ancla semanal parece estable; no se enviará un heartbeat.',
          clearRetry: true,
        ),
        result: const HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'La ventana no requiere un heartbeat en esta lectura.',
        ),
        nextProbeAt: nextProbe,
      );
    }

    final candidate = _observedState(
      retainedState,
      current,
      status: HeartbeatStatus.candidate,
      message: floatingProjection
          ? 'El reinicio se desplaza con cada lectura.'
          : 'Se observó el fin de la ventana anterior.',
    );
    return ExecuteHeartbeatDecision(
      state: candidate,
      before: current,
      expectedWindowMinutes: weeklyMinutes,
    );
  }

  HeartbeatVerification verify({
    required UsageSnapshot first,
    required UsageSnapshot second,
    required int expectedWindowMinutes,
    required DateTime now,
  }) {
    final firstObservation = observationFrom(
      first,
      expectedWindowMinutes: expectedWindowMinutes,
    );
    final secondObservation = observationFrom(
      second,
      expectedWindowMinutes: expectedWindowMinutes,
    );
    if (firstObservation == null || secondObservation == null) {
      return const HeartbeatVerification(verified: false);
    }
    final used = secondObservation.usedPercent;
    if (used != null && used > virginUsageThreshold) {
      return HeartbeatVerification(
        verified: true,
        observation: secondObservation,
      );
    }
    final firstReset = firstObservation.resetsAt;
    final secondReset = secondObservation.resetsAt;
    if (firstReset == null ||
        secondReset == null ||
        !secondReset.isAfter(now.toUtc())) {
      return HeartbeatVerification(
        verified: false,
        observation: secondObservation,
      );
    }
    final movement = secondReset.difference(firstReset).abs();
    return HeartbeatVerification(
      verified:
          movement <= stableAnchorTolerance &&
          !_isFloatingProjection(firstObservation, secondObservation),
      observation: secondObservation,
    );
  }

  Duration retryDelay(int retryCount) => switch (retryCount) {
    <= 1 => const Duration(minutes: 15),
    2 => const Duration(hours: 1),
    _ => const Duration(hours: 6),
  };

  static HeartbeatState _observedState(
    HeartbeatState state,
    HeartbeatObservation observation, {
    required HeartbeatStatus status,
    required String message,
    bool clearRetry = false,
  }) => HeartbeatState(
    observation: observation,
    status: status,
    message: message,
    lastAttemptAt: state.lastAttemptAt,
    lastSuccessAt: state.lastSuccessAt,
    verifiedResetAt: state.verifiedResetAt,
    verifiedIdentity: state.verifiedIdentity,
    retryAfter: clearRetry ? null : state.retryAfter,
    retryCount: clearRetry ? 0 : state.retryCount,
  );

  static bool _isResetTransition(
    HeartbeatObservation? previous,
    HeartbeatObservation current,
    DateTime now,
  ) {
    final previousReset = previous?.resetsAt;
    final currentReset = current.resetsAt;
    if (previousReset == null || currentReset == null) return false;
    if (previousReset.isAfter(now.add(const Duration(minutes: 1)))) {
      return false;
    }
    return currentReset.isAfter(now) &&
        currentReset.difference(previousReset).abs() > const Duration(hours: 1);
  }

  static bool _isFloatingProjection(
    HeartbeatObservation? previous,
    HeartbeatObservation current,
  ) {
    if (previous == null ||
        !previous.identity.isCompatibleWith(current.identity)) {
      return false;
    }
    final previousReset = previous.resetsAt;
    final currentReset = current.resetsAt;
    if (previousReset == null || currentReset == null) return false;
    if (!_looksProjected(previous) || !_looksProjected(current)) return false;
    final observedMovement = current.observedAt.difference(previous.observedAt);
    if (observedMovement < minimumDriftSample) return false;
    final anchorMovement = currentReset.difference(previousReset);
    if (anchorMovement < minimumDriftSample) return false;
    return (anchorMovement - observedMovement).abs() <= projectionTolerance;
  }

  static bool _looksProjected(HeartbeatObservation observation) {
    final reset = observation.resetsAt;
    if (reset == null) return false;
    final expected = observation.observedAt.add(
      Duration(minutes: observation.windowDurationMinutes),
    );
    return reset.difference(expected).abs() <= projectionTolerance;
  }
}
