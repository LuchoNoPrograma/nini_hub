import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/settings/domain/settings_ports.dart';

typedef RequestTimeoutSetter = void Function(int seconds);
typedef WeeklyKeepAliveEnabledSetter = void Function(bool enabled);
typedef WeeklyProfileMonitor = void Function(Iterable<CliProfile> profiles);

final class DesktopSettingsRuntime implements SettingsRuntime {
  DesktopSettingsRuntime({
    required this.discovery,
    required this.heartbeatScheduleSetter,
    required this.onProfilesRefreshed,
    required this.requestTimeoutSetter,
    required this.weeklyKeepAliveEnabledSetter,
    required this.monitorWeeklyProfiles,
  });

  final void Function(HeartbeatDailySchedule schedule) heartbeatScheduleSetter;

  @override
  void setHeartbeatSchedule(HeartbeatDailySchedule schedule) =>
      heartbeatScheduleSetter(schedule);

  final ProfileDiscoveryService discovery;
  final Future<void> Function() onProfilesRefreshed;
  final RequestTimeoutSetter requestTimeoutSetter;
  final WeeklyKeepAliveEnabledSetter weeklyKeepAliveEnabledSetter;
  final WeeklyProfileMonitor monitorWeeklyProfiles;
  List<CliProfile> _discoveredProfiles = const [];

  @override
  void setRequestTimeoutSeconds(int seconds) {
    requestTimeoutSetter(seconds);
  }

  @override
  void setWeeklyKeepAliveEnabled(bool enabled) {
    weeklyKeepAliveEnabledSetter(enabled);
  }

  @override
  Future<void> refreshProfiles() async {
    _discoveredProfiles = await discovery.discoverProfiles();
    await onProfilesRefreshed();
  }

  @override
  void syncWeeklyScheduler() {
    monitorWeeklyProfiles(
      _discoveredProfiles.where(
        (profile) =>
            profile.toolKey == 'codex' &&
            profile.isAvailable &&
            profile.hasAuthFile,
      ),
    );
  }
}
