import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/features/usage/application/usage_calendar.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_ports.dart';

void main() {
  test('load delegates once and returns the repository calendar', () async {
    final day = UsageCalendarDay(
      day: DateTime(2026, 8, 22),
      tokens: 42,
      successfulChecks: 1,
      failedChecks: 0,
      lowestRemaining: 80,
      resetCount: 0,
      renewalCount: 0,
    );
    final calendar = UsageCalendar([day]);
    final repository = _FakeCalendarRepository(calendar: calendar);

    final loaded = await LoadUsageCalendar(repository: repository)();

    expect(loaded, same(calendar));
    expect(repository.calls, 1);
  });

  test('load preserves the repository error', () async {
    final cause = StateError('calendar failed');
    final repository = _FakeCalendarRepository(error: cause);

    await expectLater(
      LoadUsageCalendar(repository: repository)(),
      throwsA(same(cause)),
    );
    expect(repository.calls, 1);
  });
}

final class _FakeCalendarRepository implements UsageCalendarRepository {
  _FakeCalendarRepository({this.calendar, this.error});

  final UsageCalendar? calendar;
  final Object? error;
  int calls = 0;

  @override
  Future<UsageCalendar> loadCalendar() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return calendar ?? UsageCalendar(const []);
  }
}
