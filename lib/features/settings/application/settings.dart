import 'package:nini_hub/features/settings/domain/app_preferences.dart';
import 'package:nini_hub/features/settings/domain/settings_ports.dart';

final class LoadSettings {
  const LoadSettings({required this.repository, required this.runtime});

  final SettingsRepository repository;
  final SettingsRuntime runtime;

  Future<AppPreferences> call() async {
    final preferences = await repository.load();
    runtime.setHeartbeatSchedule(preferences.heartbeatSchedule);
    runtime.setWeeklyKeepAliveEnabled(preferences.weeklyKeepAliveEnabled);
    runtime.setRequestTimeoutSeconds(preferences.timeoutSeconds);
    return preferences;
  }
}

sealed class SaveSettingsResult {
  const SaveSettingsResult(this.preferences);

  final AppPreferences preferences;
}

final class SettingsSaved extends SaveSettingsResult {
  const SettingsSaved(super.preferences);
}

final class SettingsPersistedWithFailure extends SaveSettingsResult {
  const SettingsPersistedWithFailure(super.preferences, this.failure);

  final Object failure;
}

final class SaveSettings {
  const SaveSettings({required this.repository, required this.runtime});

  final SettingsRepository repository;
  final SettingsRuntime runtime;

  Future<SaveSettingsResult> call(AppPreferences preferences) async {
    final normalized = preferences.normalizedForSave();
    await repository.save(normalized);
    try {
      runtime.setWeeklyKeepAliveEnabled(normalized.weeklyKeepAliveEnabled);
      runtime.setHeartbeatSchedule(normalized.heartbeatSchedule);
      runtime.setRequestTimeoutSeconds(normalized.timeoutSeconds);
      await runtime.refreshProfiles();
      runtime.syncWeeklyScheduler();
      return SettingsSaved(normalized);
    } catch (error) {
      return SettingsPersistedWithFailure(normalized, error);
    }
  }
}
