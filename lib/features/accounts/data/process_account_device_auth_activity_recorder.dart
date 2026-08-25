import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

final class ProcessAccountDeviceAuthActivityRecorder
    implements AccountDeviceAuthActivityRecorder {
  const ProcessAccountDeviceAuthActivityRecorder(this.runner);

  final ProcessRunner runner;

  @override
  Future<void> recordStarted(Profile profile) => runner.addInternalLog(
    summary: 'Vincular ${profile.displayName}',
    status: 'success',
    output: 'Codex inició el flujo oficial de código de dispositivo.',
    profileId: profile.id,
    command: 'codex app-server account/login/start',
  );

  @override
  Future<void> recordCompleted(Profile profile, {required bool success}) =>
      runner.addInternalLog(
        summary: 'Vincular ${profile.displayName}',
        status: success ? 'success' : 'error',
        output: success
            ? 'Codex confirmó la cuenta y guardó la credencial en el perfil.'
            : 'El acceso no fue confirmado.',
        profileId: profile.id,
        command: 'codex app-server account/login/completed',
      );
}
