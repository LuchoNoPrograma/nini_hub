import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/settings/application/settings.dart';
import 'package:nini_hub/features/settings/domain/app_preferences.dart';
import 'package:nini_hub/features/settings/domain/settings_ports.dart';
import 'package:nini_hub/features/settings/presentation/controllers/settings_controller.dart';
import 'package:nini_hub/features/settings/presentation/state/settings_state.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  test('loads preferences and rejects an overlapping operation', () async {
    final gate = Completer<AppPreferences>();
    fixture.repository.loadGate = gate;

    final firstLoad = fixture.controller.load();
    final overlappingLoad = fixture.controller.load();

    expect(fixture.state.isLoading, isTrue);
    expect(await overlappingLoad, isFalse);
    gate.complete(_preferences(theme: 'system'));
    expect(await firstLoad, isTrue);
    expect(fixture.state.isInitialized, isTrue);
    expect(fixture.state.preferences.theme, 'system');
    expect(fixture.state.operation, isNull);
  });

  test('saves the normalized snapshot without reloading', () async {
    expect(
      await fixture.controller.save(
        _preferences(
          fontScale: 2,
          concurrency: 99,
          timeoutSeconds: 1,
          profilesRoot: '  /profiles  ',
        ),
      ),
      isTrue,
    );

    expect(fixture.repository.loadCalls, 0);
    expect(fixture.repository.saved, isNotNull);
    expect(fixture.state.preferences.fontScale, 1.2);
    expect(fixture.state.preferences.concurrency, 6);
    expect(fixture.state.preferences.timeoutSeconds, 5);
    expect(fixture.state.preferences.profilesRoot, '/profiles');
    expect(fixture.state.isSaving, isFalse);
  });

  test('retains failures as recoverable state', () async {
    final failure = StateError('write failed');
    fixture.repository.saveFailure = failure;

    expect(await fixture.controller.save(_preferences()), isFalse);
    expect(fixture.state.failure, same(failure));
    expect(fixture.state.errorMessage, 'No se pudo guardar la configuración.');
    expect(fixture.state.operation, isNull);
    expect(fixture.state.preferences, AppPreferences.defaults);
    expect(fixture.state.isInitialized, isFalse);

    fixture.controller.clearFailure();
    expect(fixture.state.failure, isNull);
    expect(fixture.state.errorMessage, isNull);
  });

  test('publishes persisted preferences when a later effect fails', () async {
    final failure = StateError('refresh failed');
    fixture.runtime.refreshFailure = failure;

    expect(
      await fixture.controller.save(
        _preferences(
          theme: 'light',
          fontScale: 2,
          concurrency: 99,
          timeoutSeconds: 1,
          profilesRoot: '  /new/profiles  ',
        ),
      ),
      isFalse,
    );

    expect(fixture.repository.stored, same(fixture.repository.saved));
    expect(fixture.state.preferences, same(fixture.repository.saved));
    expect(fixture.state.preferences.theme, 'light');
    expect(fixture.state.preferences.fontScale, 1.2);
    expect(fixture.state.preferences.concurrency, 6);
    expect(fixture.state.preferences.timeoutSeconds, 5);
    expect(fixture.state.preferences.profilesRoot, '/new/profiles');
    expect(fixture.state.isInitialized, isTrue);
    expect(fixture.state.failure, same(failure));
    expect(
      fixture.state.errorMessage,
      'La configuración se guardó, pero no se pudieron aplicar todos los '
      'cambios.',
    );
    expect(fixture.state.operation, isNull);
  });

  test('distinguishes a recoverable load failure', () async {
    final failure = StateError('read failed');
    fixture.repository.loadFailure = failure;

    expect(await fixture.controller.load(), isFalse);
    expect(fixture.state.failure, same(failure));
    expect(fixture.state.errorMessage, 'No se pudo cargar la configuración.');
    expect(fixture.state.isInitialized, isFalse);
  });
}

final class _Fixture {
  _Fixture() {
    provider = NotifierProvider<SettingsController, SettingsState>(
      () => SettingsController(
        loadSettings: LoadSettings(repository: repository, runtime: runtime),
        saveSettings: SaveSettings(repository: repository, runtime: runtime),
      ),
    );
    container = ProviderContainer();
    controller = container.read(provider.notifier);
  }

  final _MemorySettingsRepository repository = _MemorySettingsRepository();
  final _NoopSettingsRuntime runtime = _NoopSettingsRuntime();
  late final NotifierProvider<SettingsController, SettingsState> provider;
  late final ProviderContainer container;
  late final SettingsController controller;

  SettingsState get state => container.read(provider);

  void dispose() => container.dispose();
}

final class _MemorySettingsRepository implements SettingsRepository {
  AppPreferences stored = AppPreferences.defaults;
  Completer<AppPreferences>? loadGate;
  Object? saveFailure;
  Object? loadFailure;
  AppPreferences? saved;
  int loadCalls = 0;

  @override
  Future<AppPreferences> load() async {
    loadCalls++;
    final failure = loadFailure;
    if (failure != null) throw failure;
    final gate = loadGate;
    return gate == null ? stored : gate.future;
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    final failure = saveFailure;
    if (failure != null) throw failure;
    saved = preferences;
    stored = preferences;
  }
}

final class _NoopSettingsRuntime implements SettingsRuntime {
  @override
  void setHeartbeatSchedule(HeartbeatDailySchedule schedule) {}

  Object? refreshFailure;

  @override
  Future<void> refreshProfiles() async {
    final failure = refreshFailure;
    if (failure != null) throw failure;
  }

  @override
  void setRequestTimeoutSeconds(int seconds) {}

  @override
  void setWeeklyKeepAliveEnabled(bool enabled) {}

  @override
  void syncWeeklyScheduler() {}
}

AppPreferences _preferences({
  String theme = 'dark',
  double fontScale = .9,
  int concurrency = 3,
  int timeoutSeconds = 15,
  bool keepTerminalOpenAfterExit = true,
  String profilesRoot = '',
}) => AppPreferences(
  theme: theme,
  accent: 'cyan',
  fontScale: fontScale,
  fontFamily: 'system',
  concurrency: concurrency,
  timeoutSeconds: timeoutSeconds,
  compactCards: false,
  weeklyKeepAliveEnabled: true,
  keepTerminalOpenAfterExit: keepTerminalOpenAfterExit,
  profilesRoot: profilesRoot,
);
