import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/accounts/data/codex_account_device_auth_gateway.dart';
import 'package:multi_cli_ai/features/accounts/data/process_account_device_auth_activity_recorder.dart';
import 'package:multi_cli_ai/features/accounts/domain/account_device_auth.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';

void main() {
  test(
    'gateway forwards the complete profile to the configured starter',
    () async {
      Profile? received;
      final session = _FakeSession();
      final gateway = CodexAccountDeviceAuthGateway.withStarter((
        profile,
      ) async {
        received = profile;
        return session;
      });

      expect(await gateway.start(_profile()), same(session));
      expect(received?.id, 'account');
      expect(received?.profileHome, '/profiles/account');
    },
  );

  test(
    'activity recorder preserves Device Auth log fields and order',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final recorder = ProcessAccountDeviceAuthActivityRecorder(
        ProcessRunner(database),
      );

      await recorder.recordStarted(_profile());
      await recorder.recordCompleted(_profile(), success: true);
      await recorder.recordCompleted(_profile(), success: false);

      final logs = await database.select(database.commandLogs).get();
      expect(logs.map((log) => log.command), [
        'codex app-server account/login/start',
        'codex app-server account/login/completed',
        'codex app-server account/login/completed',
      ]);
      expect(logs.map((log) => log.status), ['success', 'success', 'error']);
      expect(logs.first.summary, 'Vincular Account');
      expect(logs.first.profileId, 'account');
      expect(logs.last.output, 'El acceso no fue confirmado.');
    },
  );
}

final class _FakeSession implements AccountDeviceAuthSession {
  @override
  String get userCode => 'ABCD-EFGH';

  @override
  String get verificationUrl => 'https://example.com/device';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> waitForCompletion() async => true;
}

Profile _profile() => const Profile(
  id: 'account',
  toolKey: 'codex',
  profileName: 'account',
  commandName: 'codex-account',
  displayName: 'Account',
  profileHome: '/profiles/account',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: false,
  isAvailable: true,
  isFavorite: false,
);
