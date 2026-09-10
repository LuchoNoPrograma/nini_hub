import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('nini-hub-codex-rpc-');
  });

  tearDown(() async {
    await scratch.delete(recursive: true);
  });

  test(
    'managed profiles start app-server through Nini exec with clean context',
    () async {
      final profile = await _managedProfile(scratch);
      final process = _FakeCodexProcess(_successfulResponder);
      final launches = <CodexProcessLaunch>[];
      final client = CodexAppServerClient(
        processStarter: (launch) async {
          launches.add(launch);
          return process;
        },
      );

      final result = await client.refresh(profile);

      expect(result.state, UsageCheckState.success);
      expect(launches, hasLength(1));
      expect(launches.single.executable, 'nini-agents');
      expect(launches.single.arguments, [
        'exec',
        'codex/work',
        '--',
        'app-server',
        '--stdio',
      ]);
      expect(launches.single.workingDirectory, profile.profileHome);
      expect(launches.single.environment, {'MULTICLI_HOME': scratch.path});
      expect(process.stdinClosed, isTrue);
      expect(process.killSignals, isEmpty);
      await process.dispose();
    },
  );

  test(
    'usage survives several seconds of outage without blocking timers',
    () async {
      final profile = await _managedProfile(scratch);
      final attempts = <String, int>{};
      var timerRan = false;
      final process = _FakeCodexProcess((process, request) {
        final method = request['method'] as String;
        attempts[method] = (attempts[method] ?? 0) + 1;
        if (method == 'account/rateLimits/read' && attempts[method]! <= 3) {
          process.sendRaw(
            jsonEncode({
              'id': request['id'],
              'error': {'message': 'connection reset by peer'},
            }),
          );
          return;
        }
        _successfulResponder(process, request);
      });
      final timer = Timer(
        const Duration(milliseconds: 50),
        () => timerRan = true,
      );
      final result = await CodexAppServerClient(
        processStarter: (_) async => process,
      ).refresh(profile);

      expect(result.state, UsageCheckState.success);
      expect(attempts['account/rateLimits/read'], 4);
      expect(attempts['account/usage/read'], 1);
      expect(attempts['account/read'], 1);
      expect(timerRan, isTrue);
      expect(process.stdinClosed, isTrue);
      timer.cancel();
      await process.dispose();
    },
  );

  test(
    'persistent outage stays within the read budget and preserves partial data',
    () async {
      final profile = await _managedProfile(scratch);
      var attempts = 0;
      final process = _FakeCodexProcess((process, request) {
        if (request['method'] == 'account/rateLimits/read') {
          attempts++;
          if (attempts == 1) {
            process.sendRaw(
              jsonEncode({
                'id': request['id'],
                'error': {'message': 'connection reset'},
              }),
            );
          }
          // The retry receives no reply: it must only use the remaining budget.
          return;
        }
        _successfulResponder(process, request);
      });
      final elapsed = Stopwatch()..start();
      final result = await CodexAppServerClient(
        timeout: const Duration(milliseconds: 800),
        processStarter: (_) async => process,
      ).refresh(profile);

      expect(attempts, 2);
      expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 1200)));
      expect(result.state, UsageCheckState.partial);
      expect(result.dailyUsage, isNotEmpty);
      expect(process.stdinClosed, isTrue);
      await process.dispose();
    },
  );

  for (final message in [
    'error sending request: 401 unauthorized',
    'error sending request: token_expired',
    'method not found',
  ]) {
    test('does not retry permanent metadata failure: $message', () async {
      final profile = await _managedProfile(scratch);
      var attempts = 0;
      final process = _FakeCodexProcess((process, request) {
        if (request['method'] == 'account/rateLimits/read') {
          attempts++;
          process.sendRaw(
            jsonEncode({
              'id': request['id'],
              'error': {'message': message},
            }),
          );
          return;
        }
        _successfulResponder(process, request);
      });
      final result = await CodexAppServerClient(
        processStarter: (_) async => process,
      ).refresh(profile);
      expect(attempts, 1);
      expect(result.state, isNot(UsageCheckState.success));
      expect(process.stdinClosed, isTrue);
      await process.dispose();
    });
  }

  test('initial account read also recovers from a transient failure', () async {
    final profile = await _managedProfile(scratch);
    var attempts = 0;
    final process = _FakeCodexProcess((process, request) {
      if (request['method'] == 'account/read' && ++attempts == 1) {
        process.sendRaw(
          jsonEncode({
            'id': request['id'],
            'error': {'message': 'temporary failure in name resolution'},
          }),
        );
        return;
      }
      _successfulResponder(process, request);
    });
    final result = await CodexAppServerClient(
      processStarter: (_) async => process,
    ).refresh(profile);
    expect(result.state, UsageCheckState.success);
    expect(attempts, 2);
    await process.dispose();
  });

  test('default profile keeps the native Codex app-server boundary', () async {
    final home = Directory('${scratch.path}/.codex')
      ..createSync(recursive: true);
    final profile = _profile(
      home: home.path,
      name: 'base',
      source: ProfileSource.defaultProfile,
      kind: ProfileKind.base,
    );
    final process = _FakeCodexProcess(_successfulResponder);
    CodexProcessLaunch? launch;
    final client = CodexAppServerClient(
      executable: 'custom-codex',
      processStarter: (value) async {
        launch = value;
        return process;
      },
    );

    expect((await client.refresh(profile)).state, UsageCheckState.success);
    expect(launch?.executable, 'custom-codex');
    expect(launch?.arguments, ['app-server', '--stdio']);
    expect(launch?.environment, {'CODEX_HOME': home.path});
    await process.dispose();
  });

  test('non-JSON stdout fails closed as a protocol error', () async {
    final profile = await _managedProfile(scratch);
    final process = _FakeCodexProcess((process, request) {
      if (request['method'] == 'initialize') {
        process.sendRaw('Launching Codex profile...');
      }
    });
    final client = CodexAppServerClient(processStarter: (_) async => process);

    final result = await client.refresh(profile);

    expect(result.state, UsageCheckState.error);
    expect(result.errorCode, 'CODEX_PROTOCOL_ERROR');
    expect(result.errorMessage, isNot(contains('Launching Codex')));
    await process.dispose();
  });

  test(
    'process stderr is bounded, redacted, and never returned verbatim',
    () async {
      final profile = await _managedProfile(scratch);
      final process = _FakeCodexProcess((process, request) {
        if (request['method'] == 'initialize') {
          process.sendStderr(
            'Bearer private-token-value ${List.filled(5000, 'x').join()}',
          );
          scheduleMicrotask(() => process.completeExit(7));
        }
      });
      final client = CodexAppServerClient(processStarter: (_) async => process);

      CodexAppServerFailure? failure;
      try {
        await client.startDeviceAuth(profile);
      } on CodexAppServerFailure catch (error) {
        failure = error;
      }

      expect(failure?.kind, CodexAppServerFailureKind.processExited);
      expect(failure?.code, 'CODEX_PROCESS_EXITED');
      expect(failure?.message, 'Codex app-server terminó antes de responder.');
      expect(failure?.diagnostic, contains('Bearer [REDACTADO]'));
      expect(failure?.diagnostic, isNot(contains('private-token-value')));
      expect(failure!.diagnostic!.length, lessThan(4100));
      await process.dispose();
    },
  );

  test(
    'timeout closes stdin and terminates the supervised Windows tree',
    () async {
      final profile = await _managedProfile(scratch);
      final process = _FakeCodexProcess((_, _) {}, exitOnStdinClose: false);
      final terminated = <int>[];
      final client = CodexAppServerClient(
        timeout: const Duration(milliseconds: 5),
        isWindows: true,
        processStarter: (_) async => process,
        processTreeTerminator: (pid) async {
          terminated.add(pid);
          process.completeExit(1);
        },
      );

      final result = await client.refresh(profile);

      expect(result.state, UsageCheckState.timeout);
      expect(result.errorCode, 'TIMEOUT');
      expect(process.stdinClosed, isTrue);
      expect(terminated, [process.pid]);
      await process.dispose();
    },
  );

  test(
    'browser auth uses official ChatGPT RPC and completes without a device code',
    () async {
      final profile = await _managedProfile(scratch);
      final process = _FakeCodexProcess((process, request) {
        if (request['method'] == 'initialize') {
          process.respond(request, {});
          return;
        }
        expect(request['method'], 'account/login/start');
        expect(request['params'], {'type': 'chatgpt'});
        process.respond(request, {
          'type': 'chatgpt',
          'loginId': 'browser-1',
          'authUrl': 'https://auth.openai.com/authorize',
        });
      });
      final client = CodexAppServerClient(processStarter: (_) async => process);
      final session = await client.startDeviceAuth(profile, useBrowser: true);
      expect(session.userCode, isEmpty);
      expect(session.verificationUrl, 'https://auth.openai.com/authorize');
      final completion = session.waitForCompletion();
      process.sendRaw(
        jsonEncode({
          'method': 'account/login/completed',
          'params': {'loginId': 'browser-1', 'success': true},
        }),
      );
      expect(await completion, isTrue);
      expect(process.closeStdinCalls, 1);
      await process.dispose();
    },
  );

  for (final beforeReply in [true, false]) {
    test('retains early login confirmation beforeReply=$beforeReply', () async {
      final profile = await _managedProfile(scratch);
      final process = _FakeCodexProcess((process, request) {
        if (request['method'] == 'initialize') {
          process.respond(request, {});
          return;
        }
        if (beforeReply) {
          process.sendRaw(
            jsonEncode({
              'method': 'account/login/completed',
              'params': {'loginId': 'fast', 'success': true},
            }),
          );
        }
        process.respond(request, {
          'loginId': 'fast',
          'authUrl': 'https://example.test/auth',
        });
      });
      final client = CodexAppServerClient(processStarter: (_) async => process);
      final session = await client.startDeviceAuth(profile, useBrowser: true);
      if (!beforeReply) {
        process.sendRaw(
          jsonEncode({
            'method': 'account/login/completed',
            'params': {'loginId': 'fast', 'success': true},
          }),
        );
      }
      // Represents the interval between the RPC response and dialog mounting.
      await Future<void>.delayed(Duration.zero);
      process.sendRaw(
        jsonEncode({
          'method': 'account/login/completed',
          'params': {'loginId': 'unrelated', 'success': false},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await session.waitForCompletion(
          timeout: const Duration(milliseconds: 100),
        ),
        isTrue,
      );
      expect(process.closeStdinCalls, 1);
      await process.dispose();
    });
  }

  test(
    'early rejected login remains rejected and cannot authenticate another session',
    () async {
      final profile = await _managedProfile(scratch);
      final process = _FakeCodexProcess((process, request) {
        if (request['method'] == 'initialize') {
          process.respond(request, {});
          return;
        }
        process.sendRaw(
          jsonEncode({
            'method': 'account/login/completed',
            'params': {'loginId': 'rejected', 'success': false},
          }),
        );
        process.respond(request, {
          'loginId': 'rejected',
          'authUrl': 'https://example.test/auth',
        });
      });
      final session = await CodexAppServerClient(
        processStarter: (_) async => process,
      ).startDeviceAuth(profile, useBrowser: true);
      await Future<void>.delayed(Duration.zero);
      expect(
        await session.waitForCompletion(
          timeout: const Duration(milliseconds: 100),
        ),
        isFalse,
      );
      await process.dispose();
    },
  );

  test(
    'concurrent close callers all wait for the owned writer to stop',
    () async {
      final profile = await _managedProfile(scratch);
      final process = _FakeCodexProcess((process, request) {
        process.respond(
          request,
          request['method'] == 'initialize'
              ? {}
              : {'loginId': 'close', 'authUrl': 'https://example.test/auth'},
        );
      });
      final session = await CodexAppServerClient(
        processStarter: (_) async => process,
      ).startDeviceAuth(profile, useBrowser: true);
      process.closeGate = Completer<void>();
      var secondClosed = false;
      final first = session.close();
      final second = session.close().then((_) => secondClosed = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondClosed, isFalse);
      process.closeGate!.complete();
      await Future.wait([first, second]);
      expect(process.closeStdinCalls, 1);
      await process.dispose();
    },
  );

  test(
    'Device Auth relinks an existing profile without logout and cancels safely',
    () async {
      final profile = await _managedProfile(scratch);
      expect(profile.hasAuthFile, isTrue);
      final methods = <String>[];
      final process = _FakeCodexProcess((process, request) {
        final method = request['method'] as String;
        methods.add(method);
        final result = switch (method) {
          'initialize' => <String, Object?>{},
          'account/login/start' => <String, Object?>{
            'loginId': 'login-1',
            'verificationUrl': 'https://example.test/device',
            'userCode': 'ABCD-EFGH',
          },
          'account/login/cancel' => <String, Object?>{},
          _ => throw StateError('Unexpected method: $method'),
        };
        process.respond(request, result);
      });
      final client = CodexAppServerClient(processStarter: (_) async => process);

      final session = await client.startDeviceAuth(profile);
      expect(session.verificationUrl, 'https://example.test/device');
      expect(session.userCode, 'ABCD-EFGH');

      await session.cancel();
      await session.close();

      expect(methods, [
        'initialize',
        'account/login/start',
        'account/login/cancel',
      ]);
      expect(methods, isNot(contains('account/logout')));
      expect(process.closeStdinCalls, 1);
      await process.dispose();
    },
  );
}

typedef _Responder =
    void Function(_FakeCodexProcess process, Map<String, dynamic> request);

void _successfulResponder(
  _FakeCodexProcess process,
  Map<String, dynamic> request,
) {
  final method = request['method'];
  final result = switch (method) {
    'initialize' => <String, Object?>{},
    'account/read' => <String, Object?>{
      'account': {'email': 'owner@example.test', 'planType': 'plus'},
    },
    'account/rateLimits/read' => <String, Object?>{
      'limitId': 'codex',
      'primary': {'usedPercent': 25, 'windowDurationMins': 300},
    },
    'account/usage/read' => <String, Object?>{
      'dailyUsageBuckets': [
        {'date': '2026-08-24T00:00:00Z', 'totalTokens': 12},
      ],
    },
    _ => throw StateError('Unexpected method: $method'),
  };
  process.respond(request, result);
}

final class _FakeCodexProcess implements CodexProcessHandle {
  _FakeCodexProcess(this._responder, {this.exitOnStdinClose = true});

  final _Responder _responder;
  final bool exitOnStdinClose;
  final StreamController<List<int>> _stdout = StreamController();
  final StreamController<List<int>> _stderr = StreamController(sync: true);
  final Completer<int> _exitCode = Completer();
  final List<ProcessSignal> killSignals = [];
  bool stdinClosed = false;
  int closeStdinCalls = 0;
  Completer<void>? closeGate;

  @override
  int get pid => 2468;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<void> closeStdin() async {
    closeStdinCalls++;
    stdinClosed = true;
    if (closeGate != null) await closeGate!.future;
    if (exitOnStdinClose) completeExit(0);
  }

  @override
  bool kill(ProcessSignal signal) {
    killSignals.add(signal);
    completeExit(signal == ProcessSignal.sigterm ? 143 : 137);
    return true;
  }

  @override
  void writeLine(String value) {
    final decoded = jsonDecode(value);
    _responder(
      this,
      (decoded as Map).map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  void respond(Map<String, dynamic> request, Object? result) {
    scheduleMicrotask(() {
      if (!_stdout.isClosed) {
        _stdout.add(
          utf8.encode(
            '${jsonEncode({'id': request['id'], 'result': result})}\n',
          ),
        );
      }
    });
  }

  void sendRaw(String value) {
    scheduleMicrotask(() {
      if (!_stdout.isClosed) _stdout.add(utf8.encode('$value\n'));
    });
  }

  void sendStderr(String value) {
    scheduleMicrotask(() {
      if (!_stderr.isClosed) _stderr.add(utf8.encode(value));
    });
  }

  void completeExit(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  Future<void> dispose() async {
    completeExit(0);
    await _stdout.close();
    await _stderr.close();
  }
}

Future<Profile> _managedProfile(Directory scratch) async {
  final home = Directory('${scratch.path}/codex/work');
  await home.create(recursive: true);
  return _profile(
    home: home.path,
    name: 'work',
    source: ProfileSource.multiCli,
    kind: ProfileKind.full,
  );
}

Profile _profile({
  required String home,
  required String name,
  required ProfileSource source,
  required ProfileKind kind,
}) => Profile(
  id: name,
  toolKey: 'codex',
  profileName: name,
  displayName: name,
  profileHome: home,
  source: source,
  kind: kind,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);
