final class HeartbeatDailySchedule {
  const HeartbeatDailySchedule({
    this.hours = const [0, 7, 12, 17],
    this.minutes,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.intervalMinutes,
    this.gracePeriod = const Duration(minutes: 15),
  });

  static const continuous = HeartbeatDailySchedule();

  final List<int> hours;
  final List<int>? minutes;
  final List<int> weekdays;
  final int? intervalMinutes;
  final Duration gracePeriod;

  List<int> get slots {
    final interval = intervalMinutes;
    if (interval != null) {
      if (interval < 15 || interval > 1440) {
        throw ArgumentError('El intervalo debe estar entre 15 y 1440 minutos.');
      }
      return [for (var minute = 0; minute < 1440; minute += interval) minute];
    }
    final values = (minutes ?? hours.map((hour) => hour * 60)).toSet().toList()
      ..sort();
    if (values.isEmpty || values.any((value) => value < 0 || value >= 1440)) {
      throw ArgumentError('Selecciona al menos una hora válida.');
    }
    return values;
  }

  HeartbeatDailySchedule normalized() {
    final days = weekdays.toSet().toList()..sort();
    if (days.isEmpty || days.any((day) => day < 1 || day > 7)) {
      throw ArgumentError('Selecciona al menos un día.');
    }
    return HeartbeatDailySchedule(
      minutes: List.unmodifiable(slots),
      weekdays: List.unmodifiable(days),
      intervalMinutes: intervalMinutes,
      gracePeriod: gracePeriod,
    );
  }

  bool contains(DateTime localTime) {
    if (!weekdays.contains(localTime.weekday)) return false;
    return slots.any((minute) {
      final elapsed = localTime.difference(_slot(localTime, minute));
      return !elapsed.isNegative && elapsed <= gracePeriod;
    });
  }

  DateTime nextSlotAtOrAfter(DateTime localTime) =>
      _next(localTime, allowGrace: true);

  DateTime nextSlotAfter(DateTime localTime) =>
      _next(localTime, allowGrace: false);

  DateTime _next(DateTime localTime, {required bool allowGrace}) {
    final schedule = normalized();
    for (var offset = 0; offset <= 7; offset++) {
      // Calendar arithmetic preserves local wall-clock hours across DST.
      final day = DateTime(
        localTime.year,
        localTime.month,
        localTime.day + offset,
      );
      if (!schedule.weekdays.contains(day.weekday)) continue;
      for (final minute in schedule.slots) {
        final slot = _slot(day, minute);
        if (allowGrace
            ? !localTime.isAfter(slot.add(gracePeriod))
            : slot.isAfter(localTime)) {
          return slot;
        }
      }
    }
    throw StateError('No se encontró el siguiente horario.');
  }

  static DateTime _slot(DateTime day, int minute) =>
      DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);
}
