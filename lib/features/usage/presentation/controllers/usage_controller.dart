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

  Future<bool> refreshOne(
    String profileId, {
    UsageRefreshProgressCallback? onProgress,
  }) async {
    if (state.isRefreshingAll ||
        state.isSynchronizing ||
        state.isRefreshingProfile(profileId)) {
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
      final snapshot = await _dependencies.refreshUsage(profileId);
      if (generation != _generation) return false;
      _recordLatestSnapshot(profileId, snapshot);
      onProgress?.call(profileId, snapshot);
      _finishProfileRefresh(profileId);
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      if (error case UsageRefreshAppliedFailure(:final snapshot)) {
        _recordLatestSnapshot(profileId, snapshot);
        onProgress?.call(profileId, snapshot);
      }
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

  Future<bool> refreshAll({UsageRefreshProgressCallback? onProgress}) async {
    if (state.isRefreshing) return false;
    final generation = _generation;
    final request = ++_batchRequest;
    state = state.copyWith(
      isRefreshingAll: true,
      batchTargetProfileIds: const {},
      runningBatchProfileIds: const {},
      failedBatchProfileIds: const {},
      persistedBatchProfileIds: const {},
      completedBatchByProfile: const {},
      batchFailure: null,
    );

    try {
      final result = await _dependencies.refreshAllUsage(
        concurrency: _dependencies.refreshConcurrency(),
        onTargets: (profileIds) {
          if (!_isCurrentBatchRequest(generation, request)) return;
          _recordBatchTargets(profileIds);
        },
        onStarted: (profileId) {
          if (!_isCurrentBatchRequest(generation, request)) return;
          _recordBatchStarted(profileId);
        },
        onProgress: (profileId, snapshot) {
          if (!_isCurrentBatchRequest(generation, request)) return;
          _recordBatchProgress(profileId, snapshot);
          onProgress?.call(profileId, snapshot);
        },
        onFailure: (profileId, error) {
          if (!_isCurrentBatchRequest(generation, request)) return;
          final snapshot = _recordBatchFailure(profileId, error);
          if (snapshot != null) onProgress?.call(profileId, snapshot);
        },
      );
      if (!_isCurrentBatchRequest(generation, request)) return false;
      state = state.copyWith(
        isRefreshingAll: false,
        runningBatchProfileIds: const {},
        completedBatchByProfile: result.byProfile,
        persistedBatchProfileIds: {
          ...state.persistedBatchProfileIds,
          ...result.byProfile.keys,
        },
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
        runningBatchProfileIds: const {},
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

  void setSynchronizing(bool value) {
    if (state.isSynchronizing == value) return;
    state = state.copyWith(isSynchronizing: value);
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

  void _recordLatestSnapshot(String profileId, UsageSnapshot snapshot) {
    final latest = Map<String, UsageSnapshot>.of(state.latestSnapshotByProfile);
    final current = latest[profileId];
    if (current == null || !snapshot.startedAt.isBefore(current.startedAt)) {
      latest[profileId] = snapshot;
      state = state.copyWith(latestSnapshotByProfile: latest);
    }
  }

  void _recordBatchTargets(List<String> profileIds) {
    final targets = profileIds.toSet();
    final failures = Map<String, UsageOperationFailure>.of(
      state.profileFailures,
    )..removeWhere((profileId, _) => targets.contains(profileId));
    state = state.copyWith(
      batchTargetProfileIds: targets,
      runningBatchProfileIds: const {},
      failedBatchProfileIds: const {},
      persistedBatchProfileIds: const {},
      profileFailures: failures,
    );
  }

  void _recordBatchStarted(String profileId) {
    final running = Set<String>.of(state.runningBatchProfileIds)
      ..add(profileId);
    state = state.copyWith(runningBatchProfileIds: running);
  }

  void _recordBatchProgress(String profileId, UsageSnapshot snapshot) {
    final completed = Map<String, UsageSnapshot>.of(
      state.completedBatchByProfile,
    )..[profileId] = snapshot;
    final failures = Map<String, UsageOperationFailure>.of(
      state.profileFailures,
    )..remove(profileId);
    final running = Set<String>.of(state.runningBatchProfileIds)
      ..remove(profileId);
    final persisted = Set<String>.of(state.persistedBatchProfileIds)
      ..add(profileId);
    final latest = Map<String, UsageSnapshot>.of(state.latestSnapshotByProfile);
    final current = latest[profileId];
    if (current == null || !snapshot.startedAt.isBefore(current.startedAt)) {
      latest[profileId] = snapshot;
    }
    state = state.copyWith(
      runningBatchProfileIds: running,
      persistedBatchProfileIds: persisted,
      completedBatchByProfile: completed,
      latestSnapshotByProfile: latest,
      profileFailures: failures,
    );
  }

  UsageSnapshot? _recordBatchFailure(String profileId, Object error) {
    final running = Set<String>.of(state.runningBatchProfileIds)
      ..remove(profileId);
    final failed = Set<String>.of(state.failedBatchProfileIds)..add(profileId);
    final failures =
        Map<String, UsageOperationFailure>.of(state.profileFailures)
          ..[profileId] = UsageOperationFailure(
            cause: error,
            message: _refreshFailureMessage(error),
          );
    final snapshot = switch (error) {
      UsageRefreshAppliedFailure(:final snapshot) => snapshot,
      _ => null,
    };
    final persisted = Set<String>.of(state.persistedBatchProfileIds);
    final latest = Map<String, UsageSnapshot>.of(state.latestSnapshotByProfile);
    if (snapshot != null) {
      persisted.add(profileId);
      final current = latest[profileId];
      if (current == null || !snapshot.startedAt.isBefore(current.startedAt)) {
        latest[profileId] = snapshot;
      }
    }
    state = state.copyWith(
      runningBatchProfileIds: running,
      failedBatchProfileIds: failed,
      persistedBatchProfileIds: persisted,
      latestSnapshotByProfile: latest,
      profileFailures: failures,
    );
    return snapshot;
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
