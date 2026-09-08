import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';
import 'package:nini_hub/providers/codex/codex_client_runtime.dart';

typedef AccountDeviceAuthStarter =
    Future<AccountDeviceAuthSession> Function(
      Profile profile, {
      AccountAuthMethod method,
    });

final class CodexAccountDeviceAuthGateway implements AccountDeviceAuthGateway {
  CodexAccountDeviceAuthGateway(CodexClientRuntime runtime)
    : _start = ((profile, {method = AccountAuthMethod.deviceCode}) async {
        final session = await runtime.current.startDeviceAuth(
          profile,
          useBrowser: method == AccountAuthMethod.browser,
        );
        return _CodexAccountDeviceAuthSession(session);
      });

  CodexAccountDeviceAuthGateway.withStarter(this._start);

  final AccountDeviceAuthStarter _start;

  @override
  Future<AccountDeviceAuthSession> start(
    Profile profile, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  }) => _start(profile, method: method);
}

final class _CodexAccountDeviceAuthSession implements AccountDeviceAuthSession {
  const _CodexAccountDeviceAuthSession(this.session);

  final CodexDeviceAuthSession session;

  @override
  String get verificationUrl => session.verificationUrl;

  @override
  String get userCode => session.userCode;

  @override
  Future<bool> waitForCompletion() => session.waitForCompletion();

  @override
  Future<void> cancel() => session.cancel();

  @override
  Future<void> close() => session.close();
}
