import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/usage/domain/quota_reset_anchor_policy.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

sealed class HeartbeatDecision {
  const HeartbeatDecision(this.state);

  final HeartbeatState state;
}

final class SkipHeartbeatDecision extends HeartbeatDecision {
  const SkipHeartbeatDecision({
    required HeartbeatState state,
    required this.result,
    this.nextProbeAt,
    this.usePlannedTime = false,
  }) : super(state);

  final HeartbeatRunResult result;
  final DateTime? nextProbeAt;
  final bool usePlannedTime;
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

final class HeartbeatQuotaGuard {
  const HeartbeatQuotaGuard({required this.exhausted, this.resetsAt});

  static const clear = HeartbeatQuotaGuard(exhausted: false);

  final bool exhausted;
  final DateTime? resetsAt;
}

final class HeartbeatPolicy {
  const HeartbeatPolicy();

  static const primaryMinutes = 5 * 60;
  static const weeklyMinutes = 7 * 24 * 60;
  static const virginUsageThreshold = 1.0;
  static const ambiguousProbeDelay = Duration(seconds: 45);
  static const resetProbeMargin = Duration(seconds: 30);
  static const minimumDriftSample = QuotaResetAnchorPolicy.minimumDriftSample;

  HeartbeatObservation? observationFrom(
    UsageSnapshot snapshot, {
    int? expectedWindowMinutes,
    String? expectedLimitId,
    String? expectedWindowType,
  }) {
    var matching = snapshot.windows.where((window) {
      final duration = window.windowDurationMinutes;
      return duration != null && duration > 0;
    }).toList();
    if (expectedWindowMinutes != null) {
      matching = matching.where((window) {
        final duration = window.windowDurationMinutes!;
        return (duration - expectedWindowMinutes).abs() <= 60;
      }).toList();
    } else {
      final selectedDuration = _preferredDuration(matching);
      if (selectedDuration == null) return null;
      matching = matching.where((window) {
        return (window.windowDurationMinutes! - selectedDuration).abs() <= 60;
      }).toList();
    }
    final normalizedLimitId = expectedLimitId?.trim().toLowerCase();
    if (normalizedLimitId != null && normalizedLimitId.isNotEmpty) {
      matching = matching
          .where(
            (window) =>
                window.limitId.trim().toLowerCase() == normalizedLimitId,
          )
          .toList();
    }
    final normalizedWindowType = expectedWindowType?.trim().toLowerCase();
    if (normalizedWindowType != null && normalizedWindowType.isNotEmpty) {
      matching = matching
          .where(
            (window) =>
                window.windowType.trim().toLowerCase() == normalizedWindowType,
          )
          .toList();
    }
    if (matching.isEmpty) return null;
    matching.sort((left, right) {
      final leftCore = left.limitId.toLowerCase() == 'codex' ? 0 : 1;
      final rightCore = right.limitId.toLowerCase() == 'codex' ? 0 : 1;
      final byCore = leftCore.compareTo(rightCore);
      if (byCore != 0) return byCore;
      final leftPrimary = left.windowType.toLowerCase() == 'primary' ? 0 : 1;
      final rightPrimary = right.windowType.toLowerCase() == 'primary' ? 0 : 1;
      final byPrimary = leftPrimary.compareTo(rightPrimary);
      return byPrimary != 0
          ? byPrimary
          : left.windowType.compareTo(right.windowType);
    });
    final window = matching.first;
    return HeartbeatObservation(
      limitId: window.limitId,
      windowType: window.windowType,
      usedPercent: window.usedPercent,
      windowDurationMinutes: window.windowDurationMinutes!,
      resetsAt: window.resetsAt,
      observedAt: snapshot.completedAt,
      accountEmail: snapshot.accountEmail,
      planType: snapshot.planType,
    );
  }

  HeartbeatQuotaGuard longQuotaGuardFrom(
    UsageSnapshot snapshot, {
    required HeartbeatObservation target,
  }) {
    DateTime? latestReset;
    var exhausted = false;
    for (final window in snapshot.windows) {
      final duration = window.windowDurationMinutes;
      if (duration == null ||
          duration <= target.windowDurationMinutes + 60 ||
          window.limitId.trim().toLowerCase() !=
              target.limitId.trim().toLowerCase()) {
        continue;
      }
      final reached = window.reachedType?.trim().isNotEmpty ?? false;
      if ((window.usedPercent ?? 0) < 99 && !reached) continue;
      exhausted = true;
      final reset = window.resetsAt?.toUtc();
      if (reset != null &&
          (latestReset == null || reset.isAfter(latestReset))) {
        latestReset = reset;
      }
    }
    return exhausted
        ? HeartbeatQuotaGuard(exhausted: true, resetsAt: latestReset)
        : HeartbeatQuotaGuard.clear;
  }

  bool needsHistoricalObservation({
    required HeartbeatState state,
    required HeartbeatObservation current,
  }) {
    final previous = state.observation;
    return previous == null ||
        !previous.isSameWindowAs(current) ||
        !previous.observedAt.isBefore(current.observedAt) ||
        !previous.identity.isCompatibleWith(current.identity);
  }

