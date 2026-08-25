import 'package:nini_hub/features/activity/domain/activity_log.dart';
import 'package:nini_hub/features/activity/domain/activity_repository.dart';

final class ActivityHistorySnapshot {
  ActivityHistorySnapshot({required List<ActivityLog> logs})
    : logs = List.unmodifiable(logs);

  final List<ActivityLog> logs;
}

final class ActivityClearAppliedFailure implements Exception {
  const ActivityClearAppliedFailure(this.cause);

  final Object cause;

  @override
  String toString() =>
      'Activity history was cleared, but reload failed: $cause';
}

final class LoadActivityHistory {
  const LoadActivityHistory({required this.repository});

  static const recentLimit = 250;

  final ActivityRepository repository;

  Future<ActivityHistorySnapshot> call() async {
    final logs = await repository.loadRecent(limit: recentLimit);
    return ActivityHistorySnapshot(logs: logs);
  }
}

final class ClearActivityHistory {
  const ClearActivityHistory({required this.repository});

  final ActivityRepository repository;

  Future<ActivityHistorySnapshot> call() async {
    await repository.clearAll();

    try {
      final logs = await repository.loadRecent(
        limit: LoadActivityHistory.recentLimit,
      );
      return ActivityHistorySnapshot(logs: logs);
    } catch (error) {
      throw ActivityClearAppliedFailure(error);
    }
  }
}
