import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/profiles/application/profile_management.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'production composition completes create rename and delete through ports',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'multicli-ai-profiles-composition-',
      );
      final database = AppDatabase(NativeDatabase.memory());
      await database.saveSetting('profiles_root_path', root.path);
      final runner = _FilesystemMultiCliRunner(database, root.path);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          processRunnerProvider.overrideWithValue(runner),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final controller = container.read(profilesControllerProvider.notifier);

      final created = await controller.create(
        const CreateProfileCommand(
          toolKey: 'codex',
          name: 'team',
          displayName: 'Equipo',
          setupMode: ProfileSetupMode.shared,
          seedFromBase: false,
        ),
      );

      expect(created, isNotNull);
      expect(created?.profileName, 'team');
      expect(created?.displayName, 'Equipo');
      expect(created?.kind, ProfileKind.shared);
      final profileId = created!.id;
      var stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profileId))).getSingle();
      expect(stored.displayName, 'Equipo');
      expect(stored.profileType, 'shared');

      final renamed = await controller.rename(
        RenameProfileCommand(profileId: profileId, name: 'new_team'),
      );

      expect(renamed, isNotNull);
      expect(renamed?.id, profileId);
      expect(renamed?.profileName, 'new_team');
      expect(renamed?.displayName, 'Equipo');
      stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profileId))).getSingle();
      expect(stored.profileName, 'new_team');
      expect(stored.commandName, 'codex-new_team');
      expect(stored.profileHome, p.join(root.path, 'codex', 'new_team'));

      expect(await controller.delete(DeleteProfileCommand(profileId)), isTrue);

      expect(
        container.read(profilesControllerProvider).findById(profileId),
        isNull,
      );
      expect(
        await (database.select(
          database.cliProfiles,
        )..where((row) => row.id.equals(profileId))).getSingleOrNull(),
        isNull,
      );
      expect(runner.calls.map((call) => call.arguments), [
        ['new', 'codex/team', '--shared', '--no-seed'],
        ['rename', 'codex/team', 'codex/new_team'],
        ['delete', 'codex/new_team'],
      ]);
      expect(
        runner.calls.map((call) => call.timeout),
        everyElement(const Duration(minutes: 2)),
      );
      expect(
        runner.calls.map((call) => call.executable),
        everyElement('multi-cli'),
      );
      expect(runner.calls.last.stdinText, 'y\n');
    },
  );
}

final class _FilesystemMultiCliRunner extends ProcessRunner {
  _FilesystemMultiCliRunner(super.database, this.profilesRoot);

  final String profilesRoot;
  final List<_RunCall> calls = [];

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
      _RunCall(
        executable: executable,
        arguments: List.unmodifiable(arguments),
        stdinText: stdinText,
        timeout: timeout,
      ),
    );
    switch (arguments.first) {
      case 'new':
        final directory = Directory(_profilePath(arguments[1]));
        await directory.create(recursive: true);
        if (arguments.contains('--shared')) {
          await File(p.join(directory.path, '.shared')).create();
        } else if (arguments.contains('--cli')) {
          await File(p.join(directory.path, '.cli')).create();
        }
        break;
      case 'rename':
        await Directory(
          _profilePath(arguments[1]),
        ).rename(_profilePath(arguments[2]));
        break;
      case 'delete':
        await Directory(_profilePath(arguments[1])).delete(recursive: true);
        break;
    }
    final now = DateTime.now().toUtc();
    return SafeProcessResult(
      exitCode: 0,
      stdout: '',
      stderr: '',
      startedAt: now,
      completedAt: now,
    );
  }

  String _profilePath(String profileSpec) {
    final parts = profileSpec.split('/');
    return p.join(profilesRoot, parts.first, parts.last);
  }
}

final class _RunCall {
  const _RunCall({
    required this.executable,
    required this.arguments,
    required this.stdinText,
    required this.timeout,
  });

  final String executable;
  final List<String> arguments;
  final String? stdinText;
  final Duration timeout;
}
