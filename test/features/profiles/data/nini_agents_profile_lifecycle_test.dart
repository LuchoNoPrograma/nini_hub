import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/data/nini_agents_profile_lifecycle.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late _StatefulNiniAgentsRunner runner;
  late NiniAgentsProfileLifecycle lifecycle;
  const root = '/synthetic/profiles';

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.saveSetting('profiles_root_path', root);
    runner = _StatefulNiniAgentsRunner(database);
    final client = NiniAgentsReadClient(runner);
    final discovery = ProfileDiscoveryService(database, client);
    lifecycle = NiniAgentsProfileLifecycle(database, client, discovery);
  });

  tearDown(() => database.close());

  test('maps setup modes and seed flag to Nini Agents JSON', () async {
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
      ['--json', 'new', 'codex/full', '--no-seed'],
      ['--json', 'new', 'codex/shared', '--shared', '--no-seed'],
      ['--json', 'new', 'codex/cli', '--cli'],
    ]);
    expect(
      runner.calls.map((call) => call.timeout),
      everyElement(const Duration(minutes: 2)),
    );
    expect(
      runner.calls.map((call) => call.environment),
      everyElement({'MULTICLI_HOME': root}),
    );
    expect(await database.select(database.cliProfiles).get(), isEmpty);
  });

  test(
    'renames through Nini Agents before updating persisted identity',
    () async {
      final row = _row();
      await database.into(database.cliProfiles).insert(row);
      runner.profiles.add(const _Summary('codex', 'team', 'full'));

      await lifecycle.rename(
        profile: _profile(),
        profileName: ProfileName('new-team'),
      );

      expect(runner.calls.single.arguments, [
        '--json',
        'rename',
        'codex/team',
        'codex/new-team',
      ]);
      expect(runner.calls.single.profileId, row.id);
      final stored = await (database.select(
        database.cliProfiles,
      )..where((item) => item.id.equals(row.id))).getSingle();
      expect(stored.profileName, 'new-team');
      expect(stored.commandName, 'codex-new-team');
      expect(stored.profileHome, p.join(root, 'codex', 'new-team'));
      expect(
        stored.createdAt.millisecondsSinceEpoch,
        row.createdAt.millisecondsSinceEpoch,
      );
      expect(
        stored.lastLaunchedAt?.millisecondsSinceEpoch,
        row.lastLaunchedAt?.millisecondsSinceEpoch,
      );
      expect(stored.lastDiscoveredAt.isAfter(row.lastDiscoveredAt), isTrue);
    },
  );

  test(
    'deletes with exact confirmation before cascading SQLite rows',
    () async {
      final row = _row();
      await database.into(database.cliProfiles).insert(row);
      await database
          .into(database.profileMetadatas)
          .insert(
            ProfileMetadatasCompanion.insert(
              profileId: row.id,
              updatedAt: DateTime.utc(2026, 8, 24),
            ),
          );
      runner.profiles.add(const _Summary('codex', 'team', 'full'));

      await lifecycle.delete(_profile());

      expect(runner.calls.single.arguments, [
        '--json',
        'delete',
        'codex/team',
        '--confirm',
        'codex/team',
      ]);
      expect(runner.calls.single.stdinText, isNull);
      expect(await database.select(database.cliProfiles).get(), isEmpty);
      expect(await database.select(database.profileMetadatas).get(), isEmpty);
    },
  );

  test('maps a not-applied conflict without changing SQLite', () async {
    final row = _row();
    await database.into(database.cliProfiles).insert(row);
    runner.profiles.add(const _Summary('codex', 'team', 'full'));
    runner.failure = const _MutationFailure(
      command: 'rename',
      code: 'profile_exists',
      state: 'not_applied',
    );

    await expectLater(
      lifecycle.rename(
        profile: _profile(),
        profileName: ProfileName('new-team'),
      ),
      throwsA(
        isA<ProfileMutationRejectedFailure>().having(
          (failure) => failure.reason,
          'reason',
          ProfileMutationRejectionReason.alreadyExists,
        ),
      ),
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
    expect(runner.calls, hasLength(1));
  });

  test('reconciles a partially applied rename through status', () async {
    final row = _row();
    await database.into(database.cliProfiles).insert(row);
    runner.profiles.add(const _Summary('codex', 'team', 'full'));
    runner.failure = const _MutationFailure(
      command: 'rename',
      code: 'operation_failed',
      state: 'partially_applied',
      applyBeforeFailure: true,
    );

    await expectLater(
      lifecycle.rename(
        profile: _profile(),
        profileName: ProfileName('new-team'),
      ),
      throwsA(
        isA<ProfileMutationAppliedFailure>().having(
          (failure) => failure.operation,
          'operation',
          ProfileOperation.rename,
        ),
      ),
    );

    final stored = await (database.select(
      database.cliProfiles,
    )..where((item) => item.id.equals(row.id))).getSingle();
    expect(stored.profileName, 'new-team');
    expect(stored.profileType, 'full');
    expect(stored.isAvailable, isTrue);
    expect(runner.calls.map((call) => call.arguments[1]), [
      'rename',
      'status',
      'tools',
    ]);
  });

  test(
    'keeps a partially deleted profile when status still lists it',
    () async {
      final row = _row();
      await database.into(database.cliProfiles).insert(row);
      runner.profiles.add(const _Summary('codex', 'team', 'full'));
      runner.failure = const _MutationFailure(
        command: 'delete',
        code: 'operation_failed',
        state: 'partially_applied',
      );

      await expectLater(
        lifecycle.delete(_profile()),
        throwsA(isA<ProfileMutationAppliedFailure>()),
      );

      final stored = await (database.select(
        database.cliProfiles,
      )..where((item) => item.id.equals(row.id))).getSingle();
      expect(stored.profileName, 'team');
      expect(stored.isAvailable, isTrue);
      expect(runner.calls.map((call) => call.arguments[1]), [
        'delete',
        'status',
        'tools',
      ]);
    },
  );
}

