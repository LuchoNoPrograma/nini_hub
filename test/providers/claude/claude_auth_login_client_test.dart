import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/data/claude_account_device_auth_gateway.dart';
import 'package:nini_hub/features/accounts/data/provider_account_device_auth_gateway.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/providers/claude/claude_auth_login_client.dart';
import 'package:path/path.dart' as p;

const _url =
    'https://claude.com/cai/oauth/authorize?code=true&client_id=abc&state=xyz';

void main() {
  late Directory root;
  late Profile profile;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nini-hub-claude-login-');
    final home = Directory(p.join(root.path, 'claude-cli', 'luis'))
      ..createSync(recursive: true);
    profile = _profile(home.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('parses plain and OSC 8 hyperlinked sign-in URLs', () {
    expect(
      ClaudeAuthLoginClient.parseAuthorizationUrl('visit: $_url\n'),
      _url,
    );
    expect(
      ClaudeAuthLoginClient.parseAuthorizationUrl(
        'visit: \x1b]8;;$_url\x07$_url\x1b]8;;\x07\n',
      ),
      _url,
    );
    expect(
      ClaudeAuthLoginClient.parseAuthorizationUrl('visit: $_url'),
      isNull,
      reason: 'an unterminated URL may still be arriving',
    );
  });

  test('runs auth login through the profile and completes on exit 0', () async {
    final process = _FakeProcess();
    ClaudeProcessLaunch? launch;
    ClaudeProcessLaunch? confirmation;
    final client = ClaudeAuthLoginClient(
      isWindows: false,
      processRunner: (value) async {
        confirmation = value;
        return const ClaudeProcessOutput(
          0,
          'Claude configuration file not found\n{"loggedIn": true}\n',
        );
      },
      processStarter: (value) async {
        launch = value;
        scheduleMicrotask(
          () => process.emit('Opening browser to sign in…\nvisit: $_url\n'),
        );
        return process;
      },
    );

    final session = await client.start(profile);

    expect(launch?.executable, 'nini-agents');
    expect(launch?.arguments, [
      'exec',
      'claude-cli/luis',
      '--',
      'auth',
      'login',
    ]);
    expect(launch?.environment, {'MULTICLI_HOME': root.path});
    expect(session.verificationUrl, _url);

    await session.submitCode('  code#state  ');
    expect(process.lines, ['code#state']);

    process.exit(0);
    expect(await session.waitForCompletion(), isTrue);
    expect(confirmation?.arguments, [
      'exec',
      'claude-cli/luis',
      '--',
      'auth',
      'status',
      '--json',
    ]);
  });

  test('a login that did not stick in the profile is reported', () async {
    final process = _FakeProcess();
    final client = ClaudeAuthLoginClient(
      isWindows: false,
      processRunner: (_) async =>
          const ClaudeProcessOutput(1, '{"loggedIn": false}'),
      processStarter: (_) async {
        scheduleMicrotask(() => process.emit('visit: $_url\n'));
        return process;
      },
    );
    final session = await client.start(profile);

    process.exit(0);

    await expectLater(
      session.waitForCompletion(),
      throwsA(
        isA<ClaudeAuthLoginFailure>().having(
          (e) => e.code,
          'code',
          'CLAUDE_LOGIN_UNCONFIRMED',
        ),
      ),
    );
  });

  test('auth status JSON is read past warning lines', () {
    expect(
      ClaudeAuthLoginClient.parseAuthStatus('warning\n{"loggedIn": true}\n'),
      {'loggedIn': true},
    );
    expect(ClaudeAuthLoginClient.parseAuthStatus('no json'), isNull);
  });

  test('reports a failed login with sanitized output', () async {
    final process = _FakeProcess();
    final client = ClaudeAuthLoginClient(
      isWindows: false,
      processStarter: (_) async {
        scheduleMicrotask(() => process.emit('visit: $_url\n'));
        return process;
      },
    );
    final session = await client.start(profile);

    process.emit('OAuth error: invalid code\n');
    process.exit(1);

    await expectLater(
      session.waitForCompletion(),
      throwsA(
        isA<ClaudeAuthLoginFailure>()
            .having((e) => e.code, 'code', 'DEVICE_AUTH_FAILED')
            .having((e) => e.diagnostic, 'diagnostic', contains('invalid code'))
            .having(
              (e) => e.diagnostic,
              'diagnostic',
              isNot(contains('oauth/authorize')),
            ),
      ),
    );
  });

  test('cancellation stops the process and reports no success', () async {
    final process = _FakeProcess();
    final client = ClaudeAuthLoginClient(
      isWindows: false,
      processStarter: (_) async {
        scheduleMicrotask(() => process.emit('visit: $_url\n'));
        return process;
      },
    );
    final session = await client.start(profile);
    final completion = session.waitForCompletion();

    await session.cancel();

    expect(process.signals, contains(ProcessSignal.sigterm));
    expect(await completion, isFalse);
  });

  test('fails when Claude exits before printing the URL', () async {
    final process = _FakeProcess();
    final client = ClaudeAuthLoginClient(
      isWindows: false,
      processStarter: (_) async {
        scheduleMicrotask(() {
          process.emit('claude: command not found\n');
          process.exit(127);
        });
        return process;
      },
    );

    await expectLater(
      client.start(profile),
      throwsA(
        isA<ClaudeAuthLoginFailure>().having(
          (e) => e.code,
          'code',
          'CLAUDE_LOGIN_FAILED',
        ),
      ),
    );
  });

  test('rejects profiles outside the Claude tool directory', () async {
    final other = Directory(p.join(root.path, 'codex', 'luis'))
      ..createSync(recursive: true);
    final client = ClaudeAuthLoginClient(
      processStarter: (_) async => fail('must not start a process'),
    );

    await expectLater(
      client.start(_profile(other.path)),
      throwsA(
        isA<ClaudeAuthLoginFailure>().having(
          (e) => e.code,
          'code',
          'INVALID_PROFILE_HOME',
        ),
      ),
    );
  });

  test('gateways route each profile to its own sign-in flow', () async {
    final session = _FakeCodeSession();
    Profile? received;
    final gateway = ProviderAccountDeviceAuthGateway({
      'claude-cli': ClaudeAccountDeviceAuthGateway.withStarter((value) async {
        received = value;
        return session;
      }),
    });

    expect(await gateway.start(profile), same(session));
    expect(received, same(profile));
    expect(
      () => gateway.start(_profile('/profiles/x', toolKey: 'cursor')),
      throwsA(isA<UnsupportedProfileToolFailure>()),
    );
  });
}

Profile _profile(String home, {String toolKey = 'claude-cli'}) => Profile(
  id: 'luis',
  toolKey: toolKey,
  profileName: 'luis',
  commandName: '$toolKey-luis',
  displayName: 'Luis',
  profileHome: home,
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: false,
  isAvailable: true,
  isFavorite: false,
);

final class _FakeProcess implements ClaudeProcessHandle {
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  final lines = <String>[];
  final signals = <ProcessSignal>[];

  void emit(String value) => _stdout.add(utf8.encode(value));

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 42;

  @override
  void writeLine(String value) => lines.add(value);

  @override
  Future<void> closeStdin() async {}

  @override
  bool kill(ProcessSignal signal) {
    signals.add(signal);
    exit(-15);
    return true;
  }
}

final class _FakeCodeSession implements AccountAuthorizationCodeSession {
  @override
  String get verificationUrl => _url;

  @override
  String get userCode => '';

  @override
  Future<void> submitAuthorizationCode(String code) async {}

  @override
  Future<bool> waitForCompletion() async => true;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async {}
}
