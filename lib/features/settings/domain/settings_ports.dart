import 'package:multi_cli_ai/features/settings/domain/app_preferences.dart';

abstract interface class SettingsRepository {
  Future<AppPreferences> load();

  Future<void> save(AppPreferences preferences);
}

abstract interface class SettingsRuntime {
  void setRequestTimeoutSeconds(int seconds);

  void setWeeklyKeepAliveEnabled(bool enabled);

  Future<void> refreshProfiles();

  void syncWeeklyScheduler();
}
