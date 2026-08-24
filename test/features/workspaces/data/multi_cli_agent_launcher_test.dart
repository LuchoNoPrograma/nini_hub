import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/profiles/data/multi_cli_gateway.dart';
import 'package:multi_cli_ai/features/profiles/domain/agent_profile.dart';
import 'package:multi_cli_ai/features/workspaces/data/multi_cli_agent_launcher.dart';
import 'package:multi_cli_ai/features/workspaces/domain/agent_launcher.dart';

void main() {
  late AppDatabase database;
  late Directory root;
  late Directory profileHome;
  late Directory workspaceDirectory;
  late AgentProfile profile;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('agent-launcher-data-');
    profileHome = Directory('${root.path}/profiles/team');
    workspaceDirectory = Directory('${root.path}/workspace');
    await profileHome.create(recursive: true);
    await workspaceDirectory.create();
    profile = AgentProfile(
      id: 'profile-id',
      toolKey: 'codex',
      profileName: 'team',
      displayName: 'Team',
      profileHome: profileHome.path,
      profileSource: 'multicli',
      hasAuthFile: true,
      isAvailable: true,
    );
    final now = DateTime.utc(2026, 8, 22);
    await database
        .into(database.cliProfiles)
        .insert(
          CliProfile(
            id: profile.id,
            toolKey: profile.toolKey,
            profileName: profile.profileName,
            commandName: 'codex-team',
            displayName: profile.displayName,
            profileHome: profile.profileHome,
            profileSource: profile.profileSource,
            profileType: 'full',
            hasAuthFile: true,
            isAvailable: true,
            isFavorite: false,
            createdAt: now,
            lastDiscoveredAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'forwards the pure profile through the existing terminal flow',
    () async {
      final runner = _RecordingProcessRunner(database);
      final launcher = MultiCliAgentLauncher(MultiCliGateway(database, runner));

      await launcher.launch(profile, workingDirectory: workspaceDirectory.path);

      expect(runner.executable, 'multi-cli');
      expect(runner.arguments, [
        'launch',
        'codex/team',
        '--',
        '-c',
        'tui.terminal_title=[]',
      ]);
      expect(runner.summary, 'Abrir Team');
      expect(runner.profileId, profile.id);
      expect(runner.workingDirectory, workspaceDirectory.absolute.path);
      expect(runner.title, 'team · workspace');
      final stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).getSingle();
      expect(stored.lastLaunchedAt, isNotNull);
    },
  );

  test(
    'legacy row and pure profile use the same terminal invocation',
    () async {
      final storedProfile = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).getSingle();
      final legacyRunner = _RecordingProcessRunner(database);
      final pureRunner = _RecordingProcessRunner(database);

      await MultiCliGateway(
        database,
        legacyRunner,
      ).launch(storedProfile, workingDirectory: workspaceDirectory.path);
      await MultiCliGateway(
        database,
        pureRunner,
      ).launchAgentProfile(profile, workingDirectory: workspaceDirectory.path);

      expect(pureRunner.invocation, legacyRunner.invocation);
    },
  );

  test('translates terminal failures without updating launch time', () async {
    final runner = _RecordingProcessRunner(
      database,
      failure: StateError('terminal failed'),
    );
    final launcher = MultiCliAgentLauncher(MultiCliGateway(database, runner));

    await expectLater(
      launcher.launch(profile, workingDirectory: workspaceDirectory.path),
      throwsA(isA<AgentLauncherFailure>()),
    );

    final stored = await (database.select(
      database.cliProfiles,
    )..where((row) => row.id.equals(profile.id))).getSingle();
    expect(stored.lastLaunchedAt, isNull);
  });
}

final class _RecordingProcessRunner extends ProcessRunner {
  _RecordingProcessRunner(super.database, {this.failure});

  final Object? failure;
  String? executable;
  List<String>? arguments;
  String? summary;
  String? profileId;
  String? workingDirectory;
  String? title;

  Map<String, Object?> get invocation => {
    'executable': executable,
    'arguments': arguments,
    'summary': summary,
    'profileId': profileId,
    'workingDirectory': workingDirectory,
    'title': title,
  };

  @override
  Future<void> startInTerminal({
    required String executable,
    required List<String> arguments,
    required String summary,
    String? profileId,
    String? workingDirectory,
    String? title,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.summary = summary;
    this.profileId = profileId;
    this.workingDirectory = workingDirectory;
    this.title = title;
    if (failure != null) throw failure!;
  }
}
