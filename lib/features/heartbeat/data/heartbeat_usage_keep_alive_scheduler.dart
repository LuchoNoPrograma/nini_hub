import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/heartbeat/data/dart_heartbeat_scheduler.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';

typedef HeartbeatUsageObservation =
    Future<HeartbeatRunResult> Function({
      required Profile profile,
      required UsageSnapshot snapshot,
    });

typedef HeartbeatUsageSnapshotPublisher =
    Future<void> Function({
      required String profileId,
      required UsageSnapshot snapshot,
      UsageSnapshot? previousSnapshot,
    });

final class HeartbeatUsageKeepAliveScheduler
    implements UsageKeepAliveScheduler {
  const HeartbeatUsageKeepAliveScheduler({
    required this.scheduler,
    required this.runner,
    required this.observe,
    required this.publish,
    this.operationGate,
  });

  final DartHeartbeatScheduler scheduler;
  final ProcessRunner runner;
  final HeartbeatUsageObservation observe;
  final HeartbeatUsageSnapshotPublisher publish;
  final UsageOperationGate? operationGate;

  @override
  bool scheduleIfEligible({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) {
    if (profile.toolKey != 'codex') return false;
    return scheduler.enqueueBackgroundOperation(
      profileId: profile.id,
      operation: () =>
          operationGate?.run(profile.id, () => _observe(profile, snapshot)) ??
          _observe(profile, snapshot),
      onError: (error, _) => runner.addInternalLog(
        summary: 'Revisar heartbeat de ${profile.displayName}',
        status: 'error',
        output: ProcessRunner.sanitizeOutput(error.toString()),
        profileId: profile.id,
        command: 'heartbeat automatic observation',
      ),
    );
  }

  Future<void> _observe(Profile profile, UsageSnapshot snapshot) async {
    if (!scheduler.enabled) return;
    final result = await observe(profile: profile, snapshot: snapshot);
    final latestSnapshot = result.latestUsageSnapshot;
    if (latestSnapshot == null || !scheduler.enabled) return;
    await publish(
      profileId: profile.id,
      snapshot: latestSnapshot,
      previousSnapshot: result.previousUsageSnapshot,
    );
  }
}
