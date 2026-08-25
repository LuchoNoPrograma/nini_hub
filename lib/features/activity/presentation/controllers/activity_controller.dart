import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/features/activity/application/activity_history.dart';
import 'package:nini_hub/features/activity/presentation/state/activity_state.dart';

typedef ActivityControllerDependenciesBuilder =
    ActivityControllerDependencies Function(Ref<ActivityState> ref);

final class ActivityControllerDependencies {
  const ActivityControllerDependencies({
    required this.loadActivityHistory,
    required this.clearActivityHistory,
  });

  final LoadActivityHistory loadActivityHistory;
  final ClearActivityHistory clearActivityHistory;
}

final class ActivityController extends Notifier<ActivityState> {
  factory ActivityController({
    required LoadActivityHistory loadActivityHistory,
    required ClearActivityHistory clearActivityHistory,
  }) => ActivityController.composed(
    (_) => ActivityControllerDependencies(
      loadActivityHistory: loadActivityHistory,
      clearActivityHistory: clearActivityHistory,
    ),
  );

  ActivityController.composed(this._buildDependencies);

  final ActivityControllerDependenciesBuilder _buildDependencies;
  late ActivityControllerDependencies _dependencies;
  int _generation = 0;

  @override
  ActivityState build() {
    final buildGeneration = ++_generation;
    ref.onDispose(() {
      if (_generation == buildGeneration) _generation++;
    });
    _dependencies = _buildDependencies(ref);
    return ActivityState();
  }

  Future<bool> load() async {
    if (!_begin(ActivityOperation.load)) return false;
    final generation = _generation;
    try {
      final snapshot = await _dependencies.loadActivityHistory();
      if (generation != _generation) return false;
      state = ActivityState(
        snapshot: snapshot,
        isInitialized: true,
        search: state.search,
        statusFilter: state.statusFilter,
        selectedLogId: state.selectedLogId,
      );
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      _completeFailure(error);
      return false;
    }
  }

  Future<bool> clear() async {
    if (!_begin(ActivityOperation.clear)) return false;
    final generation = _generation;
    try {
      final snapshot = await _dependencies.clearActivityHistory();
      if (generation != _generation) return false;
      state = ActivityState(
        snapshot: snapshot,
        isInitialized: true,
        search: state.search,
        statusFilter: state.statusFilter,
        selectedLogId: state.selectedLogId,
      );
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      _completeFailure(error);
      return false;
    }
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }

  void setStatusFilter(ActivityStatusFilter statusFilter) {
    state = state.copyWith(statusFilter: statusFilter);
  }

  void selectLog(String logId) {
    state = state.copyWith(selectedLogId: logId);
  }

  void clearFailure() {
    if (state.failure == null && state.errorMessage == null) return;
    state = state.copyWith(failure: null, errorMessage: null);
  }

  bool _begin(ActivityOperation operation) {
    if (state.isBusy) return false;
    state = state.copyWith(
      operation: operation,
      failure: null,
      errorMessage: null,
    );
    return true;
  }

  void _completeFailure(Object error) {
    final operation = state.operation;
    state = state.copyWith(
      operation: null,
      failure: error,
      errorMessage: _failureMessage(error, operation),
    );
  }

  static String _failureMessage(Object error, ActivityOperation? operation) =>
      switch (error) {
        ActivityClearAppliedFailure() =>
          'El historial se limpió, pero no se pudo actualizar la lista.',
        _ when operation == ActivityOperation.load =>
          'No se pudo cargar el historial.',
        _ => 'No se pudo limpiar el historial.',
      };
}
