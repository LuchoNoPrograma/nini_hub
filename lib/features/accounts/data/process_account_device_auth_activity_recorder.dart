import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';

final class ProcessAccountDeviceAuthActivityRecorder
    implements AccountDeviceAuthActivityRecorder {
  const ProcessAccountDeviceAuthActivityRecorder(this.runner);

  final ProcessRunner runner;

  @override
  Future<void> recordStarted(Profile profile) => runner.addInternalLog(
    summary: 'Vincular ${profile.displayName}',
    status: 'success',
    output: _isClaude(profile)
        ? 'Claude Code inició el flujo oficial de acceso.'
        : 'Codex inició el flujo oficial de código de dispositivo.',
    profileId: profile.id,
    command: _isClaude(profile)
        ? 'nini-agents exec ${_spec(profile)} -- auth login'
        : 'codex app-server account/login/start',
  );

  @override
  Future<void> recordCompleted(Profile profile, {required bool success}) =>
      runner.addInternalLog(
        summary: 'Vincular ${profile.displayName}',
        status: success ? 'success' : 'error',
        output: success
            ? '${_productName(profile)} confirmó la cuenta y guardó la credencial en el perfil.'
            : 'El acceso no fue confirmado.',
        profileId: profile.id,
        command: _isClaude(profile)
            ? 'nini-agents exec ${_spec(profile)} -- auth login'
            : 'codex app-server account/login/completed',
      );

  static bool _isClaude(Profile profile) => profile.toolKey == 'claude-cli';

  static String _productName(Profile profile) =>
      profileProviderOrNull(profile.toolKey)?.productName ?? 'Codex';

  static String _spec(Profile profile) =>
      profileProvider(profile.toolKey).profileSpec(profile.profileName);
}
