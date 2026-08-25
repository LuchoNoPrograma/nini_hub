import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';

final class ProcessUsageActivityRecorder implements UsageActivityRecorder {
  const ProcessUsageActivityRecorder(this.runner);

  final ProcessRunner runner;

  @override
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) => runner.addInternalLog(
    summary: 'Actualizar ${profile.displayName}',
    status: snapshot.status == UsageRefreshStatus.success ? 'success' : 'error',
    output:
        snapshot.errorMessage ??
        '${snapshot.windows.length} ventanas y '
            '${snapshot.dailyUsage.length} días de uso.',
    profileId: profile.id,
    command: 'codex app-server metadata',
  );
}
