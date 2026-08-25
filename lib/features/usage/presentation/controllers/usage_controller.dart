import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/features/usage/application/usage_calendar.dart';
import 'package:nini_hub/features/usage/application/usage_refresh.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_failure.dart';
import 'package:nini_hub/features/usage/presentation/state/usage_state.dart';

typedef UsageControllerDependenciesBuilder =
    UsageControllerDependencies Function(Ref<UsageState> ref);

final class UsageControllerDependencies {
  const UsageControllerDependencies({
    required this.refreshUsage,
    required this.refreshAllUsage,
    required this.loadUsageCalendar,
    required this.refreshConcurrency,
  });

  final RefreshUsage refreshUsage;
  final RefreshAllUsage refreshAllUsage;
  final LoadUsageCalendar loadUsageCalendar;
  final int Function() refreshConcurrency;
}

final class UsageController extends Notifier<UsageState> {
  factory UsageController({
    required RefreshUsage refreshUsage,
    required RefreshAllUsage refreshAllUsage,
    required LoadUsageCalendar loadUsageCalendar,
    int Function()? refreshConcurrency,
  }) => UsageController.composed(
    (_) => UsageControllerDependencies(
      refreshUsage: refreshUsage,
      refreshAllUsage: refreshAllUsage,
      loadUsageCalendar: loadUsageCalendar,
      refreshConcurrency: refreshConcurrency ?? _defaultConcurrency,
    ),
  );

  UsageController.composed(this._buildDependencies);

  final UsageControllerDependenciesBuilder _buildDependencies;
  late UsageControllerDependencies _dependencies;
  int _generation = 0;
  int _calendarRequest = 0;
  int _batchRequest = 0;

  static int _defaultConcurrency() => 3;

  @override
  UsageState build() {
    final buildGeneration = ++_generation;
    ref.onDispose(() {
      if (_generation == buildGeneration) _generation++;
    });
    _dependencies = _buildDependencies(ref);
    return UsageState();
  }

  void selectDay(DateTime day) {
    state = state.copyWith(selectedDay: day);
  }

  Future<bool> loadCalendar() async {
    final generation = _generation;
    final request = ++_calendarRequest;
    state = state.copyWith(isCalendarLoading: true, calendarFailure: null);
    try {
      final calendar = await _dependencies.loadUsageCalendar();
      if (!_isCurrentCalendarRequest(generation, request)) return false;
      state = state.copyWith(
        calendar: calendar,
        isCalendarInitialized: true,
        isCalendarLoading: false,
      );
      return true;
    } catch (error) {
      if (!_isCurrentCalendarRequest(generation, request)) return false;
      state = state.copyWith(
        isCalendarLoading: false,
        calendarFailure: UsageOperationFailure(
          cause: error,
          message: 'No se pudo cargar el calendario de uso.',
        ),
      );
      return false;
    }
  }

  Future<bool> refreshOne(String profileId) async {
    if (state.isRefreshingAll || state.isRefreshingProfile(profileId)) {
      return false;
    }
    final generation = _generation;
    final failures = Map<String, UsageOperationFailure>.of(
      state.profileFailures,
    )..remove(profileId);
    final refreshing = Set<String>.of(state.refreshingProfileIds)
      ..add(profileId);
    state = state.copyWith(
      refreshingProfileIds: refreshing,
      profileFailures: failures,
    );

    try {
      await _dependencies.refreshUsage(profileId);
      if (generation != _generation) return false;
      _finishProfileRefresh(profileId);
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      _finishProfileRefresh(
        profileId,
        failure: UsageOperationFailure(
          cause: error,
          message: _refreshFailureMessage(error),
        ),
      );
      return false;
    }
  }

