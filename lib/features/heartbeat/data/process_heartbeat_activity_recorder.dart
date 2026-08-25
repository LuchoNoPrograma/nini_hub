import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

final class ProcessHeartbeatActivityRecorder
    implements HeartbeatActivityRecorder {
  const ProcessHeartbeatActivityRecorder(this.runner);

  final ProcessRunner runner;

  @override
  Future<void> record({
    required Profile profile,
    required HeartbeatActivityKind kind,
    required String message,
  }) => runner.addInternalLog(
    summary: switch (kind) {
      HeartbeatActivityKind.verified || HeartbeatActivityKind.unverified =>
        'Verificar ventana de ${profile.displayName}',
      HeartbeatActivityKind.probeFailure =>
        'Revisar ventana de ${profile.displayName}',
    },
    status: kind == HeartbeatActivityKind.verified ? 'success' : 'error',
    output: kind == HeartbeatActivityKind.probeFailure
        ? '$message Reintento con backoff.'
        : message,
    profileId: profile.id,
    command: 'codex app-server account/rateLimits/read',
  );
}
