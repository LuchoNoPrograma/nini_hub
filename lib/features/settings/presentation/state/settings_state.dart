import 'package:multi_cli_ai/features/settings/domain/app_preferences.dart';

enum SettingsOperation { load, save }

final class SettingsState {
  const SettingsState({
    this.preferences = AppPreferences.defaults,
    this.isInitialized = false,
    this.operation,
    this.errorMessage,
    this.failure,
  });

  static const _unset = Object();

  final AppPreferences preferences;
  final bool isInitialized;
  final SettingsOperation? operation;
  final String? errorMessage;
  final Object? failure;

  bool get isBusy => operation != null;

  bool get isLoading => operation == SettingsOperation.load;

  bool get isSaving => operation == SettingsOperation.save;

  SettingsState copyWith({
    AppPreferences? preferences,
    bool? isInitialized,
    Object? operation = _unset,
    Object? errorMessage = _unset,
    Object? failure = _unset,
  }) => SettingsState(
    preferences: preferences ?? this.preferences,
    isInitialized: isInitialized ?? this.isInitialized,
    operation: identical(operation, _unset)
        ? this.operation
        : operation as SettingsOperation?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    failure: identical(failure, _unset) ? this.failure : failure,
  );
}
