import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';

final class ProcessUsageActivityRecorder
    implements UsageActivityRecorder, UsageResetCreditActivityRecorder {
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
    command: profile.toolKey == 'claude-cli'
        ? 'GET api.anthropic.com/api/oauth/usage'
        : 'codex app-server metadata',
  );

  @override
  Future<void> recordResetCredit({
    required Profile profile,
    required ResetCreditOutcome? outcome,
    String? errorMessage,
  }) => runner.addInternalLog(
    summary: 'Usar reset de ${profile.displayName}',
    status: outcome == null ? 'error' : 'success',
    output: switch (outcome) {
      null => errorMessage ?? 'No se pudo usar el reset.',
      ResetCreditOutcome.reset => 'Límites reiniciados; se gastó un reset.',
      ResetCreditOutcome.nothingToReset =>
        'No había nada que reiniciar; no se gastó ningún reset.',
      ResetCreditOutcome.noCredit => 'La cuenta no tiene resets disponibles.',
      ResetCreditOutcome.alreadyRedeemed => 'Ese reset ya se había aplicado.',
    },
    profileId: profile.id,
    command: 'codex app-server account/rateLimitResetCredit/consume',
  );
}
