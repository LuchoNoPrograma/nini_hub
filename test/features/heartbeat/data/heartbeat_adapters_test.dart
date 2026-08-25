import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';
import 'package:nini_hub/features/heartbeat/data/codex_heartbeat_quota_probe.dart';
import 'package:nini_hub/features/heartbeat/data/dart_heartbeat_runtime.dart';
import 'package:nini_hub/features/heartbeat/data/process_heartbeat_activity_recorder.dart';
import 'package:nini_hub/features/heartbeat/data/process_heartbeat_command_gateway.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'managed command uses Nini Agents with the safe process contract',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final runner = _RecordingProcessRunner(database);
      final gateway = ProcessHeartbeatCommandGateway(
        runner,
        temporaryDirectory: () => '/safe/temp',
      );

      final profile = _profile();
      final result = await gateway.execute(
        profile: profile,
        prompt: 'heartbeat prompt',
      );

      expect(result.succeeded, isTrue);
      expect(runner.calls, hasLength(1));
      final call = runner.calls.single;
      expect(call.executable, 'nini-agents');
      expect(call.arguments, [
        'exec',
        'codex/primary',
        '--',
        'exec',
        '--ephemeral',
        '--ignore-user-config',
        '--ignore-rules',
        '--skip-git-repo-check',
        '--sandbox',
        'read-only',
        '--color',
        'never',
        '-C',
        '/safe/temp',
        '-c',
        'model_reasoning_effort="low"',
        'heartbeat prompt',
      ]);
      expect(call.summary, 'Iniciar ventana de Primary');
      expect(call.profileId, 'primary');
      expect(call.workingDirectory, '/safe/temp');
      expect(call.environment, {
        'MULTICLI_HOME': p.dirname(
          p.dirname(p.normalize(p.absolute(profile.profileHome))),
        ),
        'NO_COLOR': '1',
      });
      expect(call.timeout, const Duration(seconds: 90));
      expect(call.stdinText, isNull);
    },
  );

  test('principal command stays on native Codex with CODEX_HOME', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final runner = _RecordingProcessRunner(database);
    final gateway = ProcessHeartbeatCommandGateway(
      runner,
      temporaryDirectory: () => '/safe/temp',
    );
    final profile = _profile(
      source: ProfileSource.defaultProfile,
      profileHome: '/profiles/.codex',
    );

    final result = await gateway.execute(profile: profile, prompt: 'prompt');

    expect(result.succeeded, isTrue);
    final call = runner.calls.single;
    expect(call.executable, 'codex');
    expect(call.arguments.first, 'exec');
    expect(call.environment, {
      'CODEX_HOME': p.normalize(p.absolute(profile.profileHome)),
      'NO_COLOR': '1',
    });
  });

  test('managed command rejects a profile home for another tool', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final runner = _RecordingProcessRunner(database);
    final gateway = ProcessHeartbeatCommandGateway(
      runner,
      temporaryDirectory: () => '/safe/temp',
    );

    final result = await gateway.execute(
      profile: _profile(profileHome: '/profiles/not-codex/primary'),
      prompt: 'prompt',
    );

    expect(result.succeeded, isFalse);
    expect(result.failureMessage, contains('no coincide con su herramienta'));
    expect(runner.calls, isEmpty);
  });

  test('command gateway translates and redacts process failures', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final runner = _RecordingProcessRunner(database);
    final gateway = ProcessHeartbeatCommandGateway(
      runner,
      temporaryDirectory: () => '/safe/temp',
    );
    runner.result = _processResult(
      exitCode: 7,
      stderr: 'access_token=secret-value',
    );

    final failed = await gateway.execute(profile: _profile(), prompt: 'prompt');
    expect(failed.succeeded, isFalse);
    expect(failed.failureMessage, 'access_token= [REDACTADO]');

    runner.error = StateError('api_key=another-secret');
    final thrown = await gateway.execute(profile: _profile(), prompt: 'prompt');
    expect(thrown.succeeded, isFalse);
    expect(thrown.failureMessage, contains('api_key= [REDACTADO]'));
  });

  test('quota probe fixes 30 seconds and maps the profile response', () async {
    final client = _RecordingCodexClient(
      CodexRefreshResult(
        state: UsageCheckState.partial,
        startedAt: DateTime.utc(2026, 8, 23, 10),
        completedAt: DateTime.utc(2026, 8, 23, 10, 0, 1),
        accountEmail: 'owner@example.com',
      ),
    );
    Duration? requestedTimeout;
    final probe = CodexHeartbeatQuotaProbe(
      clientFactory: (timeout) {
        requestedTimeout = timeout;
        return client;
      },
    );

    final snapshot = await probe.probe(_profile());

    expect(requestedTimeout, const Duration(seconds: 30));
    expect(client.profileHomes, ['/profiles/codex/primary']);
    expect(snapshot.status, UsageRefreshStatus.partial);
    expect(snapshot.accountEmail, 'owner@example.com');
  });

  test('activity recorder preserves fields, statuses and redaction', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final recorder = ProcessHeartbeatActivityRecorder(ProcessRunner(database));

    await recorder.record(
      profile: _profile(),
      kind: HeartbeatActivityKind.verified,
      message: 'confirmado',
    );
    await recorder.record(
      profile: _profile(),
      kind: HeartbeatActivityKind.unverified,
      message: 'sin confirmar',
    );
    await recorder.record(
      profile: _profile(),
      kind: HeartbeatActivityKind.probeFailure,
      message: 'api_key=private-value',
    );

    final logs = await database.select(database.commandLogs).get();
    expect(logs, hasLength(3));
    expect(logs[0].summary, 'Verificar ventana de Primary');
    expect(logs[0].status, 'success');
    expect(logs[0].output, 'confirmado');
    expect(logs[1].summary, 'Verificar ventana de Primary');
    expect(logs[1].status, 'error');
    expect(logs[1].output, 'sin confirmar');
    expect(logs[2].summary, 'Revisar ventana de Primary');
    expect(logs[2].status, 'error');
    expect(logs[2].output, 'api_key= [REDACTADO] Reintento con backoff.');
    expect(logs.map((log) => log.command).toSet(), {
      'codex app-server account/rateLimits/read',
    });
    expect(logs.map((log) => log.profileId).toSet(), {'primary'});
  });

  test('runtime adapters expose UTC time and a Dart delay', () async {
    expect(const SystemHeartbeatClock().nowUtc().isUtc, isTrue);
    await const DartHeartbeatDelay().wait(Duration.zero);
  });
}

