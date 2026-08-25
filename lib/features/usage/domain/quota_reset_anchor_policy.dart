enum QuotaResetAnchorConfidence { confirmed, estimated, unavailable }

final class QuotaResetAnchorObservation {
  QuotaResetAnchorObservation({
    required DateTime observedAt,
    required this.usedPercent,
    required this.windowDurationMinutes,
    required DateTime? resetsAt,
  }) : observedAt = observedAt.toUtc(),
       resetsAt = resetsAt?.toUtc();

  final DateTime observedAt;
  final double? usedPercent;
  final int? windowDurationMinutes;
  final DateTime? resetsAt;
}

abstract final class QuotaResetAnchorPolicy {
  static const activeUsageThreshold = 0.0;
  static const projectionTolerance = Duration(minutes: 3);
  static const stableAnchorTolerance = Duration(seconds: 2);
  static const minimumDriftSample = Duration(seconds: 20);

  static QuotaResetAnchorConfidence classify({
    required QuotaResetAnchorObservation current,
    QuotaResetAnchorObservation? previous,
    bool observationsAreCompatible = true,
  }) {
    if (current.resetsAt == null) {
      return QuotaResetAnchorConfidence.unavailable;
    }
    if (previous != null && observationsAreCompatible) {
      if (isFloatingProjection(previous: previous, current: current)) {
        return QuotaResetAnchorConfidence.estimated;
      }
    }
    final used = current.usedPercent;
    if (used != null && used > activeUsageThreshold) {
      return QuotaResetAnchorConfidence.confirmed;
    }
    if (previous != null && observationsAreCompatible) {
      if (isStable(previous: previous, current: current)) {
        return QuotaResetAnchorConfidence.confirmed;
      }
    }
    return QuotaResetAnchorConfidence.estimated;
  }

  static bool isFloatingProjection({
    required QuotaResetAnchorObservation? previous,
    required QuotaResetAnchorObservation current,
  }) {
    if (previous == null) return false;
    final previousReset = previous.resetsAt;
    final currentReset = current.resetsAt;
    if (previousReset == null || currentReset == null) return false;
    if (!looksProjected(previous) || !looksProjected(current)) return false;
    final observedMovement = current.observedAt.difference(previous.observedAt);
    if (observedMovement < minimumDriftSample) return false;
    final anchorMovement = currentReset.difference(previousReset);
    if (anchorMovement < minimumDriftSample) return false;
    return (anchorMovement - observedMovement).abs() <= projectionTolerance;
  }

  static bool isStable({
    required QuotaResetAnchorObservation previous,
    required QuotaResetAnchorObservation current,
  }) {
    final previousReset = previous.resetsAt;
    final currentReset = current.resetsAt;
    if (previousReset == null || currentReset == null) return false;
    return currentReset.difference(previousReset).abs() <=
        stableAnchorTolerance;
  }

  static bool looksProjected(QuotaResetAnchorObservation observation) {
    final reset = observation.resetsAt;
    final duration = observation.windowDurationMinutes;
    if (reset == null || duration == null || duration <= 0) return false;
    final expected = observation.observedAt.add(Duration(minutes: duration));
    return reset.difference(expected).abs() <= projectionTolerance;
  }
}
