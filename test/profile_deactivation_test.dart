import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/accounts/data/drift_account_repository.dart';
import 'package:multi_cli_ai/features/profiles/data/profile_discovery_service.dart';

void main() {
  test(
    'an undiscovered profile deactivates and restores when it reappears',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'multi-cli-ai-deactivation-',
      );
      addTearDown(() => root.delete(recursive: true));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.saveSetting('profiles_root_path', root.path);
      final activeHome = Directory('${root.path}/codex/luis');
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
              profileHome: activeHome.path,
              profileSource: 'multicli',
              profileType: 'full',
              hasAuthFile: true,
              isAvailable: true,
              isFavorite: false,
              createdAt: now,
              lastDiscoveredAt: now,
            ),
          );
      final discovery = ProfileDiscoveryService(database);

      var profiles = await discovery.discoverProfiles();
      var luis = profiles.singleWhere((profile) => profile.id == 'luis-id');
      final account = (await DriftAccountRepository(
        database,
      ).loadAll()).singleWhere((item) => item.profile.id == 'luis-id');

      expect(luis.profileType, 'deactivated');
      expect(luis.isAvailable, isFalse);
      expect(luis.profileHome, activeHome.path);
      expect(account.isDeactivated, isTrue);

      await activeHome.create(recursive: true);
      await File('${activeHome.path}/auth.json').writeAsString('{}');
      profiles = await discovery.discoverProfiles();
      luis = profiles.singleWhere((profile) => profile.id == 'luis-id');

      expect(luis.profileType, 'full');
      expect(luis.isAvailable, isTrue);
      expect(luis.hasAuthFile, isTrue);
    },
  );
}
