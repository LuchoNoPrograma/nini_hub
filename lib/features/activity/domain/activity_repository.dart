import 'package:nini_hub/features/activity/domain/activity_log.dart';

abstract interface class ActivityRepository {
  Future<List<ActivityLog>> loadRecent({required int limit});

  Future<void> clearAll();
}
