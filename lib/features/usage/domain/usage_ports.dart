import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

abstract interface class UsageProvider {
  Future<UsageSnapshot> refresh(Profile profile);
}

abstract interface class UsageSnapshotRepository {
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  });
}

abstract interface class UsageActivityRecorder {
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  });
}

abstract interface class UsageKeepAliveScheduler {
  bool scheduleIfEligible({
    required Profile profile,
    required UsageSnapshot snapshot,
  });
}

abstract interface class UsageCalendarRepository {
  Future<UsageCalendar> loadCalendar();
}
