import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_cli_ai/features/settings/application/settings.dart';
import 'package:multi_cli_ai/features/settings/domain/app_preferences.dart';
import 'package:multi_cli_ai/features/settings/presentation/state/settings_state.dart';

typedef SettingsControllerDependenciesBuilder =
    SettingsControllerDependencies Function(Ref<SettingsState> ref);

final class SettingsControllerDependencies {
  const SettingsControllerDependencies({
    required this.loadSettings,
    required this.saveSettings,
  });

  final LoadSettings loadSettings;
  final SaveSettings saveSettings;
}

final class SettingsController extends Notifier<SettingsState> {
  factory SettingsController({
    required LoadSettings loadSettings,
    required SaveSettings saveSettings,
  }) => SettingsController.composed(
    (_) => SettingsControllerDependencies(
      loadSettings: loadSettings,
      saveSettings: saveSettings,
    ),
  );

  SettingsController.composed(this._buildDependencies);

  final SettingsControllerDependenciesBuilder _buildDependencies;
  late SettingsControllerDependencies _dependencies;

  @override
  SettingsState build() {
    _dependencies = _buildDependencies(ref);
    return const SettingsState();
  }

  Future<bool> load() async {
    if (!_begin(SettingsOperation.load)) return false;
    try {
      final preferences = await _dependencies.loadSettings();
      state = SettingsState(preferences: preferences, isInitialized: true);
      return true;
    } catch (error) {
      _completeFailure(error);
      return false;
    }
  }

  Future<bool> save(AppPreferences preferences) async {
    if (!_begin(SettingsOperation.save)) return false;
    try {
      final result = await _dependencies.saveSettings(preferences);
      switch (result) {
        case SettingsSaved():
          state = SettingsState(
            preferences: result.preferences,
            isInitialized: true,
          );
          return true;
        case SettingsPersistedWithFailure(:final failure):
          state = SettingsState(
            preferences: result.preferences,
            isInitialized: true,
            failure: failure,
            errorMessage:
                'La configuración se guardó, pero no se pudieron aplicar todos '
                'los cambios.',
          );
          return false;
      }
    } catch (error) {
      _completeFailure(error);
      return false;
    }
  }

  void clearFailure() {
    if (state.failure == null && state.errorMessage == null) return;
    state = state.copyWith(failure: null, errorMessage: null);
  }

  bool _begin(SettingsOperation operation) {
    if (state.isBusy) return false;
    state = state.copyWith(
      operation: operation,
      failure: null,
      errorMessage: null,
    );
    return true;
  }

  void _completeFailure(Object error) {
    final errorMessage = switch (state.operation) {
      SettingsOperation.load => 'No se pudo cargar la configuración.',
      _ => 'No se pudo guardar la configuración.',
    };
    state = state.copyWith(
      operation: null,
      failure: error,
      errorMessage: errorMessage,
    );
  }
}
