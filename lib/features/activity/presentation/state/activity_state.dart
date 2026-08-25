import 'package:nini_hub/features/activity/application/activity_history.dart';
import 'package:nini_hub/features/activity/domain/activity_log.dart';

enum ActivityStatusFilter { all, running, error }

enum ActivityOperation { load, clear }

final class ActivityState {
  ActivityState({
    ActivityHistorySnapshot? snapshot,
    this.isInitialized = false,
    this.search = '',
    this.statusFilter = ActivityStatusFilter.all,
    this.selectedLogId,
    this.operation,
    this.errorMessage,
    this.failure,
  }) : snapshot = snapshot ?? ActivityHistorySnapshot(logs: const []);

  static const _unset = Object();

  final ActivityHistorySnapshot snapshot;
  final bool isInitialized;
  final String search;
  final ActivityStatusFilter statusFilter;
  final String? selectedLogId;
  final ActivityOperation? operation;
  final String? errorMessage;
  final Object? failure;

  List<ActivityLog> get logs => snapshot.logs;

  List<ActivityLog> get visibleLogs {
    final normalizedSearch = search.trim().toLowerCase();
    if (normalizedSearch.isEmpty && statusFilter == ActivityStatusFilter.all) {
      return logs;
    }
    return List.unmodifiable(
      logs.where((log) {
        final statusMatches = switch (statusFilter) {
          ActivityStatusFilter.all => true,
          ActivityStatusFilter.running =>
            log.status == ActivityLogStatus.running,
          ActivityStatusFilter.error => log.status == ActivityLogStatus.error,
        };
        final textMatches =
            normalizedSearch.isEmpty ||
            log.summary.toLowerCase().contains(normalizedSearch) ||
            log.command.toLowerCase().contains(normalizedSearch) ||
            log.output.toLowerCase().contains(normalizedSearch);
        return statusMatches && textMatches;
      }),
    );
  }

  ActivityLog? get selectedLog {
    final visible = visibleLogs;
    if (visible.isEmpty) return null;
    final selectedId = selectedLogId;
    if (selectedId != null) {
      for (final log in visible) {
        if (log.id == selectedId) return log;
      }
    }
    return visible.first;
  }

  bool get isBusy => operation != null;

  bool get isLoading => operation == ActivityOperation.load;

  bool get isClearing => operation == ActivityOperation.clear;

  ActivityState copyWith({
    ActivityHistorySnapshot? snapshot,
    bool? isInitialized,
    String? search,
    ActivityStatusFilter? statusFilter,
    Object? selectedLogId = _unset,
    Object? operation = _unset,
    Object? errorMessage = _unset,
    Object? failure = _unset,
  }) => ActivityState(
    snapshot: snapshot ?? this.snapshot,
    isInitialized: isInitialized ?? this.isInitialized,
    search: search ?? this.search,
    statusFilter: statusFilter ?? this.statusFilter,
    selectedLogId: identical(selectedLogId, _unset)
        ? this.selectedLogId
        : selectedLogId as String?,
    operation: identical(operation, _unset)
        ? this.operation
        : operation as ActivityOperation?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    failure: identical(failure, _unset) ? this.failure : failure,
  );
}
