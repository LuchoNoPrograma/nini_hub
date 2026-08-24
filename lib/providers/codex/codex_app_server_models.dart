enum UsageCheckState {
  success,
  partial,
  unavailable,
  timeout,
  authRequired,
  toolMissing,
  profileMissing,
  error;

  String get storageValue => switch (this) {
    authRequired => 'auth_required',
    toolMissing => 'tool_missing',
    profileMissing => 'profile_missing',
    _ => name,
  };

  static UsageCheckState fromStorage(String value) => switch (value) {
    'success' => success,
    'partial' => partial,
    'unavailable' => unavailable,
    'timeout' => timeout,
    'auth_required' => authRequired,
    'tool_missing' => toolMissing,
    'profile_missing' => profileMissing,
    _ => error,
  };
}

class QuotaSnapshot {
  const QuotaSnapshot({
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

  double? get remainingPercent =>
      usedPercent == null ? null : (100 - usedPercent!).clamp(0, 100);
}

class DailyUsageSnapshot {
  const DailyUsageSnapshot({
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

class CodexRefreshResult {
  const CodexRefreshResult({
    required this.state,
    required this.startedAt,
    required this.completedAt,
    this.planType,
    this.accountEmail,
    this.accountDisplayName,
    this.errorCode,
    this.errorMessage,
    this.rateLimitsReadSucceeded = false,
    this.windows = const [],
    this.dailyUsage = const [],
    this.resetCredits = 0,
    this.nextCreditExpiry,
  });

  final UsageCheckState state;
  final DateTime startedAt;
  final DateTime completedAt;
  final String? planType;
  final String? accountEmail;
  final String? accountDisplayName;
  final String? errorCode;
  final String? errorMessage;
  final bool rateLimitsReadSucceeded;
  final List<QuotaSnapshot> windows;
  final List<DailyUsageSnapshot> dailyUsage;
  final int resetCredits;
  final DateTime? nextCreditExpiry;

  int get durationMs => completedAt.difference(startedAt).inMilliseconds;
}
