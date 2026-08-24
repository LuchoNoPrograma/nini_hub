import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_models.dart';
import 'package:multi_cli_ai/features/profiles/data/profile_discovery_service.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_failure.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_client.dart';
import 'package:multi_cli_ai/providers/codex/codex_client_runtime.dart';

void main() {
  test('usage refresh rediscovers profiles before starting Codex', () async {
    final root = await Directory.systemTemp.createTemp(
      'multicli-ai-refresh-safety-',
    );
    addTearDown(() => root.delete(recursive: true));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.saveSetting('profiles_root_path', root.path);

    final staleHome = '${root.path}/codex/willy';
    final now = DateTime.now().toUtc();
    await database
        .into(database.cliProfiles)
        .insert(
          CliProfile(
            id: 'willy',
            toolKey: 'codex',
            profileName: 'willy',
            commandName: 'codex-willy',
            displayName: 'Willy',
            profileHome: staleHome,
            profileSource: 'multicli',
            profileType: 'full',
            hasAuthFile: true,
            isAvailable: true,
            isFavorite: false,
            createdAt: now,
            lastDiscoveredAt: now,
          ),
        );

    final runner = ProcessRunner(database);
    final client = _RecordingCodexClient();
    final codexRuntime = CodexClientRuntime(initialClient: client);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        processRunnerProvider.overrideWithValue(runner),
        codexClientRuntimeProvider.overrideWithValue(codexRuntime),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(usageControllerProvider.notifier);

    expect(await controller.refreshAll(), isTrue);

    expect(client.profileHomes, isNot(contains(staleHome)));
    expect(
      (await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals('willy'))).getSingle()).isAvailable,
      isFalse,
    );
    expect(await controller.refreshOne('willy'), isFalse);
    expect(
      container.read(usageControllerProvider).failureForProfile('willy')?.cause,
      isA<UsageProfileUnavailableFailure>(),
    );
    expect(client.profileHomes, isNot(contains(staleHome)));
  });

  test('refresh all reads concurrency from composed settings', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.saveSetting('concurrency', '4');
    final now = DateTime.now().toUtc();
    await database.batch((batch) {
      for (var index = 0; index < 6; index++) {
        batch.insert(
          database.cliProfiles,
          CliProfile(
            id: 'profile-$index',
            toolKey: 'codex',
            profileName: 'profile-$index',
            commandName: 'codex-profile-$index',
            displayName: 'Profile $index',
            profileHome: '/tmp/profile-$index',
            profileSource: 'multicli',
            profileType: 'full',
            hasAuthFile: true,
            isAvailable: true,
            isFavorite: false,
            createdAt: now,
            lastDiscoveredAt: now,
          ),
        );
      }
    });
    final runner = ProcessRunner(database);
    final client = _GatedCodexClient();
    final codexRuntime = CodexClientRuntime(
      initialClient: client,
      clientFactory: (_) => client,
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        processRunnerProvider.overrideWithValue(runner),
        profileDiscoveryProvider.overrideWithValue(
          _StaticProfileDiscovery(database),
        ),
        codexClientRuntimeProvider.overrideWithValue(codexRuntime),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(settingsBootstrapProvider.future), isTrue);
    expect(
      container.read(settingsControllerProvider).preferences.concurrency,
      4,
    );
    final refresh = container
        .read(usageControllerProvider.notifier)
        .refreshAll();
    try {
      for (var attempt = 0; attempt < 100 && client.maxActive < 4; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(client.maxActive, 4);
    } finally {
      client.release.complete();
    }

    expect(await refresh, isTrue);
  });
}

class _RecordingCodexClient extends CodexAppServerClient {
  final List<String> profileHomes = [];

  @override
  Future<CodexRefreshResult> refresh(String profileHome) async {
    profileHomes.add(profileHome);
    return _result();
  }
}

final class _GatedCodexClient extends _RecordingCodexClient {
  final Completer<void> release = Completer<void>();
  int active = 0;
  int maxActive = 0;

  @override
  Future<CodexRefreshResult> refresh(String profileHome) async {
    profileHomes.add(profileHome);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await release.future;
      return _result();
    } finally {
      active--;
    }
  }
}

final class _StaticProfileDiscovery extends ProfileDiscoveryService {
  _StaticProfileDiscovery(super.database);

  @override
  Future<List<CliProfile>> discoverProfiles() =>
      database.select(database.cliProfiles).get();
}

CodexRefreshResult _result() {
  final now = DateTime.now().toUtc();
  return CodexRefreshResult(
    state: UsageCheckState.success,
    startedAt: now,
    completedAt: now,
  );
}
