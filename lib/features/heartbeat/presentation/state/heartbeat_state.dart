import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';

final class HeartbeatOperationFailure {
  const HeartbeatOperationFailure({required this.cause, required this.message});

  final Object cause;
  final String message;
}

final class HeartbeatPresentationState {
  HeartbeatPresentationState({
    Iterable<String> runningProfileIds = const [],
    Map<String, HeartbeatRunResult> resultsByProfile = const {},
    Map<String, HeartbeatOperationFailure> failuresByProfile = const {},
  }) : runningProfileIds = Set.unmodifiable(runningProfileIds),
       resultsByProfile = Map.unmodifiable(resultsByProfile),
       failuresByProfile = Map.unmodifiable(failuresByProfile);

  final Set<String> runningProfileIds;
  final Map<String, HeartbeatRunResult> resultsByProfile;
  final Map<String, HeartbeatOperationFailure> failuresByProfile;

  bool get isBusy => runningProfileIds.isNotEmpty;

  bool isRunningProfile(String profileId) =>
      runningProfileIds.contains(profileId);

  HeartbeatRunResult? resultForProfile(String profileId) =>
      resultsByProfile[profileId];

  HeartbeatOperationFailure? failureForProfile(String profileId) =>
      failuresByProfile[profileId];

  HeartbeatPresentationState copyWith({
    Iterable<String>? runningProfileIds,
    Map<String, HeartbeatRunResult>? resultsByProfile,
    Map<String, HeartbeatOperationFailure>? failuresByProfile,
  }) => HeartbeatPresentationState(
    runningProfileIds: runningProfileIds ?? this.runningProfileIds,
    resultsByProfile: resultsByProfile ?? this.resultsByProfile,
    failuresByProfile: failuresByProfile ?? this.failuresByProfile,
  );
}
