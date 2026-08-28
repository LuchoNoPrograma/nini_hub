import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/settings/application/settings.dart';
import 'package:nini_hub/features/settings/data/desktop_settings_runtime.dart';
import 'package:nini_hub/features/settings/data/drift_settings_repository.dart';
import 'package:nini_hub/features/settings/domain/app_preferences.dart';
import 'package:nini_hub/features/settings/presentation/controllers/settings_controller.dart';
import 'package:nini_hub/features/settings/presentation/settings_dialog.dart';
import 'package:nini_hub/features/settings/presentation/state/settings_state.dart';
import 'package:nini_hub/providers/codex/codex_client_runtime.dart';

void main() {
  test('loads settings defaults and applies their runtime values', () async {
    final fixture = _SettingsFixture.create();
    addTearDown(fixture.dispose);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(fixture.settingsProvider.notifier).load(),
      true,
    );
    final preferences = container.read(fixture.settingsProvider).preferences;

    expect(preferences.theme, 'dark');
    expect(preferences.accent, 'cyan');
    expect(preferences.fontScale, .9);
    expect(preferences.fontFamily, 'system');
    expect(preferences.concurrency, 3);
    expect(preferences.timeoutSeconds, 15);
    expect(preferences.compactCards, isFalse);
    expect(preferences.weeklyKeepAliveEnabled, isTrue);
    expect(preferences.keepTerminalOpenAfterExit, isTrue);
    expect(fixture.codexRuntime.current.timeout, const Duration(seconds: 15));
    expect(fixture.scheduler.enabled, isTrue);
    expect(fixture.discovery.calls, 0);
  });

  test('loads persisted settings with the current parsing rules', () async {
    final fixture = _SettingsFixture.create();
    addTearDown(fixture.dispose);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final entry in const {
      'theme': 'system',
      'accent': 'mint',
      'font_scale': '1.1',
      'font_family': 'ubuntu',
      'concurrency': '5',
      'timeout_seconds': '45',
      'compact_cards': 'true',
      'weekly_keep_alive_enabled': 'false',
      'keep_terminal_open_after_exit': 'false',
      'profiles_root_path': '/configured/profiles',
    }.entries) {
      await fixture.database.saveSetting(entry.key, entry.value);
    }

    expect(
      await container.read(fixture.settingsProvider.notifier).load(),
      true,
    );
    final preferences = container.read(fixture.settingsProvider).preferences;

    expect(preferences.theme, 'system');
    expect(preferences.accent, 'mint');
    expect(preferences.fontScale, 1.1);
    expect(preferences.fontFamily, 'ubuntu');
    expect(preferences.concurrency, 5);
    expect(preferences.timeoutSeconds, 45);
    expect(preferences.compactCards, isTrue);
    expect(preferences.weeklyKeepAliveEnabled, isFalse);
    expect(preferences.keepTerminalOpenAfterExit, isFalse);
    expect(fixture.codexRuntime.current.timeout, const Duration(seconds: 45));
    expect(fixture.scheduler.enabled, isFalse);
    expect(fixture.discovery.rootsSeen, isEmpty);
  });

  test(
    'save clamps, persists, and rescans after storing the new root',
    () async {
      final fixture = _SettingsFixture.create();
      addTearDown(fixture.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await fixture.database.saveSetting(
        'profiles_root_path',
        '/original/profiles',
      );
      expect(
        await container.read(fixture.settingsProvider.notifier).load(),
        true,
      );
      expect(
        await container
            .read(fixture.settingsProvider.notifier)
            .save(
              const AppPreferences(
                theme: 'light',
                accent: 'amber',
                fontScale: 2,
                fontFamily: 'noto',
                concurrency: 99,
                timeoutSeconds: 1,
                compactCards: true,
                weeklyKeepAliveEnabled: false,
                keepTerminalOpenAfterExit: false,
                profilesRoot: '  /new/profiles  ',
              ),
            ),
        true,
      );
      final preferences = container.read(fixture.settingsProvider).preferences;

      expect(preferences.theme, 'light');
      expect(preferences.accent, 'amber');
      expect(preferences.fontScale, 1.2);
      expect(preferences.fontFamily, 'noto');
      expect(preferences.concurrency, 6);
      expect(preferences.timeoutSeconds, 5);
      expect(preferences.compactCards, isTrue);
      expect(preferences.weeklyKeepAliveEnabled, isFalse);
      expect(preferences.keepTerminalOpenAfterExit, isFalse);
      expect(fixture.scheduler.enabled, isFalse);
      expect(fixture.codexRuntime.current.timeout, const Duration(seconds: 5));
      expect(fixture.discovery.calls, 1);
      expect(fixture.discovery.rootsSeen, ['/new/profiles']);
      expect(await fixture.database.setting('theme'), 'light');
      expect(await fixture.database.setting('accent'), 'amber');
      expect(await fixture.database.setting('font_scale'), '1.2');
      expect(await fixture.database.setting('font_family'), 'noto');
      expect(await fixture.database.setting('concurrency'), '6');
      expect(await fixture.database.setting('timeout_seconds'), '5');
      expect(await fixture.database.setting('compact_cards'), 'true');
      expect(
        await fixture.database.setting('weekly_keep_alive_enabled'),
        'false',
      );
      expect(
        await fixture.database.setting('keep_terminal_open_after_exit'),
        'false',
      );
      expect(
        await fixture.database.setting('profiles_root_path'),
        '/new/profiles',
      );
    },
  );

  testWidgets('settings dialog exposes the legacy controls at 900x600', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _SettingsFixture.create();
    addTearDown(fixture.dispose);
    await fixture.database.saveSetting(
      'profiles_root_path',
      '/configured/profiles',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fixture.settingsProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark('cyan'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      showSettingsDialog(context, fixture.settingsProvider),
                  child: const Text('Abrir configuración'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir configuración'));
    await tester.pumpAndSettle();

    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('APARIENCIA'), findsOneWidget);
    expect(find.text('CONSULTAS'), findsOneWidget);
    expect(find.text('TERMINAL'), findsOneWidget);
    expect(find.text('MULTI-CLI'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.byType(SwitchListTile), findsNWidgets(3));
    expect(find.byTooltip('Cian'), findsOneWidget);
    expect(find.byTooltip('Menta'), findsOneWidget);
    expect(find.byTooltip('Ámbar'), findsOneWidget);
    expect(
      find.text('Iniciar automáticamente los ciclos de Codex'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Nini Hub hará una solicitud mínima para iniciar el siguiente',
      ),
      findsOneWidget,
    );
    expect(find.text('Mantener abierta al finalizar'), findsOneWidget);
    expect(find.textContaining('incluso con Ctrl+C'), findsOneWidget);
    expect(find.textContaining('Si desactivas'), findsNothing);
    expect(find.textContaining('backoff'), findsNothing);
    expect(find.textContaining('app-server'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/configured/profiles',
    );
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _SettingsFixture {
  _SettingsFixture._({
    required this.database,
    required this.discovery,
    required this.scheduler,
    required this.codexRuntime,
    required this.settingsProvider,
  });

  factory _SettingsFixture.create() {
    final database = AppDatabase(NativeDatabase.memory());
    final discovery = _RecordingProfileDiscoveryService(database);
    final scheduler = _RecordingWeeklyScheduler();
    final codexRuntime = CodexClientRuntime();
    final settingsRepository = DriftSettingsRepository(database);
    final settingsRuntime = DesktopSettingsRuntime(
      discovery: discovery,
      requestTimeoutSetter: codexRuntime.setRequestTimeoutSeconds,
      weeklyKeepAliveEnabledSetter: scheduler.setEnabled,
      monitorWeeklyProfiles: scheduler.monitorProfiles,
      onProfilesRefreshed: () async {},
    );
    final settingsProvider =
        NotifierProvider<SettingsController, SettingsState>(
          () => SettingsController(
            loadSettings: LoadSettings(
              repository: settingsRepository,
              runtime: settingsRuntime,
            ),
            saveSettings: SaveSettings(
              repository: settingsRepository,
              runtime: settingsRuntime,
            ),
          ),
        );
    return _SettingsFixture._(
      database: database,
      discovery: discovery,
      scheduler: scheduler,
      codexRuntime: codexRuntime,
      settingsProvider: settingsProvider,
    );
  }

  final AppDatabase database;
  final _RecordingProfileDiscoveryService discovery;
  final _RecordingWeeklyScheduler scheduler;
  final CodexClientRuntime codexRuntime;
  final NotifierProvider<SettingsController, SettingsState> settingsProvider;

  Future<void> dispose() => database.close();
}

final class _RecordingWeeklyScheduler {
  bool enabled = true;

  void setEnabled(bool value) => enabled = value;

  void monitorProfiles(Iterable<CliProfile> _) {}
}

final class _RecordingProfileDiscoveryService extends ProfileDiscoveryService {
  _RecordingProfileDiscoveryService(super.database) : super.test();

  int calls = 0;
  final List<String?> rootsSeen = [];

  @override
  Future<List<CliProfile>> discoverProfiles() async {
    calls++;
    rootsSeen.add(await database.setting('profiles_root_path'));
    return const [];
  }
}
