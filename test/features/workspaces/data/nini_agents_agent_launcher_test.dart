import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/domain/agent_profile.dart';
import 'package:nini_hub/features/workspaces/data/nini_agents_agent_launcher.dart';
import 'package:nini_hub/features/workspaces/domain/agent_launcher.dart';

void main() {
  late AppDatabase database;
  late Directory root;
  late Directory workspaceDirectory;
  late AgentProfile profile;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('nini-agent-launcher-');
    workspaceDirectory = Directory('${root.path}/workspace');
    await workspaceDirectory.create();
    profile = AgentProfile(
      id: 'profile-id',
      toolKey: 'codex',
      profileName: 'team',
      displayName: 'Team',
      profileHome: '${root.path}/profiles/codex/team',
      profileSource: 'multicli',
      hasAuthFile: true,
      isAvailable: true,
    );
    await _insertProfile(database, profile);
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test('launches a managed profile through Nini Agents', () async {
    final runner = _RecordingProcessRunner(database);
    final launcher = NiniAgentsAgentLauncher(database, runner);

    await launcher.launch(profile, workingDirectory: workspaceDirectory.path);

    expect(runner.executable, 'nini-agents');
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
    expect(runner.environment, {
      'MULTICLI_HOME': Directory('${root.path}/profiles').absolute.path,
      'NINI_AGENTS_HYPER_TITLE_LOCK': '1',
    });
    final stored = await _storedProfile(database, profile.id);
    expect(stored.lastLaunchedAt, isNotNull);
  });

  test('keeps the principal profile on its native executable', () async {
    final principal = AgentProfile(
      id: 'principal-id',
      toolKey: 'codex',
      profileName: 'principal',
      displayName: 'Codex principal',
      profileHome: '${root.path}/.codex',
      profileSource: 'default',
      hasAuthFile: true,
      isAvailable: true,
    );
    await _insertProfile(database, principal);
    final runner = _RecordingProcessRunner(database);

    await NiniAgentsAgentLauncher(
      database,
      runner,
    ).launch(principal, workingDirectory: workspaceDirectory.path);

    expect(runner.executable, 'codex');
    expect(runner.arguments, ['-c', 'tui.terminal_title=[]']);
    expect(runner.summary, 'Abrir Codex principal');
    expect(runner.environment, isNull);
    expect(
      (await _storedProfile(database, principal.id)).lastLaunchedAt,
      isNotNull,
    );
  });

  test('rejects a missing workspace before opening a terminal', () async {
    final runner = _RecordingProcessRunner(database);

    await expectLater(
      NiniAgentsAgentLauncher(
        database,
        runner,
      ).launch(profile, workingDirectory: '${root.path}/missing'),
      throwsA(isA<AgentLauncherFailure>()),
    );

    expect(runner.executable, isNull);
    expect((await _storedProfile(database, profile.id)).lastLaunchedAt, isNull);
  });

  test('translates terminal failures without updating launch time', () async {
    final runner = _RecordingProcessRunner(
      database,
      failure: StateError('terminal failed'),
    );

    await expectLater(
      NiniAgentsAgentLauncher(
        database,
        runner,
      ).launch(profile, workingDirectory: workspaceDirectory.path),
      throwsA(isA<AgentLauncherFailure>()),
    );

    expect((await _storedProfile(database, profile.id)).lastLaunchedAt, isNull);
  });
}

Future<void> _insertProfile(AppDatabase database, AgentProfile profile) async {
  final now = DateTime.utc(2026, 8, 22);
  await database
      .into(database.cliProfiles)
      .insert(
        CliProfile(
          id: profile.id,
          toolKey: profile.toolKey,
          profileName: profile.profileName,
          commandName: profile.profileSource == 'default'
              ? 'codex'
              : 'codex-${profile.profileName}',
          displayName: profile.displayName,
          profileHome: profile.profileHome,
          profileSource: profile.profileSource,
          profileType: profile.profileSource == 'default' ? 'base' : 'full',
          hasAuthFile: profile.hasAuthFile,
          isAvailable: profile.isAvailable,
          isFavorite: false,
          createdAt: now,
          lastDiscoveredAt: now,
        ),
      );
}

Future<CliProfile> _storedProfile(AppDatabase database, String profileId) =>
    (database.select(
      database.cliProfiles,
    )..where((row) => row.id.equals(profileId))).getSingle();

final class _RecordingProcessRunner extends ProcessRunner {
  _RecordingProcessRunner(super.database, {this.failure});

  final Object? failure;
  String? executable;
  List<String>? arguments;
  String? summary;
  String? profileId;
  String? workingDirectory;
  String? title;
  Map<String, String>? environment;

  @override
  Future<void> startInTerminal({
    required String executable,
    required List<String> arguments,
    required String summary,
    String? profileId,
    String? workingDirectory,
    String? title,
    Map<String, String>? environment,
  }) async {
    this.executable = executable;
    this.arguments = List.unmodifiable(arguments);
    this.summary = summary;
    this.profileId = profileId;
    this.workingDirectory = workingDirectory;
    this.title = title;
    this.environment = environment == null
        ? null
        : Map.unmodifiable(environment);
    if (failure != null) throw failure!;
  }
}
