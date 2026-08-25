import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/settings/domain/app_preferences.dart';

void main() {
  test(
    'composition bootstraps settings and refreshes only accounts after save',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.saveSetting('timeout_seconds', '45');
      await database.saveSetting('concurrency', '5');
      await database.saveSetting('profiles_root_path', '/original/profiles');
      final discovery = _RecordingProfileDiscovery(database);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          profileDiscoveryProvider.overrideWithValue(discovery),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(settingsBootstrapProvider.future), isTrue);
      await container.read(appStartupProvider.future);
      expect(
        container.read(codexClientRuntimeProvider).current.timeout,
        const Duration(seconds: 45),
      );
      expect(
        container.read(settingsControllerProvider).preferences.concurrency,
        5,
      );

      expect(discovery.rootsSeen, ['/original/profiles']);
      final activityBeforeSave = container.read(activityControllerProvider);
      expect(activityBeforeSave.isInitialized, isTrue);
      final calendarBeforeSave = container
          .read(usageControllerProvider)
          .calendar;

      final saved = await container
          .read(settingsControllerProvider.notifier)
          .save(
            const AppPreferences(
              theme: 'light',
              accent: 'amber',
              fontScale: 1.1,
              fontFamily: 'noto',
              concurrency: 4,
              timeoutSeconds: 30,
              compactCards: true,
              weeklyKeepAliveEnabled: false,
              profilesRoot: '  /new/profiles  ',
            ),
          );

      expect(saved, isTrue);
      expect(discovery.rootsSeen, ['/original/profiles', '/new/profiles']);
      expect(
        container.read(activityControllerProvider),
        same(activityBeforeSave),
      );
      expect(
        container.read(usageControllerProvider).calendar,
        same(calendarBeforeSave),
      );
      expect(
        container.read(codexClientRuntimeProvider).current.timeout,
        const Duration(seconds: 30),
      );
      expect(
        container.read(settingsControllerProvider).preferences.concurrency,
        4,
      );
      expect(await database.setting('profiles_root_path'), '/new/profiles');
    },
  );

  test(
    'composition publishes persisted settings when discovery fails after save',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.saveSetting('profiles_root_path', '/original/profiles');
      final discovery = _RecordingProfileDiscovery(database);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          profileDiscoveryProvider.overrideWithValue(discovery),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(settingsBootstrapProvider.future), isTrue);
      await container.read(appStartupProvider.future);
      final failure = StateError('discovery failed');
      discovery.failure = failure;

      final saved = await container
          .read(settingsControllerProvider.notifier)
          .save(
            const AppPreferences(
              theme: 'light',
              accent: 'amber',
              fontScale: 1.1,
              fontFamily: 'noto',
              concurrency: 4,
              timeoutSeconds: 30,
              compactCards: true,
              weeklyKeepAliveEnabled: false,
              profilesRoot: '  /new/profiles  ',
            ),
          );
      final settingsState = container.read(settingsControllerProvider);

      expect(saved, isFalse);
      expect(discovery.rootsSeen, ['/original/profiles', '/new/profiles']);
      expect(await database.setting('profiles_root_path'), '/new/profiles');
      expect(settingsState.preferences.profilesRoot, '/new/profiles');
      expect(settingsState.preferences.timeoutSeconds, 30);
      expect(settingsState.failure, same(failure));
      expect(
        settingsState.errorMessage,
        'La configuración se guardó, pero no se pudieron aplicar todos los '
        'cambios.',
      );
      expect(
        container.read(codexClientRuntimeProvider).current.timeout,
        const Duration(seconds: 30),
      );
    },
  );

  test('app startup waits for a successful settings retry', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final discovery = _RecordingProfileDiscovery(database);
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        profileDiscoveryProvider.overrideWithValue(discovery),
        settingsBootstrapProvider.overrideWith((ref) async {
          attempts += 1;
          return attempts > 1;
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(settingsBootstrapProvider.future), isFalse);

    expect(discovery.rootsSeen, isEmpty);

    container.invalidate(settingsBootstrapProvider);
    expect(await container.read(settingsBootstrapProvider.future), isTrue);
    await container.read(appStartupProvider.future);

    expect(attempts, 2);
    expect(discovery.rootsSeen, [isNull]);
  });
}

final class _RecordingProfileDiscovery extends ProfileDiscoveryService {
  _RecordingProfileDiscovery(super.database) : super.test();

  final List<String?> rootsSeen = [];
  Object? failure;

  @override
  Future<List<CliProfile>> discoverProfiles() async {
    rootsSeen.add(await database.setting('profiles_root_path'));
    final failure = this.failure;
    if (failure != null) throw failure;
    return database.select(database.cliProfiles).get();
  }
}
