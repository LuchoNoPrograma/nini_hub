import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

typedef ProcessTreeTerminator = Future<void> Function(int pid);
typedef TerminalLaunchCommand = ({String target, List<String> arguments});

class SafeProcessResult {
  const SafeProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.startedAt,
    required this.completedAt,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final DateTime startedAt;
  final DateTime completedAt;
  final bool timedOut;

  bool get succeeded => exitCode == 0 && !timedOut;
  String get combinedOutput => [
    stdout,
    stderr,
  ].where((value) => value.trim().isNotEmpty).join('\n').trim();
}

class ProcessRunner {
  ProcessRunner(
    this.database, {
    bool? isWindows,
    ProcessTreeTerminator? processTreeTerminator,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _processTreeTerminator =
           processTreeTerminator ?? _terminateWindowsProcessTree;

  final AppDatabase database;
  final bool _isWindows;
  final ProcessTreeTerminator _processTreeTerminator;
  final Uuid _uuid = const Uuid();
  static Future<String>? _hyperShellLauncher;
  static Future<String>? _persistentLinuxSessionLauncher;
  static Future<String>? _persistentWindowsSessionLauncher;

  static const persistentLinuxSessionLauncherScript = r'''#!/usr/bin/env bash
set -u

target=${1:?}
shift
"$target" "$@"
exit_code=$?

printf '\nLa sesión terminó (código %s). La terminal seguirá abierta; escribe "exit" para cerrarla.\n' "$exit_code"
shell_path=${SHELL:-/bin/bash}
if [[ ! -x "$shell_path" ]]; then
  shell_path=/bin/bash
fi
exec "$shell_path" -l
''';

  static const persistentWindowsSessionLauncherScript = r'''param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string] $Target,
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]] $TargetArguments
)

& $Target @TargetArguments
$sessionExitCode = $LASTEXITCODE
if ($null -eq $sessionExitCode) {
  $sessionExitCode = 0
}
Write-Host "`nLa sesión terminó (código $sessionExitCode). La terminal seguirá abierta; escribe 'exit' para cerrarla."
''';

  static String? findExecutable(String name) {
    final executableNames = executableFileNames(
      name,
      isWindows: Platform.isWindows,
      pathExtensions: Platform.environment['PATHEXT'],
    );
    for (final executableName in executableNames) {
      final direct = File(executableName);
      if (direct.isAbsolute && direct.existsSync()) return direct.path;
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final searchDirectories = <String>[
      if (home != null) '$home/.local/bin',
      ...?Platform.environment['PATH']
          ?.split(Platform.isWindows ? ';' : ':')
          .where((item) => item.trim().isNotEmpty),
    ];
    for (final directory in searchDirectories) {
      for (final executableName in executableNames) {
        final candidate = '$directory${Platform.pathSeparator}$executableName';
        if (File(candidate).existsSync()) return candidate;
      }
    }
    return null;
  }

  static List<String> executableFileNames(
    String name, {
    required bool isWindows,
    String? pathExtensions,
  }) {
    if (!isWindows) return [name];
    final normalizedName = name.toLowerCase();
    final extensions = <String>[
      '.exe',
      ...?pathExtensions
          ?.split(';')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.startsWith('.') && value.length > 1),
      '.com',
      '.bat',
      '.cmd',
    ];
    final uniqueExtensions = <String>[];
    for (final extension in extensions) {
      if (!uniqueExtensions.contains(extension)) {
        uniqueExtensions.add(extension);
      }
    }
    if (uniqueExtensions.any(normalizedName.endsWith)) return [name];
    return uniqueExtensions.map((extension) => '$name$extension').toList();
  }

  static String resolveExecutable(String name) => findExecutable(name) ?? name;

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
    final started = DateTime.now().toUtc();
    final logId = recordActivity ? _uuid.v4() : null;
    if (logId != null) {
      await database
          .into(database.commandLogs)
          .insert(
            CommandLogsCompanion.insert(
              id: logId,
              profileId: Value(profileId),
              command: _displayCommand(executable, arguments),
              summary: summary,
              status: 'running',
              startedAt: started,
            ),
          );
    }

    Process? process;
    try {
      process = await Process.start(
        resolveExecutable(executable),
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: true,
        runInShell: false,
      );
      if (stdinText != null) process.stdin.write(stdinText);
      await process.stdin.close();

      final stdoutFuture = utf8.decoder
          .bind(process.stdout)
          .join()
          .then(sanitizeOutput);
      final stderrFuture = utf8.decoder
          .bind(process.stderr)
          .join()
          .then(sanitizeOutput);
      var timedOut = false;
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () async {
          timedOut = true;
          await _terminateTimedOutProcess(process!);
          return 124;
        },
      );
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      final completed = DateTime.now().toUtc();
      if (logId != null) {
        await _finishLog(
          logId,
          exitCode: exitCode,
          status: timedOut ? 'timeout' : (exitCode == 0 ? 'success' : 'error'),
          output: [
            stdout,
            stderr,
          ].where((value) => value.trim().isNotEmpty).join('\n'),
          completedAt: completed,
        );
      }
      return SafeProcessResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        startedAt: started,
        completedAt: completed,
        timedOut: timedOut,
      );
    } on ProcessException catch (error) {
      final completed = DateTime.now().toUtc();
      final message = sanitizeOutput(error.message);
      if (logId != null) {
        await _finishLog(
          logId,
          exitCode: 127,
          status: 'error',
          output: message,
          completedAt: completed,
        );
      }
      return SafeProcessResult(
        exitCode: 127,
        stdout: '',
        stderr: message,
        startedAt: started,
        completedAt: completed,
      );
    } finally {
      if (process != null && process.pid > 0) {
        // A completed process ignores this. A child left by a timeout does not.
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  Future<void> _terminateTimedOutProcess(Process process) async {
    if (_isWindows) {
      try {
        await _processTreeTerminator(process.pid);
        return;
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
        return;
      }
    }
    process.kill(ProcessSignal.sigterm);
    Timer(const Duration(milliseconds: 500), () {
      process.kill(ProcessSignal.sigkill);
    });
  }

  Future<void> startDetached({
    required String executable,
    required List<String> arguments,
    required String summary,
    String? profileId,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    final started = DateTime.now().toUtc();
    final id = _uuid.v4();
    try {
      await Process.start(
        resolveExecutable(executable),
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: false,
        mode: ProcessStartMode.detached,
      );
      await database
          .into(database.commandLogs)
          .insert(
            CommandLogsCompanion.insert(
              id: id,
              profileId: Value(profileId),
              command: _displayCommand(executable, arguments),
              summary: summary,
              output: Value(
                workingDirectory == null
                    ? 'Proceso iniciado en una terminal separada.'
                    : 'Proceso iniciado en una terminal separada. '
                          'Directorio: ${sanitizeOutput(workingDirectory)}',
              ),
              status: 'success',
              exitCode: const Value(0),
              startedAt: started,
              completedAt: Value(DateTime.now().toUtc()),
            ),
          );
    } on ProcessException catch (error) {
      await database
          .into(database.commandLogs)
          .insert(
            CommandLogsCompanion.insert(
              id: id,
              profileId: Value(profileId),
              command: _displayCommand(executable, arguments),
              summary: summary,
              output: Value(sanitizeOutput(error.message)),
              status: 'error',
              exitCode: const Value(127),
              startedAt: started,
              completedAt: Value(DateTime.now().toUtc()),
            ),
          );
      rethrow;
    }
  }

  Future<void> startInTerminal({
    required String executable,
    required List<String> arguments,
    required String summary,
    String? profileId,
    String? workingDirectory,
    String? title,
    Map<String, String>? environment,
    bool keepOpenAfterExit = false,
  }) async {
    final target = resolveExecutable(executable);
    var terminalCommand = (
      target: target,
      arguments: List<String>.unmodifiable(arguments),
    );
    if (keepOpenAfterExit && Platform.isLinux) {
      terminalCommand = buildPersistentTerminalCommand(
        isWindows: false,
        launcher: await _ensurePersistentLinuxSessionLauncher(),
        target: target,
        arguments: arguments,
      );
    } else if (keepOpenAfterExit && Platform.isWindows) {
      final powershell = findExecutable('powershell') ?? findExecutable('pwsh');
      if (powershell == null) {
        throw StateError(
          'No se encontró PowerShell para mantener abierta la terminal.',
        );
      }
      terminalCommand = buildPersistentTerminalCommand(
        isWindows: true,
        launcher: await _ensurePersistentWindowsSessionLauncher(),
        powershell: powershell,
        target: target,
        arguments: arguments,
      );
    }
    final launchDirectory = workingDirectory == null
        ? null
        : Directory(workingDirectory).absolute.path;
    final inheritedEnvironment = Map<String, String>.of(Platform.environment);
    if (environment != null) inheritedEnvironment.addAll(environment);
    final terminalEnvironment = buildTerminalEnvironment(inheritedEnvironment);
    if (Platform.isLinux) {
      final candidates = await _linuxTerminalCandidates();
      for (final candidate in candidates) {
        final terminal = findExecutable(candidate);
        if (terminal == null) continue;
        final terminalKind = identifyTerminal(terminal);
        final environment = terminalKind == 'hyper'
            ? buildHyperTerminalEnvironment(
                terminalEnvironment,
                shellLauncher: await _ensureHyperShellLauncher(),
                target: terminalCommand.target,
                arguments: terminalCommand.arguments,
                title: title,
              )
            : terminalEnvironment;
        await startDetached(
          executable: terminal,
          arguments: buildTerminalArguments(
            terminal: terminalKind,
            target: terminalCommand.target,
            arguments: terminalCommand.arguments,
            workingDirectory: launchDirectory,
            title: title,
          ),
          summary: summary,
          profileId: profileId,
          workingDirectory: launchDirectory,
          environment: environment,
          includeParentEnvironment: false,
        );
        _scheduleLinuxTerminalActivation(title);
        return;
      }
    } else if (Platform.isWindows) {
      final terminal = findExecutable('wt');
      if (terminal != null) {
        await startDetached(
          executable: terminal,
          arguments: buildTerminalArguments(
            terminal: 'wt',
            target: terminalCommand.target,
            arguments: terminalCommand.arguments,
            workingDirectory: launchDirectory,
            title: title,
          ),
          summary: summary,
          profileId: profileId,
          workingDirectory: launchDirectory,
          environment: terminalEnvironment,
          includeParentEnvironment: false,
        );
        _scheduleWindowsTerminalActivation(title);
        return;
      }
    }
    throw StateError(
      'No se encontró una terminal compatible para abrir el comando.',
    );
  }

  static TerminalLaunchCommand buildPersistentTerminalCommand({
    required bool isWindows,
    required String launcher,
    required String target,
    required List<String> arguments,
    String? powershell,
  }) {
    if (!isWindows) {
      return (
        target: launcher,
        arguments: List<String>.unmodifiable([target, ...arguments]),
      );
    }
    final windowsShell = powershell?.trim();
    if (windowsShell == null || windowsShell.isEmpty) {
      throw ArgumentError.value(
        powershell,
        'powershell',
        'Se requiere PowerShell para mantener abierta la terminal.',
      );
    }
    return (
      target: windowsShell,
      arguments: List<String>.unmodifiable([
        '-NoLogo',
        '-NoProfile',
        '-NoExit',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        launcher,
        target,
        ...arguments,
      ]),
    );
  }

  static List<String> buildTerminalArguments({
    required String terminal,
    required String target,
    required List<String> arguments,
    String? workingDirectory,
    String? title,
  }) => switch (terminal) {
    'hyper' => [?workingDirectory],
    'gnome-terminal' || 'kgx' => [
      if (title != null) '--title=$title',
      if (workingDirectory != null) '--working-directory=$workingDirectory',
      '--',
      target,
      ...arguments,
    ],
    'konsole' => [
      if (title != null) ...['-p', 'tabtitle=$title'],
      if (workingDirectory != null) ...['--workdir', workingDirectory],
      '-e',
      target,
      ...arguments,
    ],
    'wt' => [
      '--window',
      'new',
      'new-tab',
      if (title != null) ...['--title', title],
      if (workingDirectory != null) ...['-d', workingDirectory],
      target,
      ...arguments,
    ],
    _ => [
      if (title != null) ...['-T', title],
      '-e',
      target,
      ...arguments,
    ],
  };

  static Map<String, String> buildTerminalEnvironment(
    Map<String, String> parent,
  ) => Map<String, String>.of(parent)..remove('NO_COLOR');

  static Map<String, String> buildHyperTerminalEnvironment(
    Map<String, String> parent, {
    required String shellLauncher,
    required String target,
    required List<String> arguments,
    String? title,
  }) {
    final environment = buildTerminalEnvironment(parent)
      ..removeWhere((key, _) => key.startsWith('MULTICLI_TERMINAL_'))
      ..['SHELL'] = shellLauncher
      ..['MULTICLI_TERMINAL_TARGET'] = target
      ..['MULTICLI_TERMINAL_ARGC'] = arguments.length.toString();
    if (title != null && title.isNotEmpty) {
      environment['MULTICLI_TERMINAL_TITLE'] = title;
    }
    for (var index = 0; index < arguments.length; index++) {
      environment['MULTICLI_TERMINAL_ARG_$index'] = arguments[index];
    }
    return environment;
  }

  static String identifyTerminal(String executable) {
    var resolved = executable;
    try {
      resolved = File(executable).resolveSymbolicLinksSync();
    } on FileSystemException {
      // The configured command may not be a symlink or may disappear later.
    }
    final name = resolved.replaceAll('\\', '/').split('/').last.toLowerCase();
    if (name.contains('hyper')) return 'hyper';
    if (name.contains('gnome-terminal')) return 'gnome-terminal';
    if (name == 'kgx') return 'kgx';
    if (name.contains('konsole')) return 'konsole';
    return 'x-terminal-emulator';
  }

  static Future<List<String>> _linuxTerminalCandidates() async {
    final candidates = <String>[];
    final configured = await _readDesktopTerminal();
    if (configured != null) candidates.add(configured);
    for (final fallback in const [
      'x-terminal-emulator',
      'gnome-terminal',
      'kgx',
      'konsole',
    ]) {
      if (!candidates.contains(fallback)) candidates.add(fallback);
    }
    return candidates;
  }

  static Future<String?> _readDesktopTerminal() async {
    final gsettings = findExecutable('gsettings');
    if (gsettings == null) return null;
    for (final schema in const [
      'org.cinnamon.desktop.default-applications.terminal',
      'org.gnome.desktop.default-applications.terminal',
    ]) {
      try {
        final result = await Process.run(gsettings, ['get', schema, 'exec']);
        if (result.exitCode != 0) continue;
        final value = parseGSettingsString(result.stdout.toString());
        if (value != null && value.isNotEmpty) return value;
      } on ProcessException {
        return null;
      }
    }
    return null;
  }

  static String? parseGSettingsString(String output) {
    final value = output.trim();
    if (value.length < 2) return null;
    final quote = value[0];
    if ((quote != "'" && quote != '"') || value[value.length - 1] != quote) {
      return value;
    }
    final decoded = StringBuffer();
    for (var index = 1; index < value.length - 1; index++) {
      final character = value[index];
      if (character == r'\' && index + 1 < value.length - 1) {
        index++;
        decoded.write(value[index]);
      } else {
        decoded.write(character);
      }
    }
    final result = decoded.toString();
    return result.isEmpty ? null : result;
  }

  static Future<String> _ensureHyperShellLauncher() =>
      _hyperShellLauncher ??= _createHyperShellLauncher();

  static Future<String> _ensurePersistentLinuxSessionLauncher() =>
      _persistentLinuxSessionLauncher ??=
          _createPersistentLinuxSessionLauncher();

  static Future<String> _ensurePersistentWindowsSessionLauncher() =>
      _persistentWindowsSessionLauncher ??=
          _createPersistentWindowsSessionLauncher();

  static Future<String> _createPersistentLinuxSessionLauncher() async {
    final directory = await Directory.systemTemp.createTemp(
      'nini-hub-terminal-session-',
    );
    final launcher = File('${directory.path}/keep-session-open');
    await launcher.writeAsString(persistentLinuxSessionLauncherScript);
    final chmod = await Process.run('chmod', ['700', launcher.path]);
    if (chmod.exitCode != 0) {
      throw FileSystemException(
        'No se pudo preparar la sesión persistente de terminal.',
        launcher.path,
      );
    }
    return launcher.path;
  }

  static Future<String> _createPersistentWindowsSessionLauncher() async {
    final directory = await Directory.systemTemp.createTemp(
      'nini-hub-terminal-session-',
    );
    final launcher = File('${directory.path}/keep-session-open.ps1');
    await launcher.writeAsString(persistentWindowsSessionLauncherScript);
    return launcher.path;
  }

  static Future<String> _createHyperShellLauncher() async {
    final directory = await Directory.systemTemp.createTemp(
      'multi-cli-ai-hyper-',
    );
    final launcher = File('${directory.path}/launch-command');
    await launcher.writeAsString(r'''#!/usr/bin/env bash
set -u

target=${MULTICLI_TERMINAL_TARGET:?}
argument_count=${MULTICLI_TERMINAL_ARGC:-0}
arguments=()
for ((index = 0; index < argument_count; index++)); do
  variable="MULTICLI_TERMINAL_ARG_${index}"
  arguments+=("${!variable-}")
done

if [[ -n ${MULTICLI_TERMINAL_TITLE:-} ]]; then
  printf '\033]0;%s\007' "$MULTICLI_TERMINAL_TITLE"
fi

exec "$target" "${arguments[@]}"
''');
    final chmod = await Process.run('chmod', ['700', launcher.path]);
    if (chmod.exitCode != 0) {
      throw FileSystemException(
        'No se pudo preparar el iniciador de Hyper.',
        launcher.path,
      );
    }
    return launcher.path;
  }

  void _scheduleLinuxTerminalActivation(String? title) {
    if (!Platform.isLinux || title == null || title.isEmpty) return;
    final sessionType = Platform.environment['XDG_SESSION_TYPE'];
    if (sessionType?.toLowerCase() == 'wayland') return;
    final xdotool = findExecutable('xdotool');
    if (xdotool == null) return;
    unawaited(_activateLinuxTerminalWindow(xdotool, title));
  }

  void _scheduleWindowsTerminalActivation(String? title) {
    if (!Platform.isWindows || title == null || title.isEmpty) return;
    final powershell = findExecutable('powershell') ?? findExecutable('pwsh');
    if (powershell == null) return;
    unawaited(_activateWindowsTerminalWindow(powershell, title));
  }

  Future<void> _activateLinuxTerminalWindow(
    String xdotool,
    String title,
  ) async {
    final pattern = RegExp.escape(title);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var attempt = 0; attempt < 4; attempt++) {
        final search = await Process.run(xdotool, [
          'search',
          '--name',
          '--limit',
          '1',
          pattern,
        ]);
        final windowId = search.stdout.toString().trim().split('\n').first;
        if (search.exitCode == 0 && windowId.isNotEmpty) {
          await Process.run(xdotool, ['windowactivate', windowId]);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } on ProcessException {
      // Focusing is best-effort; launching the terminal already succeeded.
    }
  }

  Future<void> _activateWindowsTerminalWindow(
    String powershell,
    String title,
  ) async {
    const script = r'''
Add-Type -TypeDefinition '
using System;
using System.Runtime.InteropServices;
public static class MultiCliWindow {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}'
for ($attempt = 0; $attempt -lt 5; $attempt++) {
  $window = Get-Process -Name 'WindowsTerminal*' -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle.Contains($env:MULTICLI_TERMINAL_TITLE) } |
    Select-Object -First 1
  if ($null -ne $window) {
    [MultiCliWindow]::ShowWindowAsync($window.MainWindowHandle, 9) | Out-Null
    [MultiCliWindow]::SetForegroundWindow($window.MainWindowHandle) | Out-Null
    exit 0
  }
  Start-Sleep -Milliseconds 250
}

''';
    try {
      await Process.start(
        powershell,
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          script,
        ],
        environment: {'MULTICLI_TERMINAL_TITLE': title},
        includeParentEnvironment: true,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException {
      // Focusing is best-effort; launching Windows Terminal already succeeded.
    }
  }

  Future<void> addInternalLog({
    required String summary,
    required String status,
    required String output,
    String? profileId,
    String command = 'internal',
  }) => database
      .into(database.commandLogs)
      .insert(
        CommandLogsCompanion.insert(
          id: _uuid.v4(),
          profileId: Value(profileId),
          command: command,
          summary: summary,
          output: Value(sanitizeOutput(output)),
          status: status,
          startedAt: DateTime.now().toUtc(),
          completedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> _finishLog(
    String id, {
    required int exitCode,
    required String status,
    required String output,
    required DateTime completedAt,
  }) =>
      (database.update(
        database.commandLogs,
      )..where((row) => row.id.equals(id))).write(
        CommandLogsCompanion(
          exitCode: Value(exitCode),
          status: Value(status),
          output: Value(sanitizeOutput(output)),
          completedAt: Value(completedAt),
        ),
      );

  static String sanitizeOutput(String value) {
    var clean = value;
    final patterns = <RegExp>[
      RegExp(r'sk-[A-Za-z0-9_-]{8,}'),
      RegExp(
        r'((?:access|refresh|id)[_-]?token\s*[=:]\s*)[^\s,}\]]+',
        caseSensitive: false,
      ),
      RegExp(r'(authorization:\s*bearer\s+)[^\s]+', caseSensitive: false),
      RegExp(r'(api[_-]?key\s*[=:]\s*)[^\s,}\]]+', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      clean = clean.replaceAllMapped(pattern, (match) {
        final prefix = match.groupCount > 0 ? (match.group(1) ?? '') : '';
        return prefix.isEmpty
            ? '[REDACTADO]'
            : '${prefix.trimRight()} [REDACTADO]';
      });
    }
    return clean.length > 12000
        ? '${clean.substring(0, 12000)}\n[truncado]'
        : clean;
  }

  static String _displayCommand(String executable, List<String> arguments) {
    String quote(String value) =>
        RegExp(r'^[A-Za-z0-9_./:@=-]+$').hasMatch(value)
        ? value
        : '"${value.replaceAll('"', '\\"')}"';
    return [executable, ...arguments].map(quote).join(' ');
  }
}

Future<void> _terminateWindowsProcessTree(int pid) async {
  final result = await Process.run(
    ProcessRunner.resolveExecutable('taskkill'),
    ['/PID', '$pid', '/T', '/F'],
    runInShell: false,
  ).timeout(const Duration(seconds: 5));
  if (result.exitCode != 0) {
    throw ProcessException(
      'taskkill',
      ['/PID', '$pid', '/T', '/F'],
      'taskkill terminó con código ${result.exitCode}.',
      result.exitCode,
    );
  }
}
