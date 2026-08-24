enum UsageRefreshStatus {
  success,
  partial,
  unavailable,
  timeout,
  authRequired,
  toolMissing,
  profileMissing,
  error,
}

final class UsageQuotaWindow {
  const UsageQuotaWindow({
    required this.limitId,
    required this.windowType,
    this.limitName,
    this.usedPercent,
    this.windowDurationMinutes,
    this.resetsAt,
    this.reachedType,
    this.planType,
  });

  final String limitId;
  final String windowType;
  final String? limitName;
  final double? usedPercent;
  final int? windowDurationMinutes;
  final DateTime? resetsAt;
  final String? reachedType;
  final String? planType;

  double? get remainingPercent => usedPercent == null
      ? null
      : (100 - usedPercent!).clamp(0, 100).toDouble();
}

final class UsageDailySnapshot {
  const UsageDailySnapshot({
    required this.day,
    required this.tokens,
    required this.source,
    this.activeMinutes,
    this.messageCount,
  });

  final DateTime day;
  final int tokens;
  final int? activeMinutes;
  final int? messageCount;
  final String source;
}

final class UsageSnapshot {
  UsageSnapshot({
    required this.status,
    required this.startedAt,
    required this.completedAt,
    this.planType,
    this.accountEmail,
    this.accountDisplayName,
    this.errorCode,
    this.errorMessage,
    this.rateLimitsReadSucceeded = false,
    Iterable<UsageQuotaWindow> windows = const [],
    Iterable<UsageDailySnapshot> dailyUsage = const [],
    this.resetCredits = 0,
    this.nextCreditExpiry,
  }) : windows = List.unmodifiable(windows),
       dailyUsage = List.unmodifiable(dailyUsage);

  final UsageRefreshStatus status;
  final DateTime startedAt;
  final DateTime completedAt;
  final String? planType;
  final String? accountEmail;
  final String? accountDisplayName;
  final String? errorCode;
  final String? errorMessage;
  final bool rateLimitsReadSucceeded;
  final List<UsageQuotaWindow> windows;
  final List<UsageDailySnapshot> dailyUsage;
  final int resetCredits;
  final DateTime? nextCreditExpiry;

  int get durationMs => completedAt.difference(startedAt).inMilliseconds;
}

final class UsageAccountDay {
  const UsageAccountDay({
    required this.profileId,
    required this.displayName,
    required this.email,
    required this.tokens,
    required this.successfulChecks,
    required this.failedChecks,
    required this.lowestRemaining,
    required this.resetCount,
    required this.renewalCount,
  });

  final String profileId;
  final String displayName;
  final String email;
  final int tokens;
  final int successfulChecks;
  final int failedChecks;
  final double? lowestRemaining;
  final int resetCount;
  final int renewalCount;

  bool get hasActivity =>
      tokens > 0 ||
      successfulChecks > 0 ||
      failedChecks > 0 ||
      resetCount > 0 ||
      renewalCount > 0;
}

final class UsageCalendarDay {
  UsageCalendarDay({
    required this.day,
    required this.tokens,
    required this.successfulChecks,
    required this.failedChecks,
    required this.lowestRemaining,
    required this.resetCount,
    required this.renewalCount,
    Iterable<UsageAccountDay> accounts = const [],
  }) : accounts = List.unmodifiable(accounts);

  final DateTime day;
  final int tokens;
  final int successfulChecks;
  final int failedChecks;
  final double? lowestRemaining;
  final int resetCount;
  final int renewalCount;
  final List<UsageAccountDay> accounts;

  bool get hasActivity =>
      tokens > 0 ||
      successfulChecks > 0 ||
      failedChecks > 0 ||
      resetCount > 0 ||
      renewalCount > 0;
}

final class UsageCalendar {
  UsageCalendar(Iterable<UsageCalendarDay> values)
    : days = Map.unmodifiable({
        for (final value in values) _dateOnly(value.day): value,
      });

  final Map<DateTime, UsageCalendarDay> days;

  UsageCalendarDay? operator [](DateTime day) => days[_dateOnly(day)];

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
