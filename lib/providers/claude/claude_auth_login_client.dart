import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:path/path.dart' as p;

final class ClaudeAuthLoginFailure implements Exception {
  const ClaudeAuthLoginFailure({
    required this.code,
    required this.message,
    this.diagnostic,
  });

  final String code;
  final String message;
  final String? diagnostic;

  @override
  String toString() => message;
}

final class ClaudeProcessLaunch {
  const ClaudeProcessLaunch({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
}

abstract interface class ClaudeProcessHandle {
  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  Future<int> get exitCode;

  int get pid;

  void writeLine(String value);

  Future<void> closeStdin();

  bool kill(ProcessSignal signal);
}

typedef ClaudeProcessStarter = Future<ClaudeProcessHandle> Function(
  ClaudeProcessLaunch launch,
);
typedef ClaudeProcessTreeTerminator = Future<void> Function(int pid);

final class ClaudeProcessOutput {
  const ClaudeProcessOutput(this.exitCode, this.stdout);

  final int exitCode;
  final String stdout;
}

typedef ClaudeProcessRunner = Future<ClaudeProcessOutput> Function(
  ClaudeProcessLaunch launch,
);

/// Drives `claude auth login` inside a Nini Agents profile.
///
/// Claude Code opens the official sign-in page itself and finishes on its own
/// when the browser returns to its localhost callback. When that callback is
/// unavailable, the page shows an authorization code that must be pasted back
/// into the same process, which [ClaudeAuthLoginSession.submitCode] does.
class ClaudeAuthLoginClient {
  const ClaudeAuthLoginClient({
    this.niniAgentsExecutable = 'nini-agents',
    this.urlTimeout = const Duration(seconds: 30),
    this.processStarter,
    this.processTreeTerminator,
    this.processRunner,
    this.isWindows,
  });

  final String niniAgentsExecutable;
  final Duration urlTimeout;
  final ClaudeProcessStarter? processStarter;
  final ClaudeProcessTreeTerminator? processTreeTerminator;
  final ClaudeProcessRunner? processRunner;
  final bool? isWindows;

  Future<ClaudeAuthLoginSession> start(Profile profile) async {
    if (!Directory(profile.profileHome).existsSync()) {
      throw const ClaudeAuthLoginFailure(
        code: 'PROFILE_MISSING',
        message: 'La carpeta del perfil no existe.',
      );
    }
    final ClaudeProcessHandle process;
    try {
      process = await (processStarter ?? _startClaudeProcess)(
        _processLaunch(profile, const ['auth', 'login']),
      );
    } on ProcessException catch (error) {
      throw ClaudeAuthLoginFailure(
        code: 'NINI_AGENTS_NOT_FOUND',
        message: 'No se encontró el ejecutable de Nini Agents.',
        diagnostic: error.message,
      );
    }
    final session = ClaudeAuthLoginSession._(
      process: process,
      processTreeTerminator:
          processTreeTerminator ?? _terminateWindowsProcessTree,
      isWindows: isWindows ?? Platform.isWindows,
      confirmLogin: () => _confirmLogin(profile),
    );
    try {
      await session._waitForUrl(urlTimeout);
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  // `nini-agents exec` replaces itself with Claude Code, so the credential that
  // `auth login` wrote stays in the profile runtime until the next start. A
  // second exec reconciles it into the profile and proves the login stuck.
  Future<bool> _confirmLogin(Profile profile) async {
    final ClaudeProcessOutput result;
    try {
      result = await (processRunner ?? _runClaudeProcess)(
        _processLaunch(profile, const ['auth', 'status', '--json']),
      );
    } on ProcessException catch (error) {
      throw ClaudeAuthLoginFailure(
        code: 'NINI_AGENTS_NOT_FOUND',
        message: 'No se encontró el ejecutable de Nini Agents.',
        diagnostic: error.message,
      );
    }
    final status = parseAuthStatus(result.stdout);
    if (status?['loggedIn'] == true) return true;
    throw const ClaudeAuthLoginFailure(
      code: 'CLAUDE_LOGIN_UNCONFIRMED',
      message: 'Claude Code terminó, pero el perfil no quedó con la sesión iniciada.',
    );
  }

  /// Reads the JSON object printed by `claude auth status --json`, ignoring
  /// any warning lines Claude Code prints before it.
  static Map<String, dynamic>? parseAuthStatus(String output) {
    final start = output.indexOf('{');
    final end = output.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(output.substring(start, end + 1));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  ClaudeProcessLaunch _processLaunch(
    Profile profile,
    List<String> claudeArguments,
  ) {
    final profileHome = p.normalize(p.absolute(profile.profileHome));
    final provider = profileProvider(profile.toolKey);
    final toolDirectory = p.dirname(profileHome);
    if (profile.source != ProfileSource.multiCli ||
        p.basename(toolDirectory) != provider.multiCliTool) {
      throw const ClaudeAuthLoginFailure(
        code: 'INVALID_PROFILE_HOME',
        message: 'La ubicación del perfil no coincide con su herramienta.',
      );
    }
    return ClaudeProcessLaunch(
      executable: niniAgentsExecutable,
      arguments: [
        'exec',
        provider.profileSpec(profile.profileName),
        '--',
        ...claudeArguments,
      ],
      workingDirectory: profileHome,
      environment: {'MULTICLI_HOME': p.dirname(toolDirectory)},
    );
  }

  /// Extracts the sign-in URL from Claude's output, including OSC 8 links.
  static String? parseAuthorizationUrl(String output) {
    final match = RegExp(
      r'https://[^\s\x07\x1b]*oauth/authorize[^\s\x07\x1b]*(?=[\s\x07\x1b])',
    ).firstMatch(output);
    return match?.group(0);
  }
}

class ClaudeAuthLoginSession {
  ClaudeAuthLoginSession._({
    required this.process,
    required this.processTreeTerminator,
    required this.isWindows,
    required this.confirmLogin,
  }) {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(_onOutput, onError: (_) {});
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(_onOutput, onError: (_) {});
  }

  final ClaudeProcessHandle process;
  final ClaudeProcessTreeTerminator processTreeTerminator;
  final bool isWindows;
  final Future<bool> Function() confirmLogin;
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  final _output = StringBuffer();
  final _url = Completer<String>();
  String? _verificationUrl;
  bool _closed = false;
  bool _cancelled = false;
  Future<void>? _closeFuture;

  String get verificationUrl => _verificationUrl ?? '';

  void _onOutput(String chunk) {
    _output.write(chunk);
    if (_url.isCompleted) return;
    final url = ClaudeAuthLoginClient.parseAuthorizationUrl(_output.toString());
    if (url == null) return;
    _verificationUrl = url;
    _url.complete(url);
  }

  Future<void> _waitForUrl(Duration timeout) async {
    final exited = process.exitCode.then<String?>((_) => null);
    final String? url;
    try {
      url = await Future.any<String?>([_url.future, exited]).timeout(timeout);
    } on TimeoutException {
      throw ClaudeAuthLoginFailure(
        code: 'CLAUDE_LOGIN_TIMEOUT',
        message: 'Claude Code no devolvió el enlace de acceso a tiempo.',
        diagnostic: _diagnostic(),
      );
    }
    if (url == null) {
      throw ClaudeAuthLoginFailure(
        code: 'CLAUDE_LOGIN_FAILED',
        message: 'Claude Code terminó antes de mostrar el enlace de acceso.',
        diagnostic: _diagnostic(),
      );
    }
  }

  /// Sends the code shown by the official page when the browser could not
  /// return to Claude Code automatically.
  Future<void> submitCode(String code) async {
    final value = code.trim();
    if (value.isEmpty) {
      throw const ClaudeAuthLoginFailure(
        code: 'EMPTY_AUTH_CODE',
        message: 'Pega el código que muestra la página de Claude.',
      );
    }
    if (_closed) {
      throw const ClaudeAuthLoginFailure(
        code: 'CLAUDE_LOGIN_CLOSED',
        message: 'El proceso de acceso de Claude ya se cerró.',
      );
    }
    process.writeLine(value);
  }

  Future<bool> waitForCompletion({
    Duration timeout = const Duration(minutes: 10),
  }) async {
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      // Let the readers drain the final lines before reporting a failure.
      await Future<void>.delayed(Duration.zero);
      if (exitCode == 0) return await confirmLogin();
      if (_cancelled) return false;
      throw ClaudeAuthLoginFailure(
        code: 'DEVICE_AUTH_FAILED',
        message: 'Claude Code no pudo completar el acceso.',
        diagnostic: _diagnostic(),
      );
    } on TimeoutException {
      throw const ClaudeAuthLoginFailure(
        code: 'DEVICE_AUTH_TIMEOUT',
        message:
            'Claude Code no confirmó el acceso dentro del tiempo disponible.',
      );
    } finally {
      await close();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    await close();
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    try {
      await process.closeStdin();
    } catch (_) {}
    if (!await _waitForExit(const Duration(milliseconds: 200))) {
      if (isWindows) {
        try {
          await processTreeTerminator(process.pid);
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
        }
      } else {
        process.kill(ProcessSignal.sigterm);
      }
      if (!await _waitForExit(const Duration(seconds: 2))) {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
  }

  Future<bool> _waitForExit(Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }

  // Keep the tail of the output only; it never contains the pasted code.
  String _diagnostic() {
    final cleaned = _output
        .toString()
        .replaceAll(RegExp(r'\x1b\][^\x07\x1b]*(\x07|\x1b\\)'), '')
        .replaceAll(RegExp(r'\x1b\[[0-9;?]*[A-Za-z]'), '')
        .replaceAll(RegExp(r'https://\S+'), '[enlace]')
        .trim();
    return cleaned.length <= 400
        ? cleaned
        : cleaned.substring(cleaned.length - 400);
  }
}

Future<ClaudeProcessHandle> _startClaudeProcess(
  ClaudeProcessLaunch launch,
) async => _IoClaudeProcessHandle(
  await Process.start(
    ProcessRunner.resolveExecutable(launch.executable),
    launch.arguments,
    workingDirectory: launch.workingDirectory,
    environment: launch.environment,
    includeParentEnvironment: true,
    runInShell: false,
  ),
);

Future<ClaudeProcessOutput> _runClaudeProcess(
  ClaudeProcessLaunch launch,
) async {
  final result = await Process.run(
    ProcessRunner.resolveExecutable(launch.executable),
    launch.arguments,
    workingDirectory: launch.workingDirectory,
    environment: launch.environment,
    includeParentEnvironment: true,
    runInShell: false,
  ).timeout(const Duration(seconds: 30));
  return ClaudeProcessOutput(result.exitCode, '${result.stdout}');
}

Future<void> _terminateWindowsProcessTree(int pid) async {
  await Process.run(ProcessRunner.resolveExecutable('taskkill'), [
    '/PID',
    '$pid',
    '/T',
    '/F',
  ], runInShell: false);
}

final class _IoClaudeProcessHandle implements ClaudeProcessHandle {
  const _IoClaudeProcessHandle(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> closeStdin() => _process.stdin.close();

  @override
  bool kill(ProcessSignal signal) => _process.kill(signal);

  @override
  void writeLine(String value) => _process.stdin.writeln(value);
}
