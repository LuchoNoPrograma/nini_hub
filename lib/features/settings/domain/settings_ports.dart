import 'package:nini_hub/features/settings/domain/app_preferences.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';

abstract interface class SettingsRepository {
  Future<AppPreferences> load();

  Future<void> save(AppPreferences preferences);
}

abstract interface class SettingsRuntime {
  void setHeartbeatSchedule(HeartbeatDailySchedule schedule);

  void setRequestTimeoutSeconds(int seconds);

  void setWeeklyKeepAliveEnabled(bool enabled);

  Future<void> refreshProfiles();

  void syncWeeklyScheduler();
}
