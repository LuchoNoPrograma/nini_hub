import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/features/activity/application/activity_history.dart';
import 'package:nini_hub/features/activity/presentation/state/activity_state.dart';

typedef ActivityControllerDependenciesBuilder =
    ActivityControllerDependencies Function(Ref<ActivityState> ref);

final class ActivityControllerDependencies {
  const ActivityControllerDependencies({
    required this.observeActivityHistory,
    required this.clearActivityHistory,
  });

  final ObserveActivityHistory observeActivityHistory;
  final ClearActivityHistory clearActivityHistory;
}

final class ActivityController extends Notifier<ActivityState> {
  factory ActivityController({
    required ObserveActivityHistory observeActivityHistory,
    required ClearActivityHistory clearActivityHistory,
  }) => ActivityController.composed(
    (_) => ActivityControllerDependencies(
      observeActivityHistory: observeActivityHistory,
      clearActivityHistory: clearActivityHistory,
    ),
  );

  ActivityController.composed(this._buildDependencies);

  final ActivityControllerDependenciesBuilder _buildDependencies;
  late ActivityControllerDependencies _dependencies;
  StreamSubscription<ActivityHistorySnapshot>? _subscription;
  Completer<bool>? _pendingLoad;
  bool _streamFailed = false;
  int _generation = 0;

  @override
  ActivityState build() {
    final buildGeneration = ++_generation;
    ref.onDispose(() {
      if (_generation != buildGeneration) return;
      _generation++;
      if (_pendingLoad case final pending? when !pending.isCompleted) {
        pending.complete(false);
      }
      _pendingLoad = null;
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    _dependencies = _buildDependencies(ref);
    return ActivityState();
  }

  Future<bool> load() async {
    if (_subscription != null && !_streamFailed) {
      return !state.isBusy;
    }
    if (!_begin(ActivityOperation.load)) return false;
    final generation = _generation;
    await _subscription?.cancel();
    if (generation != _generation) return false;
    _subscription = null;
    _streamFailed = false;
    final firstSnapshot = Completer<bool>();
    _pendingLoad = firstSnapshot;
    try {
      _subscription = _dependencies.observeActivityHistory().listen(
        (snapshot) {
          if (generation != _generation) return;
          _acceptSnapshot(snapshot);
          if (!firstSnapshot.isCompleted) {
            firstSnapshot.complete(true);
            if (identical(_pendingLoad, firstSnapshot)) _pendingLoad = null;
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation != _generation) return;
          final failedSubscription = _subscription;
          _streamFailed = true;
          _subscription = null;
          unawaited(failedSubscription?.cancel());
          if (!firstSnapshot.isCompleted) {
            _completeFailure(error);
            firstSnapshot.complete(false);
            if (identical(_pendingLoad, firstSnapshot)) _pendingLoad = null;
            return;
          }
          _completeStreamFailure(error);
        },
        onDone: () {
          if (generation != _generation) return;
          _streamFailed = true;
          _subscription = null;
          if (!firstSnapshot.isCompleted) {
            final error = StateError(
              'El stream de actividad terminó antes de cargar el historial.',
            );
            _completeFailure(error);
            firstSnapshot.complete(false);
            if (identical(_pendingLoad, firstSnapshot)) _pendingLoad = null;
          }
        },
      );
      return firstSnapshot.future;
    } catch (error) {
      if (generation != _generation) return false;
      _completeFailure(error);
      if (!firstSnapshot.isCompleted) {
        firstSnapshot.complete(false);
        if (identical(_pendingLoad, firstSnapshot)) _pendingLoad = null;
      }
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

  void _acceptSnapshot(ActivityHistorySnapshot snapshot) {
    final operation = state.operation == ActivityOperation.load
        ? null
        : state.operation;
    state = ActivityState(
      snapshot: snapshot,
      isInitialized: true,
      search: state.search,
      statusFilter: state.statusFilter,
      selectedLogId: state.selectedLogId,
      operation: operation,
    );
  }

  void _completeStreamFailure(Object error) {
    state = state.copyWith(
      operation: null,
      failure: error,
      errorMessage: 'No se pudo mantener actualizado el historial.',
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