  Future<bool> refreshAll() async {
    if (state.isRefreshing) return false;
    final generation = _generation;
    final request = ++_batchRequest;
    state = state.copyWith(
      isRefreshingAll: true,
      completedBatchByProfile: const {},
      batchFailure: null,
    );

    try {
      final result = await _dependencies.refreshAllUsage(
        concurrency: _dependencies.refreshConcurrency(),
        onProgress: (profileId, snapshot) {
          if (!_isCurrentBatchRequest(generation, request)) return;
          _recordBatchProgress(profileId, snapshot);
        },
      );
      if (!_isCurrentBatchRequest(generation, request)) return false;
      state = state.copyWith(
        isRefreshingAll: false,
        completedBatchByProfile: result.byProfile,
        profileFailures: _withoutCompletedFailures(result.byProfile),
      );
      return true;
    } catch (error) {
      if (!_isCurrentBatchRequest(generation, request)) return false;
      final completed = switch (error) {
        UsageBatchFailure() => error.completedByProfile,
        _ => state.completedBatchByProfile,
      };
      state = state.copyWith(
        isRefreshingAll: false,
        completedBatchByProfile: completed,
        profileFailures: _withoutCompletedFailures(completed),
        batchFailure: UsageOperationFailure(
          cause: error,
          message: _batchFailureMessage(error),
        ),
      );
      return false;
    }
  }

  void clearCalendarFailure() {
    if (state.calendarFailure == null) return;
    state = state.copyWith(calendarFailure: null);
  }

  void clearBatchFailure() {
    if (state.batchFailure == null) return;
    state = state.copyWith(batchFailure: null);
  }

  void clearProfileFailure(String profileId) {
    if (!state.profileFailures.containsKey(profileId)) return;
    final failures = Map<String, UsageOperationFailure>.of(
      state.profileFailures,
    )..remove(profileId);
    state = state.copyWith(profileFailures: failures);
  }

  bool _isCurrentCalendarRequest(int generation, int request) =>
      generation == _generation && request == _calendarRequest;

  bool _isCurrentBatchRequest(int generation, int request) =>
      generation == _generation &&
      request == _batchRequest &&
      state.isRefreshingAll;

  void _finishProfileRefresh(
    String profileId, {
    UsageOperationFailure? failure,
  }) {
    final refreshing = Set<String>.of(state.refreshingProfileIds)
      ..remove(profileId);
    final failures = Map<String, UsageOperationFailure>.of(
      state.profileFailures,
    );
    if (failure == null) {
      failures.remove(profileId);
    } else {
      failures[profileId] = failure;
    }
    state = state.copyWith(
      refreshingProfileIds: refreshing,
      profileFailures: failures,
    );
  }

  void _recordBatchProgress(String profileId, UsageSnapshot snapshot) {
    final completed = Map<String, UsageSnapshot>.of(
      state.completedBatchByProfile,
    )..[profileId] = snapshot;
    final failures = Map<String, UsageOperationFailure>.of(
      state.profileFailures,
    )..remove(profileId);
    state = state.copyWith(
      completedBatchByProfile: completed,
      profileFailures: failures,
    );
  }

  Map<String, UsageOperationFailure> _withoutCompletedFailures(
    Map<String, UsageSnapshot> completed,
  ) =>
      Map<String, UsageOperationFailure>.of(state.profileFailures)
        ..removeWhere((profileId, _) => completed.containsKey(profileId));

  static String _batchFailureMessage(Object error) {
    if (error case UsageBatchFailure(:final cause)) {
      return 'La actualización múltiple quedó incompleta. '
          '${_refreshFailureMessage(cause)}';
    }
    return 'No se pudieron actualizar las cuentas.';
  }

  static String _refreshFailureMessage(Object error) => switch (error) {
    UsageProfileNotFoundFailure() =>
      'El perfil ya no está disponible en este equipo. '
          'No se realizó ninguna consulta.',
    UsageProfileUnavailableFailure(
      reason: UsageProfileUnavailableReason.deactivated,
    ) =>
      'La cuenta está desactivada en este equipo. '
          'No se realizó ninguna consulta.',
    UsageProfileUnavailableFailure() =>
      'El perfil ya no está disponible en este equipo. '
          'No se realizó ninguna consulta.',
    UsageUnsupportedProviderFailure() =>
      'Esta herramienta todavía no expone cuotas en esta aplicación.',
    UsageRefreshAppliedFailure(
      progress: UsageRefreshProgress.snapshotPersisted,
    ) =>
      'El uso se guardó, pero no se pudo registrar la actividad.',
    UsageRefreshAppliedFailure() =>
      'El uso y la actividad se guardaron, pero no se pudo programar el '
          'heartbeat.',
    _ => 'No se pudo actualizar el uso.',
  };
}
