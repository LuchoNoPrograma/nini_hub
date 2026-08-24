import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/features/settings/application/settings.dart';
import 'package:multi_cli_ai/features/settings/domain/app_preferences.dart';
import 'package:multi_cli_ai/features/settings/domain/settings_ports.dart';

void main() {
  test('defaults preserve the legacy settings values', () {
    const preferences = AppPreferences.defaults;

    expect(preferences.theme, 'dark');
    expect(preferences.accent, 'cyan');
    expect(preferences.fontScale, .9);
    expect(preferences.fontFamily, 'system');
    expect(preferences.concurrency, 3);
    expect(preferences.timeoutSeconds, 15);
    expect(preferences.compactCards, isFalse);
    expect(preferences.weeklyKeepAliveEnabled, isTrue);
    expect(preferences.profilesRoot, isEmpty);
  });

  test('load applies runtime settings after reading the repository', () async {
    final events = <String>[];
    const stored = AppPreferences(
      theme: 'system',
      accent: 'mint',
      fontScale: 1.1,
      fontFamily: 'ubuntu',
      concurrency: 5,
      timeoutSeconds: 45,
      compactCards: true,
      weeklyKeepAliveEnabled: false,
      profilesRoot: '/configured/profiles',
    );
    final repository = _MemorySettingsRepository(stored, events);
    final runtime = _RecordingSettingsRuntime(events);

    final result = await LoadSettings(
      repository: repository,
      runtime: runtime,
    )();

    expect(result, same(stored));
    expect(events, ['load', 'keep-alive:false', 'timeout:45']);
  });

  test('save normalizes and preserves the legacy effect order', () async {
    final events = <String>[];
    final repository = _MemorySettingsRepository(
      AppPreferences.defaults,
      events,
    );
    final runtime = _RecordingSettingsRuntime(events);

    final result = await SaveSettings(repository: repository, runtime: runtime)(
      const AppPreferences(
        theme: 'light',
        accent: 'amber',
        fontScale: 2,
        fontFamily: 'noto',
        concurrency: 99,
        timeoutSeconds: 1,
        compactCards: true,
        weeklyKeepAliveEnabled: false,
        profilesRoot: '  /new/profiles  ',
      ),
    );

    expect(result, isA<SettingsSaved>());
    expect(result.preferences.fontScale, 1.2);
    expect(result.preferences.concurrency, 6);
    expect(result.preferences.timeoutSeconds, 5);
    expect(result.preferences.profilesRoot, '/new/profiles');
    expect(repository.saved, same(result.preferences));
    expect(events, [
      'keep-alive:false',
      'save',
      'timeout:5',
      'refresh-profiles',
      'sync-weekly-scheduler',
    ]);
  });

  test('save failure keeps only the pre-persistence runtime effect', () async {
    final events = <String>[];
    final repository = _MemorySettingsRepository(
      AppPreferences.defaults,
      events,
      saveError: StateError('write failed'),
    );
    final runtime = _RecordingSettingsRuntime(events);

    await expectLater(
      SaveSettings(repository: repository, runtime: runtime)(
        const AppPreferences(
          theme: 'light',
          accent: 'amber',
          fontScale: 1,
          fontFamily: 'noto',
          concurrency: 4,
          timeoutSeconds: 30,
          compactCards: true,
          weeklyKeepAliveEnabled: false,
          profilesRoot: '/profiles',
        ),
      ),
      throwsStateError,
    );

    expect(events, ['keep-alive:false', 'save']);
  });

  test(
    'refresh failure happens after persistence and timeout update',
    () async {
      final events = <String>[];
      final repository = _MemorySettingsRepository(
        AppPreferences.defaults,
        events,
      );
      final failure = StateError('refresh failed');
      final runtime = _RecordingSettingsRuntime(events, refreshError: failure);
      final result = await SaveSettings(
        repository: repository,
        runtime: runtime,
      )(AppPreferences.defaults);

      expect(result, isA<SettingsPersistedWithFailure>());
      expect(result.preferences, same(repository.saved));
      expect((result as SettingsPersistedWithFailure).failure, same(failure));
      expect(repository.saved, isNotNull);
      expect(events, [
        'keep-alive:true',
        'save',
        'timeout:15',
        'refresh-profiles',
      ]);
    },
  );
}

final class _MemorySettingsRepository implements SettingsRepository {
  _MemorySettingsRepository(this.stored, this.events, {this.saveError});

  final AppPreferences stored;
  final List<String> events;
  final Object? saveError;
  AppPreferences? saved;

  @override
  Future<AppPreferences> load() async {
    events.add('load');
    return stored;
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    events.add('save');
    saved = preferences;
    final error = saveError;
    if (error != null) throw error;
  }
}

final class _RecordingSettingsRuntime implements SettingsRuntime {
  _RecordingSettingsRuntime(this.events, {this.refreshError});

  final List<String> events;
  final Object? refreshError;

  @override
  Future<void> refreshProfiles() async {
    events.add('refresh-profiles');
    final error = refreshError;
    if (error != null) throw error;
  }

  @override
  void setRequestTimeoutSeconds(int seconds) {
    events.add('timeout:$seconds');
  }

  @override
  void setWeeklyKeepAliveEnabled(bool enabled) {
    events.add('keep-alive:$enabled');
  }

  @override
  void syncWeeklyScheduler() {
    events.add('sync-weekly-scheduler');
  }
}
