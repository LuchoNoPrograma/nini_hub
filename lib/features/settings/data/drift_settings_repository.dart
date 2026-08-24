import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/settings/domain/app_preferences.dart';
import 'package:multi_cli_ai/features/settings/domain/settings_ports.dart';

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
  static const _profilesRootPathKey = 'profiles_root_path';

  final AppDatabase _database;

  @override
  Future<AppPreferences> load() async {
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
    final profilesRoot = await _database.setting(_profilesRootPathKey);
    final fontScale =
        double.tryParse(storedFontScale ?? '') ??
        AppPreferences.defaults.fontScale;

    return AppPreferences(
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
      profilesRoot: profilesRoot ?? AppPreferences.defaults.profilesRoot,
    );
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    await Future.wait([
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
      _database.saveSetting(_profilesRootPathKey, preferences.profilesRoot),
    ]);
  }
}
