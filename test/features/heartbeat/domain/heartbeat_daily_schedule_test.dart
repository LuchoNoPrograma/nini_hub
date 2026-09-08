import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';

void main() {
  test('normalizes hours and rolls through excluded days', () {
    final schedule = const HeartbeatDailySchedule(
      minutes: [1050, 450, 450],
      weekdays: [1, 5],
    ).normalized();
    expect(schedule.slots, [450, 1050]);
    expect(schedule.contains(DateTime(2026, 9, 5, 7, 30)), isFalse);
    expect(
      schedule.nextSlotAtOrAfter(DateTime(2026, 9, 4, 18)),
      DateTime(2026, 9, 7, 7, 30),
    );
    expect(
      schedule.nextSlotAfter(DateTime(2026, 9, 7, 7, 30)),
      DateTime(2026, 9, 7, 17, 30),
    );
  });
  test('interval mode uses local midnight and selected days', () {
    const schedule = HeartbeatDailySchedule(intervalMinutes: 90, weekdays: [1]);
    expect(
      schedule.nextSlotAfter(DateTime(2026, 9, 7, 1, 30)),
      DateTime(2026, 9, 7, 3),
    );
    expect(
      schedule.nextSlotAfter(DateTime(2026, 9, 7, 23, 59)),
      DateTime(2026, 9, 14),
    );
  });
  test('rejects empty days, invalid times and unbounded intervals', () {
    expect(
      () => const HeartbeatDailySchedule(weekdays: []).normalized(),
      throwsArgumentError,
    );
    expect(
      () => const HeartbeatDailySchedule(minutes: [1440]).normalized(),
      throwsArgumentError,
    );
    expect(
      () => const HeartbeatDailySchedule(intervalMinutes: 0).normalized(),
      throwsArgumentError,
    );
  });

  const schedule = HeartbeatDailySchedule.continuous;

  test('uses the four requested slots every day', () {
    final day = DateTime(2026, 8, 24);

    expect(schedule.nextSlotAtOrAfter(day), day);
    expect(
      schedule.nextSlotAtOrAfter(DateTime(2026, 8, 24, 6)),
      DateTime(2026, 8, 24, 7),
    );
    expect(
      schedule.nextSlotAtOrAfter(DateTime(2026, 8, 24, 10)),
      DateTime(2026, 8, 24, 12),
    );
    expect(
      schedule.nextSlotAtOrAfter(DateTime(2026, 8, 24, 14)),
      DateTime(2026, 8, 24, 17),
    );
    expect(
      schedule.nextSlotAtOrAfter(DateTime(2026, 8, 24, 22)),
      DateTime(2026, 8, 25),
    );
  });

  test('accepts a short grace period after a planned hour', () {
    expect(schedule.contains(DateTime(2026, 8, 24, 7)), isTrue);
    expect(schedule.contains(DateTime(2026, 8, 24, 7, 15)), isTrue);
    expect(schedule.contains(DateTime(2026, 8, 24, 7, 16)), isFalse);
    expect(
      schedule.nextSlotAtOrAfter(DateTime(2026, 8, 24, 12, 1)),
      DateTime(2026, 8, 24, 12),
    );
  });
}
