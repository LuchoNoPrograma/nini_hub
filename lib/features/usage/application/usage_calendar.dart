import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';

final class LoadUsageCalendar {
  const LoadUsageCalendar({required this.repository});

  final UsageCalendarRepository repository;

  Future<UsageCalendar> call() => repository.loadCalendar();
}
