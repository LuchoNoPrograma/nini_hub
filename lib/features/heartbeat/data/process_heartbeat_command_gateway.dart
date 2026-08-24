import 'dart:io';

import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';

typedef HeartbeatTemporaryDirectory = String Function();

final class ProcessHeartbeatCommandGateway implements HeartbeatCommandGateway {
  ProcessHeartbeatCommandGateway(
    this.runner, {
    HeartbeatTemporaryDirectory? temporaryDirectory,
  }) : _temporaryDirectory =
           temporaryDirectory ?? (() => Directory.systemTemp.path);

  final ProcessRunner runner;
  final HeartbeatTemporaryDirectory _temporaryDirectory;

  @override
  Future<HeartbeatCommandResult> execute({
    required Profile profile,
    required String prompt,
  }) async {
    final temporaryDirectory = _temporaryDirectory();
    try {
      final result = await runner.run(
        executable: 'codex',
        arguments: [
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
          temporaryDirectory,
          '-c',
          'model_reasoning_effort="low"',
          prompt,
        ],
        summary: 'Iniciar ventana de ${profile.displayName}',
        profileId: profile.id,
        workingDirectory: temporaryDirectory,
        environment: {'CODEX_HOME': profile.profileHome, 'NO_COLOR': '1'},
        timeout: const Duration(seconds: 90),
      );
      if (result.succeeded) {
        return const HeartbeatCommandResult.success();
      }
      final stderr = result.stderr.trim();
      return HeartbeatCommandResult.failure(
        stderr.isEmpty
            ? 'Codex terminó con código ${result.exitCode}.'
            : ProcessRunner.sanitizeOutput(stderr),
      );
    } catch (error) {
      return HeartbeatCommandResult.failure(
        ProcessRunner.sanitizeOutput(error.toString()),
      );
    }
  }
}