Profile _profile() => const Profile(
  id: 'profile-id',
  toolKey: 'codex',
  profileName: 'team',
  commandName: 'codex-team',
  displayName: 'Team',
  profileHome: '/synthetic/profiles/codex/team',
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
  profileHome: '/synthetic/profiles/codex/team',
  profileSource: 'multicli',
  profileType: 'full',
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: true,
  createdAt: DateTime.utc(2025, 1, 2),
  lastDiscoveredAt: DateTime.utc(2025, 2, 3),
  lastLaunchedAt: DateTime.utc(2025, 3, 4),
);

final class _Summary {
  const _Summary(this.tool, this.name, this.type);

  final String tool;
  final String name;
  final String type;
}

final class _MutationFailure {
  const _MutationFailure({
    required this.command,
    required this.code,
    required this.state,
    this.applyBeforeFailure = false,
  });

  final String command;
  final String code;
  final String state;
  final bool applyBeforeFailure;
}

final class _StatefulNiniAgentsRunner extends ProcessRunner {
  _StatefulNiniAgentsRunner(super.database);

  final List<_Summary> profiles = [];
  final List<_RunCall> calls = [];
  _MutationFailure? failure;

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
        environment: environment == null ? null : Map.unmodifiable(environment),
        stdinText: stdinText,
        timeout: timeout,
      ),
    );
    final command = arguments[1];
    final configuredFailure = failure;
    if (configuredFailure?.command == command) {
      if (configuredFailure!.applyBeforeFailure) {
        _applyMutation(command, arguments);
      }
      return _result(
        exitCode: configuredFailure.state == 'not_applied' ? 2 : 6,
        stdout:
            '{"schemaVersion":1,"command":"$command","ok":false,'
            '"data":null,"error":{"code":"${configuredFailure.code}",'
            '"message":"Synthetic mutation failure.",'
            '"details":{"state":"${configuredFailure.state}"}}}',
      );
    }
    if (command == 'list' || command == 'status') {
      return _result(stdout: _profilesSuccess(command, profiles));
    }
    if (command == 'tools') {
      return _result(
        stdout: _success(
          'tools',
          '{"platform":"linux","tools":['
              '{"id":"codex","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":true}'
              '],"count":1}',
        ),
      );
    }

    _applyMutation(command, arguments);
    return _result(stdout: _mutationSuccess(command, arguments));
  }

  void _applyMutation(String command, List<String> arguments) {
    switch (command) {
      case 'new':
        final address = _address(arguments[2]);
        final type = arguments.contains('--shared')
            ? 'shared'
            : arguments.contains('--cli')
            ? 'cli'
            : 'full';
        profiles.add(_Summary(address.tool, address.name, type));
        break;
      case 'rename':
        final current = _address(arguments[2]);
        final target = _address(arguments[3]);
        profiles.removeWhere(
          (profile) =>
              profile.tool == current.tool && profile.name == current.name,
        );
        profiles.add(_Summary(target.tool, target.name, 'full'));
        break;
      case 'delete':
        final address = _address(arguments[2]);
        profiles.removeWhere(
          (profile) =>
              profile.tool == address.tool && profile.name == address.name,
        );
        break;
    }
    profiles.sort((a, b) {
      final byTool = a.tool.compareTo(b.tool);
      return byTool != 0 ? byTool : a.name.compareTo(b.name);
    });
  }
}

final class _RunCall {
  const _RunCall({
    required this.arguments,
    required this.profileId,
    required this.environment,
    required this.stdinText,
    required this.timeout,
  });

  final List<String> arguments;
  final String? profileId;
  final Map<String, String>? environment;
  final String? stdinText;
  final Duration timeout;
}

({String tool, String name}) _address(String value) {
  final separator = value.indexOf('/');
  return (
    tool: value.substring(0, separator),
    name: value.substring(separator + 1),
  );
}

String _mutationSuccess(String command, List<String> arguments) {
  final target = _address(command == 'rename' ? arguments[3] : arguments[2]);
  if (command == 'delete') {
    return _success(
      command,
      '{"state":"applied","profile":{'
      '"tool":"${target.tool}","name":"${target.name}"}}',
    );
  }
  final type = arguments.contains('--shared')
      ? 'shared'
      : arguments.contains('--cli')
      ? 'cli'
      : 'full';
  final from = command == 'rename'
      ? (() {
          final source = _address(arguments[2]);
          return '"from":{"tool":"${source.tool}","name":"${source.name}"},';
        })()
      : '';
  return _success(
    command,
    '{"state":"applied",$from"profile":{'
    '"tool":"${target.tool}","name":"${target.name}",'
    '"type":"$type","schemaVersion":2}}',
  );
}

String _profilesSuccess(String command, List<_Summary> profiles) {
  final entries = profiles
      .map(
        (profile) =>
            '{"tool":"${profile.tool}","name":"${profile.name}",'
            '"type":"${profile.type}","schemaVersion":2,"sizeBytes":1}',
      )
      .join(',');
  return _success(
    command,
    '{"profiles":[$entries],"count":${profiles.length}}',
  );
}

String _success(String command, String data) =>
    '{"schemaVersion":1,"command":"$command","ok":true,'
    '"data":$data,"error":null}';

SafeProcessResult _result({int exitCode = 0, String stdout = ''}) {
  final now = DateTime.utc(2026, 8, 24);
  return SafeProcessResult(
    exitCode: exitCode,
    stdout: stdout,
    stderr: '',
    startedAt: now,
    completedAt: now,
  );
}
