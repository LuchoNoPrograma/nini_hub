import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';

void main() {
  test('keeps executable names unchanged outside Windows', () {
    expect(ProcessRunner.executableFileNames('nini-agents', isWindows: false), [
      'nini-agents',
    ]);
  });

  test('resolves Windows executables and installed command wrappers', () {
    expect(
      ProcessRunner.executableFileNames(
        'nini-agents',
        isWindows: true,
        pathExtensions: '.COM;.EXE;.BAT;.CMD',
      ),
      [
        'nini-agents.exe',
        'nini-agents.com',
        'nini-agents.bat',
        'nini-agents.cmd',
      ],
    );
    expect(
      ProcessRunner.executableFileNames(
        'nini-agents.cmd',
        isWindows: true,
        pathExtensions: '.EXE;.CMD',
      ),
      ['nini-agents.cmd'],
    );
  });

  test('persistent terminal wrappers preserve every target argument', () {
    const target = '/opt/nini agents/nini-agents';
    const arguments = ['launch', 'codex/team', '--', 'value with spaces'];

    final linux = ProcessRunner.buildPersistentTerminalCommand(
      isWindows: false,
      launcher: '/tmp/keep-session-open',
      target: target,
      arguments: arguments,
    );
    expect(linux.target, '/tmp/keep-session-open');
    expect(linux.arguments, [target, ...arguments]);

    final windows = ProcessRunner.buildPersistentTerminalCommand(
      isWindows: true,
      launcher: r'C:\Temp\keep-session-open.ps1',
      powershell: r'C:\Windows\System32\WindowsPowerShell\powershell.exe',
      target: r'C:\Program Files\Nini Hub\nini-agents.cmd',
      arguments: arguments,
    );
    expect(
      windows.target,
      r'C:\Windows\System32\WindowsPowerShell\powershell.exe',
    );
    expect(windows.arguments, [
      '-NoLogo',
      '-NoProfile',
      '-NoExit',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      r'C:\Temp\keep-session-open.ps1',
      r'C:\Program Files\Nini Hub\nini-agents.cmd',
      ...arguments,
    ]);
    expect(
      ProcessRunner.persistentWindowsSessionLauncherScript,
      contains(r'& $Target @TargetArguments'),
    );
  });

  test(
    'Linux persistent wrapper returns to a login shell after target exit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nini-terminal-wrapper-',
      );
      addTearDown(() => root.delete(recursive: true));
      final launcher = File('${root.path}/keep-session-open');
      final target = File('${root.path}/target');
      final shell = File('${root.path}/shell');
      await launcher.writeAsString(
        ProcessRunner.persistentLinuxSessionLauncherScript,
      );
      await target.writeAsString('#!/usr/bin/env bash\nexit 130\n');
      await shell.writeAsString(
        '#!/usr/bin/env bash\nprintf "SHELL:%s\\n" "\$*"\n',
      );
      final chmod = await Process.run('chmod', [
        '700',
        launcher.path,
        target.path,
        shell.path,
      ]);
      expect(chmod.exitCode, 0);

      final result = await Process.run(
        launcher.path,
        [target.path],
        environment: {'SHELL': shell.path},
        includeParentEnvironment: true,
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains('código 130'));
      expect(result.stdout, contains('SHELL:-l'));
    },
    skip: Platform.isWindows
        ? 'La ejecución real del wrapper Bash solo aplica a Linux.'
        : false,
  );

  test('timeout terminates the supervised Windows process tree', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('nini-runner-timeout-');
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final script = File('${root.path}/wait.dart');
    await script.writeAsString('''
import 'dart:async';

Future<void> main() => Future<void>.delayed(const Duration(seconds: 30));
''');
    int? terminatedPid;
    final runner = ProcessRunner(
      database,
      isWindows: true,
      processTreeTerminator: (pid) async {
        terminatedPid = pid;
        Process.killPid(pid, ProcessSignal.sigkill);
      },
    );

    final result = await runner.run(
      executable: Platform.resolvedExecutable,
      arguments: [script.path],
      summary: 'Probar timeout Windows',
      timeout: const Duration(milliseconds: 50),
    );

    expect(terminatedPid, isNotNull);
    expect(result.exitCode, 124);
    expect(result.timedOut, isTrue);
    expect(result.succeeded, isFalse);
    final log = await database.select(database.commandLogs).getSingle();
    expect(log.status, 'timeout');
    expect(log.exitCode, 124);
  });
}