  HeartbeatDecision decide({
    required HeartbeatState state,
    required HeartbeatObservation current,
    required HeartbeatObservation? previous,
    HeartbeatQuotaGuard quotaGuard = HeartbeatQuotaGuard.clear,
    required DateTime now,
  }) {
    final currentTime = now.toUtc();
    final verifiedIdentity = state.effectiveVerifiedIdentity;
    final verifiedReset = state.verifiedResetAt;
    final identityStillVerified =
        verifiedIdentity != null && verifiedIdentity.isSameAs(current.identity);
    final observedWindowStillVerified =
        state.observation?.isSameWindowAs(current) ?? false;
    final currentReset = current.resetsAt;
    final anchorStillVerified =
        verifiedReset != null &&
        currentReset != null &&
        verifiedReset.difference(currentReset).abs() <=
            const Duration(minutes: 1);
    if (verifiedReset != null &&
        verifiedReset.isAfter(currentTime) &&
        identityStillVerified &&
        observedWindowStillVerified &&
        anchorStillVerified) {
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
          message: 'El ciclo de Codex ya está activo y verificado.',
          verifiedResetAt: verifiedReset,
        ),
        nextProbeAt: verifiedReset.add(resetProbeMargin),
        usePlannedTime: true,
      );
    }

    final retainedState =
        identityStillVerified &&
            observedWindowStillVerified &&
            anchorStillVerified
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
              : 'El ciclo de Codex ya registra uso.',
          clearRetry: true,
        ),
        result: const HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'El ciclo de Codex ya registra actividad.',
        ),
        nextProbeAt: nextProbe,
        usePlannedTime: nextProbe != null,
      );
    }

    if (quotaGuard.exhausted) {
      final reset = quotaGuard.resetsAt;
      final nextProbe = reset != null && reset.isAfter(currentTime)
          ? reset.add(resetProbeMargin)
          : currentTime.add(ambiguousProbeDelay);
      return SkipHeartbeatDecision(
        state: _observedState(
          retainedState,
          current,
          status: HeartbeatStatus.active,
          message:
              'El límite largo de Codex está agotado; no se enviará un '
              'heartbeat.',
          clearRetry: true,
        ),
        result: const HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'El límite largo está agotado; se esperará a su reinicio.',
        ),
        nextProbeAt: nextProbe,
        usePlannedTime: reset != null && reset.isAfter(currentTime),
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
              : 'El ancla del ciclo parece estable; no se enviará un heartbeat.',
          clearRetry: true,
        ),
        result: const HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'La ventana no requiere un heartbeat en esta lectura.',
        ),
        nextProbeAt: nextProbe,
        usePlannedTime: previous != null && sampleAge >= minimumDriftSample,
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
      expectedWindowMinutes: current.windowDurationMinutes,
    );
  }

  HeartbeatVerification verify({
    required UsageSnapshot first,
    required UsageSnapshot second,
    required int expectedWindowMinutes,
    HeartbeatObservation? expectedTarget,
    required DateTime now,
  }) {
    final firstObservation = observationFrom(
      first,
      expectedWindowMinutes: expectedWindowMinutes,
      expectedLimitId: expectedTarget?.limitId,
      expectedWindowType: expectedTarget?.windowType,
    );
    final secondObservation = observationFrom(
      second,
      expectedWindowMinutes: expectedWindowMinutes,
      expectedLimitId: expectedTarget?.limitId,
      expectedWindowType: expectedTarget?.windowType,
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
    return HeartbeatVerification(
      verified:
          QuotaResetAnchorPolicy.isStable(
            previous: _resetObservation(firstObservation),
            current: _resetObservation(secondObservation),
          ) &&
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
        !previous.isSameWindowAs(current) ||
        !previous.identity.isCompatibleWith(current.identity)) {
      return false;
    }
    return QuotaResetAnchorPolicy.isFloatingProjection(
      previous: _resetObservation(previous),
      current: _resetObservation(current),
    );
  }

  static QuotaResetAnchorObservation _resetObservation(
    HeartbeatObservation observation,
  ) => QuotaResetAnchorObservation(
    observedAt: observation.observedAt,
    usedPercent: observation.usedPercent,
    windowDurationMinutes: observation.windowDurationMinutes,
    resetsAt: observation.resetsAt,
  );

  static int? _preferredDuration(List<UsageQuotaWindow> windows) {
    if (windows.isEmpty) return null;
    for (final preferred in const [primaryMinutes, weeklyMinutes]) {
      for (final window in windows) {
        final duration = window.windowDurationMinutes!;
        if ((duration - preferred).abs() <= 60) return duration;
      }
    }
    windows.sort(
      (left, right) =>
          left.windowDurationMinutes!.compareTo(right.windowDurationMinutes!),
    );
    return windows.first.windowDurationMinutes;
  }
}