final class _RecordingProcessRunner extends ProcessRunner {
  _RecordingProcessRunner(super.database);

  final List<_ProcessCall> calls = [];
  SafeProcessResult result = _processResult();
  Object? error;

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
      _ProcessCall(
        executable: executable,
        arguments: List.unmodifiable(arguments),
        summary: summary,
        profileId: profileId,
        workingDirectory: workingDirectory,
        environment: environment == null ? null : Map.unmodifiable(environment),
        stdinText: stdinText,
        timeout: timeout,
      ),
    );
    final currentError = error;
    if (currentError != null) throw currentError;
    return result;
  }
}

final class _ProcessCall {
  const _ProcessCall({
    required this.executable,
    required this.arguments,
    required this.summary,
    required this.profileId,
    required this.workingDirectory,
    required this.environment,
    required this.stdinText,
    required this.timeout,
  });

  final String executable;
  final List<String> arguments;
  final String summary;
  final String? profileId;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final String? stdinText;
  final Duration timeout;
}

final class _RecordingCodexClient extends CodexAppServerClient {
  _RecordingCodexClient(this.result);

  final CodexRefreshResult result;
  final List<String> profileHomes = [];

  @override
  Future<CodexRefreshResult> refresh(Profile profile) async {
    profileHomes.add(profile.profileHome);
    return result;
  }
}

SafeProcessResult _processResult({
  int exitCode = 0,
  String stdout = 'OK',
  String stderr = '',
}) => SafeProcessResult(
  exitCode: exitCode,
  stdout: stdout,
  stderr: stderr,
  startedAt: DateTime.utc(2026, 8, 23, 10),
  completedAt: DateTime.utc(2026, 8, 23, 10, 0, 1),
);

Profile _profile({
  ProfileSource source = ProfileSource.multiCli,
  String profileHome = '/profiles/codex/primary',
}) => Profile(
  id: 'primary',
  toolKey: 'codex',
  profileName: 'primary',
  displayName: 'Primary',
  profileHome: profileHome,
  source: source,
  kind: source == ProfileSource.defaultProfile
      ? ProfileKind.base
      : ProfileKind.shared,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);
