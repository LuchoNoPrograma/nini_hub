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
