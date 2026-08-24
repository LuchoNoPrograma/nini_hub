import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/profiles/data/multi_cli_gateway.dart';
import 'package:multi_cli_ai/features/profiles/data/multi_cli_profile_lifecycle.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late _RecordingProcessRunner runner;
  late MultiCliProfileLifecycle lifecycle;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    runner = _RecordingProcessRunner(database);
    lifecycle = MultiCliProfileLifecycle(MultiCliGateway(database, runner));
  });

  tearDown(() => database.close());

  test('maps setup modes and seed flag to legacy create arguments', () async {
    await lifecycle.create(
      toolKey: 'codex',
      profileName: ProfileName('full'),
      setupMode: ProfileSetupMode.full,
      seedFromBase: false,
    );
    await lifecycle.create(
      toolKey: 'codex',
      profileName: ProfileName('shared'),
      setupMode: ProfileSetupMode.shared,
      seedFromBase: false,
    );
    await lifecycle.create(
      toolKey: 'codex',
      profileName: ProfileName('cli'),
      setupMode: ProfileSetupMode.cli,
      seedFromBase: true,
    );

    expect(runner.calls.map((call) => call.arguments), [
      ['new', 'codex/full', '--no-seed'],
      ['new', 'codex/shared', '--shared', '--no-seed'],
      ['new', 'codex/cli', '--cli'],
    ]);
    expect(
      runner.calls.map((call) => call.timeout),
      everyElement(const Duration(minutes: 2)),
    );
    expect(await database.select(database.cliProfiles).get(), isEmpty);
  });

  test('renames through Multi CLI before updating the persisted row', () async {
    final row = _row();
    await database.into(database.cliProfiles).insert(row);

    await lifecycle.rename(
      profile: _profile(),
      profileName: ProfileName('new_team'),
    );

    final call = runner.calls.single;
    expect(call.arguments, ['rename', 'codex/team', 'codex/new_team']);
    expect(call.profileId, row.id);
    final stored = await (database.select(
      database.cliProfiles,
    )..where((item) => item.id.equals(row.id))).getSingle();
    expect(stored.profileName, 'new_team');
    expect(stored.commandName, 'codex-new_team');
    expect(stored.profileHome, p.join(p.dirname(row.profileHome), 'new_team'));
    expect(
      stored.createdAt.millisecondsSinceEpoch,
      row.createdAt.millisecondsSinceEpoch,
    );
    expect(
      stored.lastLaunchedAt?.millisecondsSinceEpoch,
      row.lastLaunchedAt?.millisecondsSinceEpoch,
    );
    expect(stored.lastDiscoveredAt.isAfter(row.lastDiscoveredAt), isTrue);
  });

  test('deletes through Multi CLI with confirmation before SQLite', () async {
    final row = _row();
    await database.into(database.cliProfiles).insert(row);

    await lifecycle.delete(_profile());

    final call = runner.calls.single;
    expect(call.arguments, ['delete', 'codex/team']);
    expect(call.profileId, row.id);
    expect(call.stdinText, 'y\n');
    expect(call.timeout, const Duration(minutes: 2));
    expect(await database.select(database.cliProfiles).get(), isEmpty);
  });

  test('keeps SQLite unchanged when the process fails', () async {
    final row = _row();
    await database.into(database.cliProfiles).insert(row);
    runner.result = _result(exitCode: 1, stderr: 'failed');

    await expectLater(
      lifecycle.rename(
        profile: _profile(),
        profileName: ProfileName('new_team'),
      ),
      throwsA(isA<StateError>()),
    );

    final stored = await (database.select(
      database.cliProfiles,
    )..where((item) => item.id.equals(row.id))).getSingle();
    expect(stored.id, row.id);
    expect(stored.profileName, row.profileName);
    expect(stored.commandName, row.commandName);
    expect(stored.profileHome, row.profileHome);
    expect(
      stored.createdAt.millisecondsSinceEpoch,
      row.createdAt.millisecondsSinceEpoch,
    );
    expect(
      stored.lastDiscoveredAt.millisecondsSinceEpoch,
      row.lastDiscoveredAt.millisecondsSinceEpoch,
    );
    expect(
      stored.lastLaunchedAt?.millisecondsSinceEpoch,
      row.lastLaunchedAt?.millisecondsSinceEpoch,
    );
  });
}

Profile _profile() => const Profile(
  id: 'profile-id',
  toolKey: 'codex',
  profileName: 'team',
  commandName: 'codex-team',
  displayName: 'Team',
  profileHome: '/profiles/codex/team',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: true,
);

CliProfile _row() => CliProfile(
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

SafeProcessResult _result({
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
  SafeProcessResult result = _result();

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
        arguments: List.unmodifiable(arguments),
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
    required this.arguments,
    required this.profileId,
    required this.stdinText,
    required this.timeout,
  });

  final List<String> arguments;
  final String? profileId;
  final String? stdinText;
  final Duration timeout;
}
