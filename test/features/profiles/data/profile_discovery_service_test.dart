import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('expands a configured root from the desktop user home', () async {
    final temporaryHome = await Directory.systemTemp.createTemp(
      'nini-hub-profile-home-',
    );
    addTearDown(() => temporaryHome.delete(recursive: true));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final discovery = _FixedHomeDiscovery(database, temporaryHome.path);

    await database.saveSetting(
      'profiles_root_path',
      r'  ~/profiles/../MultiCliProfiles  ',
    );

    expect(
      await discovery.profilesRoot(),
      p.normalize(p.join(temporaryHome.path, 'MultiCliProfiles')),
    );
  });

  test(
    'synchronizes Nini Agents schema v1/v2 while preserving local metadata',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const root = '/synthetic/profiles';
      await database.saveSetting('profiles_root_path', root);
      final createdAt = DateTime.utc(2025, 1, 2);
      final lastDiscoveredAt = DateTime.utc(2025, 2, 3);
      final lastLaunchedAt = DateTime.utc(2025, 3, 4);
      await database
          .into(database.cliProfiles)
          .insert(
            CliProfile(
              id: 'stable-team-id',
              toolKey: 'codex',
              profileName: 'team',
              commandName: 'legacy-command',
              displayName: 'Equipo favorito',
              profileHome: '/old/codex/team',
              profileSource: 'multicli',
              profileType: 'full',
              hasAuthFile: true,
              isAvailable: false,
              isFavorite: true,
              createdAt: createdAt,
              lastDiscoveredAt: lastDiscoveredAt,
              lastLaunchedAt: lastLaunchedAt,
            ),
          );
      final runner = _FakeNiniAgentsRunner(database)
        ..profilesByRoot[root] = const [
          _ProfileSummary('codex', 'legacy', 'full', 1),
          _ProfileSummary('codex', 'team', 'shared', 2),
          _ProfileSummary('codex', 'vault', 'isolated', 2),
        ];
      final discovery = ProfileDiscoveryService(
        database,
        NiniAgentsReadClient(runner),
      );

      final profiles = await discovery.discoverProfiles();
      final stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals('stable-team-id'))).getSingle();

      expect(stored.profileHome, p.join(root, 'codex', 'team'));
      expect(stored.commandName, 'codex-team');
      expect(stored.displayName, 'Equipo favorito');
      expect(stored.profileType, 'shared');
      expect(stored.hasAuthFile, isTrue);
      expect(stored.isAvailable, isTrue);
      expect(stored.isFavorite, isTrue);
      expect(
        stored.createdAt.millisecondsSinceEpoch,
        createdAt.millisecondsSinceEpoch,
      );
      expect(stored.lastDiscoveredAt.isAfter(lastDiscoveredAt), isTrue);
      expect(
        stored.lastLaunchedAt?.millisecondsSinceEpoch,
        lastLaunchedAt.millisecondsSinceEpoch,
      );
      expect(profiles.first.id, 'stable-team-id');
      expect(
        profiles
            .singleWhere((profile) => profile.profileName == 'vault')
            .profileType,
        'isolated',
      );
      expect(
        profiles.where(
          (profile) =>
              profile.toolKey == 'codex' &&
              profile.profileSource == 'default' &&
              profile.profileType == 'base' &&
              profile.isAvailable,
        ),
        hasLength(1),
      );
      expect(runner.calls.map((call) => call.arguments[1]), ['list', 'tools']);
      expect(runner.calls.first.environment, {'MULTICLI_HOME': root});
    },
  );

  test(
    'serializes discovery and leaves the latest Nini snapshot active',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const oldRoot = '/synthetic/old-root';
      const newRoot = '/synthetic/new-root';
      final runner = _FakeNiniAgentsRunner(database)
        ..profilesByRoot[oldRoot] = const [
          _ProfileSummary('codex', 'old-profile', 'full', 2),
        ]
        ..profilesByRoot[newRoot] = const [
          _ProfileSummary('codex', 'new-profile', 'full', 2),
        ];
      final firstRoot = Completer<String>();
      final secondRoot = Completer<String>();
      final discovery = _ControlledRootDiscovery(
        database,
        NiniAgentsReadClient(runner),
        [firstRoot.future, secondRoot.future],
      );

      final first = discovery.discoverProfiles();
      await _pumpEventQueue();
      expect(discovery.rootReads, 1);
      final second = discovery.discoverProfiles();
      await _pumpEventQueue();
      expect(discovery.rootReads, 1);

      firstRoot.complete(oldRoot);
      await first;
      await _pumpEventQueue();
      expect(discovery.rootReads, 2);
      secondRoot.complete(newRoot);
      await second;

      final profiles = await database.select(database.cliProfiles).get();
      final oldProfile = profiles.singleWhere(
        (profile) => profile.profileName == 'old-profile',
      );
      final newProfile = profiles.singleWhere(
        (profile) => profile.profileName == 'new-profile',
      );
      expect(oldProfile.isAvailable, isFalse);
      expect(oldProfile.profileType, 'deactivated');
      expect(newProfile.isAvailable, isTrue);
    },
  );

  test('continues the discovery queue after an earlier root failure', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const newRoot = '/synthetic/new-root';
    final runner = _FakeNiniAgentsRunner(database)
      ..profilesByRoot[newRoot] = const [
        _ProfileSummary('codex', 'new-profile', 'full', 2),
      ];
    final firstRoot = Completer<String>();
    final discovery = _ControlledRootDiscovery(
      database,
      NiniAgentsReadClient(runner),
      [firstRoot.future, Future.value(newRoot)],
    );
    final failure = StateError('root failed');

    final first = discovery.discoverProfiles();
    final second = discovery.discoverProfiles();
    final firstExpectation = expectLater(first, throwsA(same(failure)));
    firstRoot.completeError(failure);
    await firstExpectation;
    final profiles = await second;

    expect(discovery.rootReads, 2);
    expect(
      profiles.any(
        (profile) =>
            profile.profileName == 'new-profile' && profile.isAvailable,
      ),
      isTrue,
    );
  });
}

