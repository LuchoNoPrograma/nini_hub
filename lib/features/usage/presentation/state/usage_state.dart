import 'package:multi_cli_ai/features/usage/domain/usage.dart';

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
    Map<String, UsageSnapshot> completedBatchByProfile = const {},
    Map<String, UsageOperationFailure> profileFailures = const {},
    this.batchFailure,
    this.calendarFailure,
  }) : calendar = calendar ?? UsageCalendar(const []),
       selectedDay = _dateOnly(selectedDay ?? DateTime.now()),
       refreshingProfileIds = Set.unmodifiable(refreshingProfileIds),
       completedBatchByProfile = Map.unmodifiable(completedBatchByProfile),
       profileFailures = Map.unmodifiable(profileFailures);

  static const _unset = Object();

  final UsageCalendar calendar;
  final DateTime selectedDay;
  final bool isCalendarInitialized;
  final bool isCalendarLoading;
  final Set<String> refreshingProfileIds;
  final bool isRefreshingAll;
  final Map<String, UsageSnapshot> completedBatchByProfile;
  final Map<String, UsageOperationFailure> profileFailures;
  final UsageOperationFailure? batchFailure;
  final UsageOperationFailure? calendarFailure;

  bool get isRefreshing => isRefreshingAll || refreshingProfileIds.isNotEmpty;

  bool isRefreshingProfile(String profileId) =>
      refreshingProfileIds.contains(profileId);

  UsageOperationFailure? failureForProfile(String profileId) =>
      profileFailures[profileId];

  UsageState copyWith({
    UsageCalendar? calendar,
    DateTime? selectedDay,
    bool? isCalendarInitialized,
    bool? isCalendarLoading,
    Iterable<String>? refreshingProfileIds,
    bool? isRefreshingAll,
    Map<String, UsageSnapshot>? completedBatchByProfile,
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
    completedBatchByProfile:
        completedBatchByProfile ?? this.completedBatchByProfile,
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
