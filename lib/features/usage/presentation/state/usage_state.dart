import 'package:nini_hub/features/usage/domain/usage.dart';

enum UsageProfileRefreshStage { idle, queued, running, completed, failed }

final class UsageOperationFailure {
  const UsageOperationFailure({required this.cause, required this.message});

  final Object cause;
  final String message;
}

final class UsageState {
  UsageState({
    UsageCalendar? calendar,
    DateTime? selectedDay,
    this.isCalendarInitialized = false,
    this.isCalendarLoading = false,
    Iterable<String> refreshingProfileIds = const [],
    this.isRefreshingAll = false,
    this.isSynchronizing = false,
    Iterable<String> batchTargetProfileIds = const [],
    Iterable<String> runningBatchProfileIds = const [],
    Iterable<String> failedBatchProfileIds = const [],
    Iterable<String> persistedBatchProfileIds = const [],
    Map<String, UsageSnapshot> completedBatchByProfile = const {},
    Map<String, UsageSnapshot> latestSnapshotByProfile = const {},
    Map<String, UsageOperationFailure> profileFailures = const {},
    this.batchFailure,
    this.calendarFailure,
  }) : calendar = calendar ?? UsageCalendar(const []),
       selectedDay = _dateOnly(selectedDay ?? DateTime.now()),
       refreshingProfileIds = Set.unmodifiable(refreshingProfileIds),
       batchTargetProfileIds = Set.unmodifiable(batchTargetProfileIds),
       runningBatchProfileIds = Set.unmodifiable(runningBatchProfileIds),
       failedBatchProfileIds = Set.unmodifiable(failedBatchProfileIds),
       persistedBatchProfileIds = Set.unmodifiable(persistedBatchProfileIds),
       completedBatchByProfile = Map.unmodifiable(completedBatchByProfile),
       latestSnapshotByProfile = Map.unmodifiable(latestSnapshotByProfile),
       profileFailures = Map.unmodifiable(profileFailures);

  static const _unset = Object();

  final UsageCalendar calendar;
  final DateTime selectedDay;
  final bool isCalendarInitialized;
  final bool isCalendarLoading;
  final Set<String> refreshingProfileIds;
  final bool isRefreshingAll;
  final bool isSynchronizing;
  final Set<String> batchTargetProfileIds;
  final Set<String> runningBatchProfileIds;
  final Set<String> failedBatchProfileIds;
  final Set<String> persistedBatchProfileIds;
  final Map<String, UsageSnapshot> completedBatchByProfile;
  final Map<String, UsageSnapshot> latestSnapshotByProfile;
  final Map<String, UsageOperationFailure> profileFailures;
  final UsageOperationFailure? batchFailure;
  final UsageOperationFailure? calendarFailure;

  bool get isRefreshing =>
      isRefreshingAll || refreshingProfileIds.isNotEmpty || isSynchronizing;

  int get batchTotalCount => batchTargetProfileIds.length;

  int get batchProcessedCount =>
      completedBatchByProfile.length + failedBatchProfileIds.length;

  int get batchQueuedCount =>
      (batchTotalCount - runningBatchProfileIds.length - batchProcessedCount)
          .clamp(0, batchTotalCount)
          .toInt();

  bool isRefreshingProfile(String profileId) =>
      refreshingProfileIds.contains(profileId);

  UsageProfileRefreshStage stageForProfile(String profileId) {
    if (refreshingProfileIds.contains(profileId) ||
        (isRefreshingAll && runningBatchProfileIds.contains(profileId))) {
      return UsageProfileRefreshStage.running;
    }
    if (!isRefreshingAll) return UsageProfileRefreshStage.idle;
    if (failedBatchProfileIds.contains(profileId)) {
      return UsageProfileRefreshStage.failed;
    }
    if (completedBatchByProfile.containsKey(profileId)) {
      return UsageProfileRefreshStage.completed;
    }
    if (batchTargetProfileIds.contains(profileId)) {
      return UsageProfileRefreshStage.queued;
    }
    return UsageProfileRefreshStage.idle;
  }

  UsageOperationFailure? failureForProfile(String profileId) =>
      profileFailures[profileId];

  UsageState copyWith({
    UsageCalendar? calendar,
    DateTime? selectedDay,
    bool? isCalendarInitialized,
    bool? isCalendarLoading,
    Iterable<String>? refreshingProfileIds,
    bool? isRefreshingAll,
    bool? isSynchronizing,
    Iterable<String>? batchTargetProfileIds,
    Iterable<String>? runningBatchProfileIds,
    Iterable<String>? failedBatchProfileIds,
    Iterable<String>? persistedBatchProfileIds,
    Map<String, UsageSnapshot>? completedBatchByProfile,
    Map<String, UsageSnapshot>? latestSnapshotByProfile,
    Map<String, UsageOperationFailure>? profileFailures,
    Object? batchFailure = _unset,
    Object? calendarFailure = _unset,
  }) => UsageState(
    calendar: calendar ?? this.calendar,
    selectedDay: selectedDay ?? this.selectedDay,
    isCalendarInitialized: isCalendarInitialized ?? this.isCalendarInitialized,
    isCalendarLoading: isCalendarLoading ?? this.isCalendarLoading,
    refreshingProfileIds: refreshingProfileIds ?? this.refreshingProfileIds,
    isRefreshingAll: isRefreshingAll ?? this.isRefreshingAll,
    isSynchronizing: isSynchronizing ?? this.isSynchronizing,
    batchTargetProfileIds: batchTargetProfileIds ?? this.batchTargetProfileIds,
    runningBatchProfileIds:
        runningBatchProfileIds ?? this.runningBatchProfileIds,
    failedBatchProfileIds: failedBatchProfileIds ?? this.failedBatchProfileIds,
    persistedBatchProfileIds:
        persistedBatchProfileIds ?? this.persistedBatchProfileIds,
    completedBatchByProfile:
        completedBatchByProfile ?? this.completedBatchByProfile,
    latestSnapshotByProfile:
        latestSnapshotByProfile ?? this.latestSnapshotByProfile,
    profileFailures: profileFailures ?? this.profileFailures,
    batchFailure: identical(batchFailure, _unset)
        ? this.batchFailure
        : batchFailure as UsageOperationFailure?,
    calendarFailure: identical(calendarFailure, _unset)
        ? this.calendarFailure
        : calendarFailure as UsageOperationFailure?,
  );

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
