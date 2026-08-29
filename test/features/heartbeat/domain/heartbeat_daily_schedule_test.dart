import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';

void main() {
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