final class _ControlledRootDiscovery extends ProfileDiscoveryService {
  _ControlledRootDiscovery(super.database, super.client, this.roots);

  final List<Future<String>> roots;
  int rootReads = 0;

  @override
  Future<String> profilesRoot() => roots[rootReads++];
}

final class _FixedHomeDiscovery extends ProfileDiscoveryService {
  _FixedHomeDiscovery(super.database, this.home) : super.test();

  final String home;

  @override
  String get userHome => home;
}

final class _ProfileSummary {
  const _ProfileSummary(this.tool, this.name, this.type, this.schemaVersion);

  final String tool;
  final String name;
  final String type;
  final int schemaVersion;
}

final class _FakeNiniAgentsRunner extends ProcessRunner {
  _FakeNiniAgentsRunner(super.database);

  final Map<String, List<_ProfileSummary>> profilesByRoot = {};
  final List<_RunCall> calls = [];

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
    bool recordActivity = true,
  }) async {
    calls.add(
      _RunCall(
        arguments: List.unmodifiable(arguments),
        environment: environment == null ? null : Map.unmodifiable(environment),
      ),
    );
    final command = arguments[1];
    final stdout = switch (command) {
      'list' || 'status' => _profilesEnvelope(
        command,
        profilesByRoot[environment?['MULTICLI_HOME']] ?? const [],
      ),
      'tools' => _success(
        'tools',
        '{"platform":"linux","tools":['
            '{"id":"claude-cli","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":false},'
            '{"id":"codex","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":true}'
            '],"count":2}',
      ),
      _ => throw StateError('Unexpected command: $command'),
    };
    final now = DateTime.utc(2026, 8, 24);
    return SafeProcessResult(
      exitCode: 0,
      stdout: stdout,
      stderr: '',
      startedAt: now,
      completedAt: now,
    );
  }
}

final class _RunCall {
  const _RunCall({required this.arguments, required this.environment});

  final List<String> arguments;
  final Map<String, String>? environment;
}

String _profilesEnvelope(String command, List<_ProfileSummary> profiles) {
  final items = profiles
      .map(
        (profile) =>
            '{"tool":"${profile.tool}","name":"${profile.name}",'
            '"type":"${profile.type}","schemaVersion":${profile.schemaVersion},'
            '"sizeBytes":1}',
      )
      .join(',');
  return _success(command, '{"profiles":[$items],"count":${profiles.length}}');
}

String _success(String command, String data) =>
    '{"schemaVersion":1,"command":"$command","ok":true,'
    '"data":$data,"error":null}';

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);
