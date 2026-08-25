import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/accounts/data/drift_account_repository.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';

void main() {
  test(
    'an undiscovered profile deactivates and restores when Nini lists it again',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const root = '/synthetic/profiles';
      await database.saveSetting('profiles_root_path', root);
      final now = DateTime.utc(2026, 8, 19);
      await database
          .into(database.cliProfiles)
          .insert(
            CliProfile(
              id: 'luis-id',
              toolKey: 'codex',
              profileName: 'luis',
              commandName: 'codex-luis',
              displayName: 'Luis',
              profileHome: '$root/codex/luis',
              profileSource: 'multicli',
              profileType: 'full',
              hasAuthFile: true,
              isAvailable: true,
              isFavorite: false,
              createdAt: now,
              lastDiscoveredAt: now,
            ),
          );
      final runner = _DiscoveryRunner(database);
      final discovery = ProfileDiscoveryService(
        database,
        NiniAgentsReadClient(runner),
      );

      var profiles = await discovery.discoverProfiles();
      var luis = profiles.singleWhere((profile) => profile.id == 'luis-id');
      final account = (await DriftAccountRepository(
        database,
      ).loadAll()).singleWhere((item) => item.profile.id == 'luis-id');

      expect(luis.profileType, 'deactivated');
      expect(luis.isAvailable, isFalse);
      expect(account.isDeactivated, isTrue);

      runner.profileAvailable = true;
      profiles = await discovery.discoverProfiles();
      luis = profiles.singleWhere((profile) => profile.id == 'luis-id');

      expect(luis.profileType, 'full');
      expect(luis.isAvailable, isTrue);
      expect(luis.hasAuthFile, isTrue);
    },
  );
}

final class _DiscoveryRunner extends ProcessRunner {
  _DiscoveryRunner(super.database);

  bool profileAvailable = false;

  @override
  Future<SafeProcessResult> run({
    required String executable,
    required List<String> arguments,
    required String summary,
    String? profileId,
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final command = arguments[1];
    final data = command == 'tools'
        ? '{"platform":"linux","tools":['
              '{"id":"codex","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":true}'
              '],"count":1}'
        : profileAvailable
        ? '{"profiles":['
              '{"tool":"codex","name":"luis","type":"full","schemaVersion":2,"sizeBytes":1}'
              '],"count":1}'
        : '{"profiles":[],"count":0}';
    final now = DateTime.utc(2026, 8, 24);
    return SafeProcessResult(
      exitCode: 0,
      stdout:
          '{"schemaVersion":1,"command":"$command","ok":true,'
          '"data":$data,"error":null}',
      stderr: '',
      startedAt: now,
      completedAt: now,
    );
  }
}
