import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/providers/claude/claude_auth_login_client.dart';

typedef ClaudeAccountAuthStarter =
    Future<AccountAuthorizationCodeSession> Function(Profile profile);

final class ClaudeAccountDeviceAuthGateway implements AccountDeviceAuthGateway {
  ClaudeAccountDeviceAuthGateway(ClaudeAuthLoginClient client)
    : _start = ((profile) async =>
          _ClaudeAccountAuthSession(await client.start(profile)));

  ClaudeAccountDeviceAuthGateway.withStarter(this._start);

  final ClaudeAccountAuthStarter _start;

  // Claude has a single official flow: browser first, pasted code as fallback.
  @override
  Future<AccountDeviceAuthSession> start(
    Profile profile, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  }) => _start(profile);
}

final class _ClaudeAccountAuthSession
    implements AccountAuthorizationCodeSession {
  const _ClaudeAccountAuthSession(this.session);

  final ClaudeAuthLoginSession session;

  @override
  String get verificationUrl => session.verificationUrl;

  @override
  String get userCode => '';

  @override
  Future<void> submitAuthorizationCode(String code) => session.submitCode(code);

  @override
  Future<bool> waitForCompletion() => session.waitForCompletion();

  @override
  Future<void> cancel() => session.cancel();

  @override
  Future<void> close() => session.close();
}
