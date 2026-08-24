import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/profiles/data/multi_cli_gateway.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late _RecordingProcessRunner runner;
  late MultiCliGateway gateway;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    runner = _RecordingProcessRunner(database);
    gateway = MultiCliGateway(database, runner);
  });

  tearDown(() => database.close());

  test('create keeps the legacy Multi CLI arguments and timeout', () async {
    await gateway.createProfile(
      toolKey: 'codex',
      profileName: ProfileName(' team_02 '),
      setupMode: ProfileSetupMode.shared,
      seedFromBase: false,
    );

    final call = runner.calls.single;
    expect(call.executable, 'multi-cli');
    expect(call.arguments, ['new', 'codex/team_02', '--shared', '--no-seed']);
    expect(call.summary, 'Crear perfil Codex team_02');
    expect(call.timeout, const Duration(minutes: 2));
    expect(call.profileId, isNull);
    expect(call.stdinText, isNull);
    expect(await database.select(database.cliProfiles).get(), isEmpty);
  });

  test('create exposes a failed process without writing a profile', () async {
    runner.result = _processResult(exitCode: 2, stderr: 'creation failed');

    await expectLater(
      gateway.createProfile(
        toolKey: 'claude-cli',
        profileName: ProfileName('research'),
        setupMode: ProfileSetupMode.cli,
        seedFromBase: true,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'creation failed',
        ),
      ),
    );

    final call = runner.calls.single;
    expect(call.arguments, ['new', 'claude-cli/research', '--cli']);
    expect(await database.select(database.cliProfiles).get(), isEmpty);
  });

  test(
    'rename runs Multi CLI before updating the persisted identity',
    () async {
      final profile = await _insertProfile(database);

      await gateway.renameProfile(
        _domainProfile(profile),
        ProfileName('new_team'),
      );

      final call = runner.calls.single;
      expect(call.executable, 'multi-cli');
      expect(call.arguments, ['rename', 'codex/team', 'codex/new_team']);
      expect(call.profileId, profile.id);
      expect(call.timeout, const Duration(minutes: 2));
      final stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).getSingle();
      expect(stored.profileName, 'new_team');
      expect(stored.commandName, 'codex-new_team');
      expect(
        stored.profileHome,
        p.join(p.dirname(profile.profileHome), 'new_team'),
      );
      expect(stored.displayName, profile.displayName);
      expect(stored.isFavorite, profile.isFavorite);
      expect(stored.createdAt, profile.createdAt);
      expect(stored.lastDiscoveredAt.isAfter(profile.lastDiscoveredAt), isTrue);
    },
  );

  test('rename leaves SQLite unchanged when Multi CLI fails', () async {
    final profile = await _insertProfile(database);
    runner.result = _processResult(exitCode: 1, stderr: 'rename failed');

    await expectLater(
      gateway.renameProfile(_domainProfile(profile), ProfileName('new_team')),
      throwsA(isA<StateError>()),
    );

    final stored = await (database.select(
      database.cliProfiles,
    )..where((row) => row.id.equals(profile.id))).getSingle();
    expect(stored, profile);
  });

  test('delete confirms Multi CLI and cascades profile-owned rows', () async {
    final profile = await _insertProfile(database);
    await database
        .into(database.profileMetadatas)
        .insert(
          ProfileMetadatasCompanion.insert(
            profileId: profile.id,
            updatedAt: DateTime.utc(2026, 8, 22),
          ),
        );
    await database
        .into(database.usageChecks)
        .insert(
          UsageChecksCompanion.insert(
            id: 'check-id',
            profileId: profile.id,
            status: 'success',
            startedAt: DateTime.utc(2026, 8, 22),
          ),
        );

    await gateway.deleteProfile(_domainProfile(profile));

    final call = runner.calls.single;
    expect(call.executable, 'multi-cli');
    expect(call.arguments, ['delete', 'codex/team']);
    expect(call.profileId, profile.id);
    expect(call.stdinText, 'y\n');
    expect(call.timeout, const Duration(minutes: 2));
    expect(await database.select(database.cliProfiles).get(), isEmpty);
    expect(await database.select(database.profileMetadatas).get(), isEmpty);
    expect(await database.select(database.usageChecks).get(), isEmpty);
  });

  test('delete preserves SQLite when Multi CLI fails', () async {
    final profile = await _insertProfile(database);
    runner.result = _processResult(exitCode: 1, stderr: 'delete failed');

    await expectLater(
      gateway.deleteProfile(_domainProfile(profile)),
      throwsA(isA<StateError>()),
    );

    expect(
      await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).getSingle(),
      profile,
    );
  });

  test(
    'display data trims aliases and falls back to the physical name',
    () async {
      final profile = await _insertProfile(database);

      await gateway.saveDisplayData(
        profile: profile,
        displayName: '  Equipo  ',
        favorite: true,
      );
      var stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).getSingle();
      expect(stored.displayName, 'Equipo');
      expect(stored.isFavorite, isTrue);

      await gateway.saveDisplayData(
        profile: stored,
        displayName: '   ',
        favorite: false,
      );
      stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).getSingle();
      expect(stored.displayName, profile.profileName);
      expect(stored.isFavorite, isFalse);
    },
  );
}

Future<CliProfile> _insertProfile(AppDatabase database) async {
  final profile = CliProfile(
    id: 'profile-id',
    toolKey: 'codex',
    profileName: 'team',
    commandName: 'codex-team',
    displayName: 'Team',
    profileHome: '/profiles/codex/team',
    profileSource: 'multicli',
    profileType: 'full',
    hasAuthFile: true,
    isAvailable: true,
    isFavorite: true,
    createdAt: DateTime.utc(2025, 1, 2),
    lastDiscoveredAt: DateTime.utc(2025, 2, 3),
    lastLaunchedAt: DateTime.utc(2025, 3, 4),
  );
  await database.into(database.cliProfiles).insert(profile);
  return (database.select(
    database.cliProfiles,
  )..where((row) => row.id.equals(profile.id))).getSingle();
}

Profile _domainProfile(CliProfile row) => Profile(
  id: row.id,
  toolKey: row.toolKey,
  profileName: row.profileName,
  commandName: row.commandName,
  displayName: row.displayName,
  profileHome: row.profileHome,
  source: row.profileSource == 'multicli'
      ? ProfileSource.multiCli
      : ProfileSource.defaultProfile,
  kind: ProfileKind.full,
  hasAuthFile: row.hasAuthFile,
  isAvailable: row.isAvailable,
  isFavorite: row.isFavorite,
);

SafeProcessResult _processResult({
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
}) => SafeProcessResult(
  exitCode: exitCode,
  stdout: stdout,
  stderr: stderr,
  startedAt: DateTime.utc(2026, 8, 22),
  completedAt: DateTime.utc(2026, 8, 22),
);

final class _RecordingProcessRunner extends ProcessRunner {
  _RecordingProcessRunner(super.database);

  final List<_RunCall> calls = [];
  SafeProcessResult result = _processResult();

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
    calls.add(
      _RunCall(
        executable: executable,
        arguments: List.unmodifiable(arguments),
        summary: summary,
        profileId: profileId,
        stdinText: stdinText,
        timeout: timeout,
      ),
    );
    return result;
  }
}

final class _RunCall {
  const _RunCall({
    required this.executable,
    required this.arguments,
    required this.summary,
    required this.profileId,
    required this.stdinText,
    required this.timeout,
  });

  final String executable;
  final List<String> arguments;
  final String summary;
  final String? profileId;
  final String? stdinText;
  final Duration timeout;
}
