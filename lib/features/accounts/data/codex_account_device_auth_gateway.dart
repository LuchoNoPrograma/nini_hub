import 'package:multi_cli_ai/features/accounts/domain/account_device_auth.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_client.dart';
import 'package:multi_cli_ai/providers/codex/codex_client_runtime.dart';

typedef AccountDeviceAuthStarter =
    Future<AccountDeviceAuthSession> Function(Profile profile);

final class CodexAccountDeviceAuthGateway implements AccountDeviceAuthGateway {
  CodexAccountDeviceAuthGateway(CodexClientRuntime runtime)
    : _start = ((profile) async {
        final session = await runtime.current.startDeviceAuth(
          profile.profileHome,
        );
        return _CodexAccountDeviceAuthSession(session);
      });

  CodexAccountDeviceAuthGateway.withStarter(this._start);

  final AccountDeviceAuthStarter _start;

  @override
  Future<AccountDeviceAuthSession> start(Profile profile) => _start(profile);
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
