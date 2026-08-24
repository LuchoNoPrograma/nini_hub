import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/settings/data/drift_settings_repository.dart';
import 'package:multi_cli_ai/features/settings/domain/app_preferences.dart';

void main() {
  late AppDatabase database;
  late DriftSettingsRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftSettingsRepository(database);
  });

  tearDown(() => database.close());

  test('loads legacy defaults when settings are absent', () async {
    final preferences = await repository.load();

    expect(preferences.theme, AppPreferences.defaults.theme);
    expect(preferences.accent, AppPreferences.defaults.accent);
    expect(preferences.fontScale, AppPreferences.defaults.fontScale);
    expect(preferences.fontFamily, AppPreferences.defaults.fontFamily);
    expect(preferences.concurrency, AppPreferences.defaults.concurrency);
    expect(preferences.timeoutSeconds, AppPreferences.defaults.timeoutSeconds);
    expect(preferences.compactCards, AppPreferences.defaults.compactCards);
    expect(
      preferences.weeklyKeepAliveEnabled,
      AppPreferences.defaults.weeklyKeepAliveEnabled,
    );
    expect(preferences.profilesRoot, AppPreferences.defaults.profilesRoot);
  });

  test('loads all persisted values with legacy parsing rules', () async {
    for (final entry in const {
      'theme': 'system',
      'accent': 'mint',
      'font_scale': '1.1',
      'font_family': 'ubuntu',
      'concurrency': '5',
      'timeout_seconds': '45',
      'compact_cards': 'true',
      'weekly_keep_alive_enabled': 'false',
      'profiles_root_path': '/configured/profiles',
    }.entries) {
      await database.saveSetting(entry.key, entry.value);
    }

    final preferences = await repository.load();

    expect(preferences.theme, 'system');
    expect(preferences.accent, 'mint');
    expect(preferences.fontScale, 1.1);
    expect(preferences.fontFamily, 'ubuntu');
    expect(preferences.concurrency, 5);
    expect(preferences.timeoutSeconds, 45);
    expect(preferences.compactCards, isTrue);
    expect(preferences.weeklyKeepAliveEnabled, isFalse);
    expect(preferences.profilesRoot, '/configured/profiles');
  });

  test('preserves legacy fallbacks and load-time range behavior', () async {
    for (final entry in const {
      'font_scale': '9',
      'concurrency': '99',
      'timeout_seconds': '1',
      'compact_cards': 'TRUE',
      'weekly_keep_alive_enabled': 'FALSE',
    }.entries) {
      await database.saveSetting(entry.key, entry.value);
    }

    final outsideRange = await repository.load();

    expect(outsideRange.fontScale, 1.2);
    expect(outsideRange.concurrency, 99);
    expect(outsideRange.timeoutSeconds, 1);
    expect(outsideRange.compactCards, isFalse);
    expect(outsideRange.weeklyKeepAliveEnabled, isTrue);

    await database.saveSetting('font_scale', 'invalid');
    await database.saveSetting('concurrency', 'invalid');
    await database.saveSetting('timeout_seconds', 'invalid');

    final invalid = await repository.load();

    expect(invalid.fontScale, AppPreferences.defaults.fontScale);
    expect(invalid.concurrency, AppPreferences.defaults.concurrency);
    expect(invalid.timeoutSeconds, AppPreferences.defaults.timeoutSeconds);
  });

  test('saves the nine legacy keys with current timestamps', () async {
    const preferences = AppPreferences(
      theme: 'light',
      accent: 'amber',
      fontScale: 1.2,
      fontFamily: 'noto',
      concurrency: 6,
      timeoutSeconds: 5,
      compactCards: true,
      weeklyKeepAliveEnabled: false,
      profilesRoot: '/new/profiles',
    );

    await repository.save(preferences);

    expect(await database.setting('theme'), 'light');
    expect(await database.setting('accent'), 'amber');
    expect(await database.setting('font_scale'), '1.2');
    expect(await database.setting('font_family'), 'noto');
    expect(await database.setting('concurrency'), '6');
    expect(await database.setting('timeout_seconds'), '5');
    expect(await database.setting('compact_cards'), 'true');
    expect(await database.setting('weekly_keep_alive_enabled'), 'false');
    expect(await database.setting('profiles_root_path'), '/new/profiles');

    final rows = await database.select(database.appSettings).get();
    expect(rows, hasLength(9));
    final now = DateTime.now();
    expect(
      rows.every(
        (row) => now.difference(row.updatedAt).abs() < const Duration(days: 1),
      ),
      isTrue,
    );
  });
}
