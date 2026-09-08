import 'dart:convert';

import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/settings/domain/app_preferences.dart';
import 'package:nini_hub/features/settings/domain/settings_ports.dart';

final class DriftSettingsRepository implements SettingsRepository {
  const DriftSettingsRepository(this._database);

  static const _themeKey = 'theme';
  static const _accentKey = 'accent';
  static const _fontScaleKey = 'font_scale';
  static const _fontFamilyKey = 'font_family';
  static const _concurrencyKey = 'concurrency';
  static const _timeoutSecondsKey = 'timeout_seconds';
  static const _compactCardsKey = 'compact_cards';
  static const _weeklyKeepAliveEnabledKey = 'weekly_keep_alive_enabled';
  static const _keepTerminalOpenAfterExitKey = 'keep_terminal_open_after_exit';
  static const _profilesRootPathKey = 'profiles_root_path';

  final AppDatabase _database;

  @override
  Future<AppPreferences> load() async {
    final schedule = _readSchedule(
      await _database.setting('heartbeat_schedule'),
    );
    final theme = await _database.setting(_themeKey);
    final accent = await _database.setting(_accentKey);
    final storedFontScale = await _database.setting(_fontScaleKey);
    final fontFamily = await _database.setting(_fontFamilyKey);
    final storedConcurrency = await _database.setting(_concurrencyKey);
    final storedTimeoutSeconds = await _database.setting(_timeoutSecondsKey);
    final compactCards = await _database.setting(_compactCardsKey);
    final weeklyKeepAliveEnabled = await _database.setting(
      _weeklyKeepAliveEnabledKey,
    );
    final keepTerminalOpenAfterExit = await _database.setting(
      _keepTerminalOpenAfterExitKey,
    );
    final profilesRoot = await _database.setting(_profilesRootPathKey);
    final fontScale =
        double.tryParse(storedFontScale ?? '') ??
        AppPreferences.defaults.fontScale;

    return AppPreferences(
      heartbeatSchedule: schedule,
      theme: theme ?? AppPreferences.defaults.theme,
      accent: accent ?? AppPreferences.defaults.accent,
      fontScale: fontScale.clamp(.8, 1.2).toDouble(),
      fontFamily: fontFamily ?? AppPreferences.defaults.fontFamily,
      concurrency:
          int.tryParse(storedConcurrency ?? '') ??
          AppPreferences.defaults.concurrency,
      timeoutSeconds:
          int.tryParse(storedTimeoutSeconds ?? '') ??
          AppPreferences.defaults.timeoutSeconds,
      compactCards: compactCards == 'true',
      weeklyKeepAliveEnabled: weeklyKeepAliveEnabled != 'false',
      keepTerminalOpenAfterExit: keepTerminalOpenAfterExit != 'false',
      profilesRoot: profilesRoot ?? AppPreferences.defaults.profilesRoot,
    );
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    await _database.transaction(() async {
      await Future.wait([
        _database.saveSetting(
          'heartbeat_schedule',
          jsonEncode({
            'version': 1,
            'minutes': preferences.heartbeatSchedule.slots,
            'weekdays': preferences.heartbeatSchedule.weekdays,
            'intervalMinutes': preferences.heartbeatSchedule.intervalMinutes,
          }),
        ),
        _database.saveSetting(_themeKey, preferences.theme),
        _database.saveSetting(_accentKey, preferences.accent),
        _database.saveSetting(_fontScaleKey, preferences.fontScale.toString()),
        _database.saveSetting(_fontFamilyKey, preferences.fontFamily),
        _database.saveSetting(
          _concurrencyKey,
          preferences.concurrency.toString(),
        ),
        _database.saveSetting(
          _timeoutSecondsKey,
          preferences.timeoutSeconds.toString(),
        ),
        _database.saveSetting(
          _compactCardsKey,
          preferences.compactCards.toString(),
        ),
        _database.saveSetting(
          _weeklyKeepAliveEnabledKey,
          preferences.weeklyKeepAliveEnabled.toString(),
        ),
        _database.saveSetting(
          _keepTerminalOpenAfterExitKey,
          preferences.keepTerminalOpenAfterExit.toString(),
        ),
        _database.saveSetting(_profilesRootPathKey, preferences.profilesRoot),
      ]);
    });
  }

  static HeartbeatDailySchedule _readSchedule(String? stored) {
    if (stored == null) return HeartbeatDailySchedule.continuous;
    try {
      final value = jsonDecode(stored) as Map<String, dynamic>;
      if (value['version'] != 1) return HeartbeatDailySchedule.continuous;
      return HeartbeatDailySchedule(
        minutes: (value['minutes'] as List).cast<int>(),
        weekdays: (value['weekdays'] as List).cast<int>(),
        intervalMinutes: value['intervalMinutes'] as int?,
      ).normalized();
    } catch (_) {
      return HeartbeatDailySchedule.continuous;
    }
  }
}
