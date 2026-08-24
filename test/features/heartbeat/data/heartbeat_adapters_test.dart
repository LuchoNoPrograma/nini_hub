import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_models.dart';
import 'package:multi_cli_ai/features/heartbeat/data/codex_heartbeat_quota_probe.dart';
import 'package:multi_cli_ai/features/heartbeat/data/dart_heartbeat_runtime.dart';
import 'package:multi_cli_ai/features/heartbeat/data/process_heartbeat_activity_recorder.dart';
import 'package:multi_cli_ai/features/heartbeat/data/process_heartbeat_command_gateway.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_client.dart';

void main() {
  test('command gateway preserves the safe legacy process contract', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final runner = _RecordingProcessRunner(database);
    final gateway = ProcessHeartbeatCommandGateway(
      runner,
      temporaryDirectory: () => '/safe/temp',
    );

    final result = await gateway.execute(
      profile: _profile(),
      prompt: 'heartbeat prompt',
    );

    expect(result.succeeded, isTrue);
    expect(runner.calls, hasLength(1));
    final call = runner.calls.single;
    expect(call.executable, 'codex');
    expect(call.arguments, [
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
      'CODEX_HOME': '/profiles/primary',
      'NO_COLOR': '1',
    });
    expect(call.timeout, const Duration(seconds: 90));
    expect(call.stdinText, isNull);
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
    expect(client.profileHomes, ['/profiles/primary']);
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
  Future<CodexRefreshResult> refresh(String profileHome) async {
    profileHomes.add(profileHome);
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

Profile _profile() => const Profile(
  id: 'primary',
  toolKey: 'codex',
  profileName: 'primary',
  displayName: 'Primary',
  profileHome: '/profiles/primary',
  source: ProfileSource.multiCli,
  kind: ProfileKind.shared,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);
