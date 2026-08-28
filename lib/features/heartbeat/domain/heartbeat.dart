import 'package:nini_hub/features/usage/domain/usage.dart';

enum HeartbeatStatus {
  unknown,
  observing,
  candidate,
  running,
  verified,
  active,
  unsupported,
  unverified,
  failed,
  probeFailed,
}

enum HeartbeatOutcome { verified, unverified, skipped, failed }

enum HeartbeatActivityKind { verified, unverified, probeFailure }

final class HeartbeatIdentity {
  factory HeartbeatIdentity({String? accountEmail, String? planType}) =>
      HeartbeatIdentity._(
        accountEmail: _normalize(accountEmail),
        planType: _normalize(planType),
      );

  const HeartbeatIdentity._({
    required this.accountEmail,
    required this.planType,
  });

  final String accountEmail;
  final String planType;

  bool isCompatibleWith(HeartbeatIdentity other) {
    if (accountEmail.isNotEmpty &&
        other.accountEmail.isNotEmpty &&
        accountEmail != other.accountEmail) {
      return false;
    }
    return planType.isEmpty ||
        other.planType.isEmpty ||
        planType == other.planType;
  }

  bool isSameAs(HeartbeatIdentity other) =>
      accountEmail == other.accountEmail && planType == other.planType;

  static String _normalize(String? value) => value?.trim().toLowerCase() ?? '';
}

final class HeartbeatObservation {
  HeartbeatObservation({
    required this.limitId,
    this.windowType = '',
    required this.usedPercent,
    required this.windowDurationMinutes,
    required DateTime? resetsAt,
    required DateTime observedAt,
    this.accountEmail,
    this.planType,
  }) : resetsAt = resetsAt?.toUtc(),
       observedAt = observedAt.toUtc();

  final String limitId;
  final String windowType;
  final double? usedPercent;
  final int windowDurationMinutes;
  final DateTime? resetsAt;
  final DateTime observedAt;
  final String? accountEmail;
  final String? planType;

  HeartbeatIdentity get identity =>
      HeartbeatIdentity(accountEmail: accountEmail, planType: planType);

  bool isSameWindowAs(HeartbeatObservation other) =>
      limitId.trim().toLowerCase() == other.limitId.trim().toLowerCase() &&
      windowType.trim().toLowerCase() ==
          other.windowType.trim().toLowerCase() &&
      (windowDurationMinutes - other.windowDurationMinutes).abs() <= 60;
}

final class HeartbeatState {
  HeartbeatState({
    this.observation,
    this.status = HeartbeatStatus.unknown,
    this.message = '',
    DateTime? lastAttemptAt,
    DateTime? lastSuccessAt,
    DateTime? verifiedResetAt,
    this.verifiedIdentity,
    DateTime? retryAfter,
    this.retryCount = 0,
  }) : lastAttemptAt = lastAttemptAt?.toUtc(),
       lastSuccessAt = lastSuccessAt?.toUtc(),
       verifiedResetAt = verifiedResetAt?.toUtc(),
       retryAfter = retryAfter?.toUtc();

  final HeartbeatObservation? observation;
  final HeartbeatStatus status;
  final String message;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final DateTime? verifiedResetAt;
  final HeartbeatIdentity? verifiedIdentity;
  final DateTime? retryAfter;
  final int retryCount;

  HeartbeatIdentity? get effectiveVerifiedIdentity =>
      verifiedIdentity ??
      (verifiedResetAt == null ? null : observation?.identity);
}

final class HeartbeatRunResult {
  const HeartbeatRunResult({
    required this.outcome,
    required this.message,
    this.verifiedResetAt,
    this.latestUsageSnapshot,
  });

  final HeartbeatOutcome outcome;
  final String message;
  final DateTime? verifiedResetAt;
  final UsageSnapshot? latestUsageSnapshot;

  bool get commandSucceeded =>
      outcome == HeartbeatOutcome.verified ||
      outcome == HeartbeatOutcome.unverified;

  HeartbeatRunResult withLatestUsageSnapshot(UsageSnapshot snapshot) =>
      HeartbeatRunResult(
        outcome: outcome,
        message: message,
        verifiedResetAt: verifiedResetAt,
        latestUsageSnapshot: snapshot,
      );
}

final class HeartbeatCommandResult {
  const HeartbeatCommandResult.success()
    : succeeded = true,
      failureMessage = '';

  const HeartbeatCommandResult.failure(this.failureMessage) : succeeded = false;

  final bool succeeded;
  final String failureMessage;
}
