final class HeartbeatDailySchedule {
  const HeartbeatDailySchedule({
    required this.hours,
    this.gracePeriod = const Duration(minutes: 15),
  });

  static const continuous = HeartbeatDailySchedule(hours: [0, 7, 12, 17]);

  final List<int> hours;
  final Duration gracePeriod;

  bool contains(DateTime localTime) {
    for (final hour in hours) {
      final slot = _slot(localTime, hour);
      final elapsed = localTime.difference(slot);
      if (!elapsed.isNegative && elapsed <= gracePeriod) return true;
    }
    return false;
  }

  DateTime nextSlotAtOrAfter(DateTime localTime) {
    for (final hour in hours) {
      final slot = _slot(localTime, hour);
      if (!localTime.isAfter(slot.add(gracePeriod))) return slot;
    }
    final tomorrow = localTime.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hours.first);
  }

  static DateTime _slot(DateTime localTime, int hour) =>
      DateTime(localTime.year, localTime.month, localTime.day, hour);
}
