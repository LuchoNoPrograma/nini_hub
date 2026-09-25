import 'package:nini_hub/features/usage/domain/usage.dart';

abstract final class UsageResetRefreshPolicy {
  static const resetMargin = Duration(minutes: 1);
  static const unknownResetDelay = Duration(hours: 1);

  static bool pauses(UsageRefreshStatus status) => switch (status) {
    UsageRefreshStatus.authRequired ||
    UsageRefreshStatus.profileMissing ||
    UsageRefreshStatus.toolMissing ||
    UsageRefreshStatus.unavailable => true,
    _ => false,
  };

  static Duration retryDelay(int failures) => switch (failures) {
    <= 1 => const Duration(minutes: 5),
    2 => const Duration(minutes: 15),
    _ => const Duration(hours: 1),
  };

  static Duration networkRetryDelay(int failures) => switch (failures) {
    <= 1 => const Duration(seconds: 30),
    2 => const Duration(minutes: 2),
    3 => const Duration(minutes: 5),
    _ => const Duration(minutes: 15),
  };

  static DateTime? nextAt(
    Iterable<UsageQuotaWindow> windows, {
    required DateTime observedAt,
  }) {
    final all = windows.toList();
    DateTime? earliest;
    for (final window in all) {
      // A long exhausted quota blocks only shorter windows of the same limit.
      final blocked = all.any(
        (other) =>
            _sameLimit(window, other) &&
            _longExhausted(other) &&
            (other.windowDurationMinutes ?? 0) >
                (window.windowDurationMinutes ?? 0),
      );
      if (blocked) continue;
      final deadline =
          window.resetsAt?.toUtc().add(resetMargin) ??
          (_longExhausted(window)
              ? observedAt.toUtc().add(unknownResetDelay)
              : null);
      if (deadline != null &&
          (earliest == null || deadline.isBefore(earliest))) {
        earliest = deadline;
      }
    }
    return earliest;
  }

  static bool _sameLimit(UsageQuotaWindow a, UsageQuotaWindow b) =>
      a.limitId.trim().toLowerCase() == b.limitId.trim().toLowerCase();

  static bool _longExhausted(UsageQuotaWindow window) =>
      (window.windowDurationMinutes ?? 0) >= 7 * 24 * 60 &&
      // reachedType belongs to the limit group, not to each window. A short
      // exhausted window must not override a known available weekly quota.
      (window.usedPercent != null
          ? window.usedPercent! >= 100
          : (window.reachedType?.trim().isNotEmpty ?? false));
}
