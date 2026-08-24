import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/profiles/data/profile_discovery_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('expands a configured root from the desktop user home', () async {
    final temporaryHome = await Directory.systemTemp.createTemp(
      'multi-cli-ai-profile-home-',
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
    'preserves profile identity and display data while refreshing filesystem fields',
    () async {
      final temporaryHome = await Directory.systemTemp.createTemp(
        'multi-cli-ai-profile-identity-',
      );
      addTearDown(() => temporaryHome.delete(recursive: true));
      final profilesRoot = Directory(
        p.join(temporaryHome.path, 'MultiCliProfiles'),
      );
      final profileHome = Directory(p.join(profilesRoot.path, 'codex', 'team'));
      await profileHome.create(recursive: true);
      await File(p.join(profileHome.path, '.shared')).writeAsString('');
      await File(p.join(profileHome.path, '.cli')).writeAsString('');
      await File(p.join(profileHome.path, 'auth.json')).writeAsString('{}');
      await Directory(
        p.join(profilesRoot.path, 'codex', '.hidden'),
      ).create(recursive: true);

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.saveSetting('profiles_root_path', profilesRoot.path);
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
              profileHome: p.join(temporaryHome.path, 'old', 'team'),
              profileSource: 'multicli',
              profileType: 'full',
              hasAuthFile: false,
              isAvailable: false,
              isFavorite: true,
              createdAt: createdAt,
              lastDiscoveredAt: lastDiscoveredAt,
              lastLaunchedAt: lastLaunchedAt,
            ),
          );

      final profiles = await _FixedHomeDiscovery(
        database,
        temporaryHome.path,
      ).discoverProfiles();
      final stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals('stable-team-id'))).getSingle();

      expect(stored.profileHome, p.normalize(p.absolute(profileHome.path)));
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
        profiles.where((profile) => profile.profileName == '.hidden'),
        isEmpty,
      );
      expect(
        profiles.where(
          (profile) =>
              profile.toolKey == 'codex' &&
              profile.profileSource == 'default' &&
              profile.profileType == 'base',
        ),
        hasLength(1),
      );
      expect(
        profiles.where(
          (profile) =>
              profile.toolKey == 'claude-cli' &&
              profile.profileSource == 'default',
        ),
        isEmpty,
      );
    },
  );

  test('serializes discovery and leaves the latest root active', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final firstRoot = Completer<String>();
    final secondRoot = Completer<String>();
    final discovery = _ControlledRootDiscovery(fixture.database, [
      firstRoot.future,
      secondRoot.future,
    ]);

    final first = discovery.discoverProfiles();
    await _pumpEventQueue();
    expect(discovery.rootReads, 1);

    final second = discovery.discoverProfiles();
    await _pumpEventQueue();
    expect(discovery.rootReads, 1);

    firstRoot.complete(fixture.oldRoot.path);
    await first;
    await _pumpEventQueue();
    expect(discovery.rootReads, 2);

    secondRoot.complete(fixture.newRoot.path);
    await second;

    final profiles = await fixture.database
        .select(fixture.database.cliProfiles)
        .get();
    final oldProfile = profiles.singleWhere(
      (profile) =>
          profile.profileSource == 'multicli' &&
          profile.profileName == 'old-profile',
    );
    final newProfile = profiles.singleWhere(
      (profile) =>
          profile.profileSource == 'multicli' &&
          profile.profileName == 'new-profile',
    );
    expect(oldProfile.isAvailable, isFalse);
    expect(oldProfile.profileType, 'deactivated');
    expect(newProfile.isAvailable, isTrue);
    expect(newProfile.profileType, 'full');
  });

  test('continues the discovery queue after an earlier failure', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final firstRoot = Completer<String>();
    final discovery = _ControlledRootDiscovery(fixture.database, [
      firstRoot.future,
      Future<String>.value(fixture.newRoot.path),
    ]);
    final failure = StateError('root failed');

    final first = discovery.discoverProfiles();
    final second = discovery.discoverProfiles();
    final firstExpectation = expectLater(first, throwsA(same(failure)));
    await _pumpEventQueue();
    expect(discovery.rootReads, 1);

    firstRoot.completeError(failure);
    await firstExpectation;
    final profiles = await second;

    expect(discovery.rootReads, 2);
    expect(
      profiles.any(
        (profile) =>
            profile.profileSource == 'multicli' &&
            profile.profileName == 'new-profile' &&
            profile.isAvailable,
      ),
      isTrue,
    );
  });
}

final class _ControlledRootDiscovery extends ProfileDiscoveryService {
  _ControlledRootDiscovery(super.database, this.roots);

  final List<Future<String>> roots;
  int rootReads = 0;

  @override
  Future<String> profilesRoot() => roots[rootReads++];
}

final class _FixedHomeDiscovery extends ProfileDiscoveryService {
  _FixedHomeDiscovery(super.database, this.home);

  final String home;

  @override
  String get userHome => home;
}

final class _Fixture {
  const _Fixture({
    required this.database,
    required this.temporaryRoot,
    required this.oldRoot,
    required this.newRoot,
  });

  static Future<_Fixture> create() async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'multi-cli-ai-discovery-queue-',
    );
    final oldRoot = Directory(p.join(temporaryRoot.path, 'old-root'));
    final newRoot = Directory(p.join(temporaryRoot.path, 'new-root'));
    await Directory(
      p.join(oldRoot.path, 'codex', 'old-profile'),
    ).create(recursive: true);
    await Directory(
      p.join(newRoot.path, 'codex', 'new-profile'),
    ).create(recursive: true);
    return _Fixture(
      database: AppDatabase(NativeDatabase.memory()),
      temporaryRoot: temporaryRoot,
      oldRoot: oldRoot,
      newRoot: newRoot,
    );
  }

  final AppDatabase database;
  final Directory temporaryRoot;
  final Directory oldRoot;
  final Directory newRoot;

  Future<void> dispose() async {
    await database.close();
    await temporaryRoot.delete(recursive: true);
  }
}

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);
