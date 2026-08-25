import 'dart:io';

import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:path/path.dart' as p;

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
      final childArguments = [
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
      ];
      final launch = _buildLaunch(profile, childArguments);
      final result = await runner.run(
        executable: launch.executable,
        arguments: launch.arguments,
        summary: 'Iniciar ventana de ${profile.displayName}',
        profileId: profile.id,
        workingDirectory: temporaryDirectory,
        environment: launch.environment,
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

  static _HeartbeatProcessLaunch _buildLaunch(
    Profile profile,
    List<String> childArguments,
  ) {
    final profileHome = p.normalize(p.absolute(profile.profileHome));
    if (profile.source == ProfileSource.defaultProfile) {
      return _HeartbeatProcessLaunch(
        executable: 'codex',
        arguments: childArguments,
        environment: {'CODEX_HOME': profileHome, 'NO_COLOR': '1'},
      );
    }

    final provider = profileProvider(profile.toolKey);
    final toolDirectory = p.dirname(profileHome);
    if (p.basename(toolDirectory) != provider.multiCliTool) {
      throw StateError(
        'La ubicación del perfil no coincide con su herramienta.',
      );
    }
    return _HeartbeatProcessLaunch(
      executable: 'nini-agents',
      arguments: [
        'exec',
        provider.profileSpec(profile.profileName),
        '--',
        ...childArguments,
      ],
      environment: {'MULTICLI_HOME': p.dirname(toolDirectory), 'NO_COLOR': '1'},
    );
  }
}

final class _HeartbeatProcessLaunch {
  const _HeartbeatProcessLaunch({
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}
