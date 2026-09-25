import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/core/process/process_runner.dart';

void main() {
  late AppDatabase database;
  late _RecordingProcessRunner runner;
  late NiniAgentsReadClient client;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    runner = _RecordingProcessRunner(database);
    client = NiniAgentsReadClient(runner);
  });

  tearDown(() => database.close());

  for (final command in ['list', 'status']) {
    test(
      '$command allows slow disk inventory and respects its timeout',
      () async {
        runner.result = _result(
          stdout: _success(command, '{"profiles":[],"count":0}'),
        );
        if (command == 'list') {
          await client.list();
        } else {
          await client.status();
        }
        expect(runner.calls.last.timeout, const Duration(seconds: 60));

        final configured = NiniAgentsReadClient(
          runner,
          profileReadTimeout: const Duration(seconds: 45),
        );
        if (command == 'list') {
          await configured.list();
        } else {
          await configured.status();
        }
        expect(runner.calls.last.timeout, const Duration(seconds: 45));
      },
    );
  }

  test(
    'reads version through the canonical executable and JSON prefix',
    () async {
      runner.result = _result(
        stdout: _success(
          'version',
          '{"product":"nini-agents","version":"1.0.0"}',
        ),
      );

      final version = await client.version();

      expect(version.product, 'nini-agents');
      expect(version.version, '1.0.0');
      expect(runner.calls.single.executable, 'nini-agents');
      expect(runner.calls.single.arguments, ['--json', 'version']);
      expect(runner.calls.single.timeout, const Duration(seconds: 15));
      expect(runner.calls.single.environment, isNull);
      expect(runner.calls.single.recordActivity, isFalse);
    },
  );

  test(
    'reads sorted schema v1 and v2 profiles with the configured root',
    () async {
      runner.result = _result(
        stdout: _success('list', '''{
          "profiles":[
            {"tool":"codex","name":"legacy","type":"full","schemaVersion":1,"sizeBytes":4,"hasAuthFile":false},
            {"tool":"codex","name":"work","type":"shared","schemaVersion":2,"sizeBytes":8,"hasAuthFile":true}
          ],
          "count":2
        }'''),
      );

      final profiles = await client.list(profilesRoot: '/synthetic/profiles');

      expect(profiles.command, 'list');
      expect(profiles.count, 2);
      expect(profiles.profiles.first.schemaVersion, 1);
      expect(profiles.profiles.first.hasAuthFile, isFalse);
      expect(profiles.profiles.last.schemaVersion, 2);
      expect(profiles.profiles.last.hasAuthFile, isTrue);
      expect(runner.calls.single.arguments, ['--json', 'list']);
      expect(runner.calls.single.environment, {
        'MULTICLI_HOME': '/synthetic/profiles',
      });
      expect(runner.calls.single.recordActivity, isFalse);
    },
  );

  test('passes the status tool filter without shell interpolation', () async {
    runner.result = _result(
      stdout: _success('status', '''{
          "profiles":[
            {"tool":"codex","name":"work","type":"full","schemaVersion":2,"sizeBytes":9,"hasAuthFile":true}
          ],
          "count":1
        }'''),
    );

    final profiles = await client.status(tool: ' codex ');

    expect(profiles.command, 'status');
    expect(profiles.profiles.single.tool, 'codex');
    expect(profiles.profiles.single.hasAuthFile, isTrue);
    expect(runner.calls.single.arguments, ['--json', 'status', 'codex']);
    expect(runner.calls.single.recordActivity, isFalse);
  });

  for (final platform in ['linux', 'windows']) {
    test('reads $platform tool capabilities from tools', () async {
      runner.result = _result(
        stdout: _success('tools', '''{
            "platform":"$platform",
            "tools":[
              {"id":"claude-cli","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":false},
              {"id":"codex","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":true}
            ],
            "count":2
          }'''),
      );

      final tools = await client.tools();

      expect(tools.platform, platform);
      expect(tools.count, 2);
      expect(tools.tools.first.installed, isFalse);
      expect(tools.tools.last.installed, isTrue);
      expect(runner.calls.single.arguments, ['--json', 'tools']);
      expect(runner.calls.single.recordActivity, isFalse);
    });
  }

  test('creates a profile through the versioned mutation envelope', () async {
    runner.result = _result(
      stdout: _success('new', '''{
        "state":"applied",
        "profile":{"tool":"codex","name":"team","type":"shared","schemaVersion":2}
      }'''),
    );

    final mutation = await client.createProfile(
      tool: 'codex',
      name: 'team',
      setupMode: 'shared',
      seedFromBase: false,
      profilesRoot: '/synthetic/profiles',
    );

    expect(mutation.command, 'new');
    expect(mutation.profile.tool, 'codex');
    expect(mutation.profile.name, 'team');
    expect(runner.calls.single.arguments, [
      '--json',
      'new',
      'codex/team',
      '--shared',
      '--no-seed',
    ]);
    expect(runner.calls.single.timeout, const Duration(minutes: 2));
    expect(runner.calls.single.recordActivity, isTrue);
    expect(runner.calls.single.environment, {
      'MULTICLI_HOME': '/synthetic/profiles',
    });
  });

  test('validates rename and exact-confirmation delete results', () async {
    runner.result = _result(
      stdout: _success('rename', '''{
        "state":"applied",
        "from":{"tool":"codex","name":"team"},
        "profile":{"tool":"codex","name":"new-team","type":"full","schemaVersion":2}
      }'''),
    );
    final renamed = await client.renameProfile(
      tool: 'codex',
      currentName: 'team',
      newName: 'new-team',
      profileId: 'profile-id',
    );

    expect(renamed.from?.name, 'team');
    expect(renamed.profile.name, 'new-team');
    expect(runner.calls.single.arguments, [
      '--json',
      'rename',
      'codex/team',
      'codex/new-team',
    ]);

    runner.calls.clear();
    runner.result = _result(
      stdout: _success('delete', '''{
        "state":"applied",
        "profile":{"tool":"codex","name":"new-team"}
      }'''),
    );
    await client.deleteProfile(
      tool: 'codex',
      name: 'new-team',
      profileId: 'profile-id',
    );

    expect(runner.calls.single.arguments, [
      '--json',
      'delete',
      'codex/new-team',
      '--confirm',
      'codex/new-team',
    ]);
  });

  test('preserves machine-safe mutation rejection state', () async {
    runner.result = _result(
      exitCode: 6,
      stdout:
          '{"schemaVersion":1,"command":"delete","ok":false,'
          '"data":null,"error":{"code":"operation_failed",'
          '"message":"Delete incomplete.",'
          '"details":{"state":"partially_applied"}}}',
    );

    await expectLater(
      client.deleteProfile(
        tool: 'codex',
        name: 'team',
        profileId: 'profile-id',
      ),
      throwsA(
        isA<NiniAgentsReadFailure>()
            .having((failure) => failure.code, 'code', 'operation_failed')
            .having(
              (failure) => failure.mutationState,
              'mutationState',
              NiniAgentsMutationState.partiallyApplied,
            ),
      ),
    );
  });

  test('preserves a stable remote error code and exit code', () async {
    runner.result = _result(
      exitCode: 6,
      stdout:
          '{"schemaVersion":1,"command":"tools","ok":false,'
          '"data":null,"error":{"code":"dependency_missing",'
          '"message":"A required dependency is unavailable."}}',
    );

    await expectLater(
      client.tools(),
      throwsA(
        isA<NiniAgentsReadFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              NiniAgentsReadFailureKind.remote,
            )
            .having((failure) => failure.code, 'code', 'dependency_missing')
            .having((failure) => failure.exitCode, 'exitCode', 6),
      ),
    );
  });

  test('reports an unavailable executable without exposing stderr', () async {
    runner.result = _result(exitCode: 127, stderr: 'private host path');

    await expectLater(
      client.version(),
      throwsA(
        isA<NiniAgentsReadFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              NiniAgentsReadFailureKind.executableUnavailable,
            )
            .having(
              (failure) => failure.message,
              'message',
              isNot(contains('private host path')),
            ),
      ),
    );
  });

  test('reports timeout before attempting to decode partial output', () async {
    runner.result = _result(
      exitCode: 124,
      stdout: '{"partial":',
      timedOut: true,
    );

    await expectLater(
      client.version(),
      throwsA(
        isA<NiniAgentsReadFailure>().having(
          (failure) => failure.kind,
          'kind',
          NiniAgentsReadFailureKind.timeout,
        ),
      ),
    );
  });

  test('rejects human preambles and multiple JSON documents', () async {
    for (final stdout in [
      'Loading profiles...\n${_success('version', '{"product":"nini-agents","version":"1.0.0"}')}',
      '${_success('version', '{"product":"nini-agents","version":"1.0.0"}')}\n{}',
    ]) {
      runner.result = _result(stdout: stdout);

      await expectLater(
        client.version(),
        throwsA(
          isA<NiniAgentsReadFailure>().having(
            (failure) => failure.kind,
            'kind',
            NiniAgentsReadFailureKind.malformedResponse,
          ),
        ),
      );
    }
  });

  test('rejects schema, command, stderr and process inconsistencies', () async {
    final cases = <SafeProcessResult>[
      _result(
        stdout:
            '{"schemaVersion":2,"command":"version","ok":true,'
            '"data":{},"error":null}',
      ),
      _result(
        stdout:
            '{"schemaVersion":1,"command":"tools","ok":true,'
            '"data":{},"error":null}',
      ),
      _result(
        stdout: _success(
          'version',
          '{"product":"nini-agents","version":"1.0.0"}',
        ),
        stderr: 'unexpected warning',
      ),
      _result(
        exitCode: 1,
        stdout: _success(
          'version',
          '{"product":"nini-agents","version":"1.0.0"}',
        ),
      ),
    ];

    for (final result in cases) {
      runner.result = result;
      await expectLater(
        client.version(),
        throwsA(isA<NiniAgentsReadFailure>()),
      );
    }
  });

  test('rejects inconsistent counts, order and unsafe error codes', () async {
    final outputs = [
      _success('list', '''{
          "profiles":[
            {"tool":"codex","name":"work","type":"full","schemaVersion":2,"sizeBytes":1}
          ],
          "count":1
        }'''),
      _success('list', '''{
          "profiles":[
            {"tool":"codex","name":"work","type":"full","schemaVersion":2,"sizeBytes":1,"hasAuthFile":true}
          ],
          "count":2
        }'''),
      _success('list', '''{
          "profiles":[
            {"tool":"codex","name":"z","type":"full","schemaVersion":2,"sizeBytes":1,"hasAuthFile":true},
            {"tool":"codex","name":"a","type":"full","schemaVersion":2,"sizeBytes":1,"hasAuthFile":false}
          ],
          "count":2
        }'''),
    ];
    for (final output in outputs) {
      runner.result = _result(stdout: output);
      await expectLater(client.list(), throwsA(isA<NiniAgentsReadFailure>()));
    }

    runner.result = _result(
      exitCode: 2,
      stdout:
          '{"schemaVersion":1,"command":"list","ok":false,'
          '"data":null,"error":{"code":"Not Safe",'
          '"message":"Invalid."}}',
    );
    await expectLater(
      client.list(),
      throwsA(
        isA<NiniAgentsReadFailure>().having(
          (failure) => failure.kind,
          'kind',
          NiniAgentsReadFailureKind.protocolViolation,
        ),
      ),
    );
  });

  test('rejects empty filters before starting a process', () async {
    await expectLater(client.status(tool: '  '), throwsArgumentError);
    await expectLater(client.list(profilesRoot: '  '), throwsArgumentError);
    expect(runner.calls, isEmpty);
  });
}

String _success(String command, String data) =>
    '{"schemaVersion":1,"command":"$command","ok":true,'
    '"data":$data,"error":null}';

SafeProcessResult _result({
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
  bool timedOut = false,
}) => SafeProcessResult(
  exitCode: exitCode,
  stdout: stdout,
  stderr: stderr,
  startedAt: DateTime.utc(2026, 8, 24),
  completedAt: DateTime.utc(2026, 8, 24),
  timedOut: timedOut,
);

final class _RecordingProcessRunner extends ProcessRunner {
  _RecordingProcessRunner(super.database);

  SafeProcessResult result = _result();
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
        executable: executable,
        arguments: List.unmodifiable(arguments),
        environment: environment == null ? null : Map.unmodifiable(environment),
        timeout: timeout,
        recordActivity: recordActivity,
      ),
    );
    return result;
  }
}

final class _RunCall {
  const _RunCall({
    required this.executable,
    required this.arguments,
    required this.environment,
    required this.timeout,
    required this.recordActivity,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String>? environment;
  final Duration timeout;
  final bool recordActivity;
}
