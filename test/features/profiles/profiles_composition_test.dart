import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'production composition completes CRUD through Nini Agents JSON',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nini-hub-profiles-composition-',
      );
      final database = AppDatabase(NativeDatabase.memory());
      await database.saveSetting('profiles_root_path', root.path);
      final runner = _NiniAgentsRunner(database);
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
        RenameProfileCommand(profileId: profileId, name: 'new-team'),
      );

      expect(renamed, isNotNull);
      expect(renamed?.id, profileId);
      expect(renamed?.profileName, 'new-team');
      expect(renamed?.displayName, 'Equipo');
      stored = await (database.select(
        database.cliProfiles,
      )..where((row) => row.id.equals(profileId))).getSingle();
      expect(stored.profileName, 'new-team');
      expect(stored.commandName, 'codex-new-team');
      expect(stored.profileHome, p.join(root.path, 'codex', 'new-team'));

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
      final mutationCalls = runner.calls.where(
        (call) => const {'new', 'rename', 'delete'}.contains(call.arguments[1]),
      );
      expect(mutationCalls.map((call) => call.arguments), [
        ['--json', 'new', 'codex/team', '--shared', '--no-seed'],
        ['--json', 'rename', 'codex/team', 'codex/new-team'],
        ['--json', 'delete', 'codex/new-team', '--confirm', 'codex/new-team'],
      ]);
      expect(
        mutationCalls.map((call) => call.timeout),
        everyElement(const Duration(minutes: 2)),
      );
      expect(
        runner.calls.map((call) => call.executable),
        everyElement('nini-agents'),
      );
      expect(mutationCalls.map((call) => call.stdinText), everyElement(isNull));
    },
  );
}

final class _NiniAgentsRunner extends ProcessRunner {
  _NiniAgentsRunner(super.database);

  final List<({String tool, String name, String type})> profiles = [];
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
    final command = arguments[1];
    late final String data;
    switch (command) {
      case 'new':
        final target = _address(arguments[2]);
        final type = arguments.contains('--shared')
            ? 'shared'
            : arguments.contains('--cli')
            ? 'cli'
            : 'full';
        profiles.add((tool: target.tool, name: target.name, type: type));
        data = _mutationData(target, type: type);
        break;
      case 'rename':
        final source = _address(arguments[2]);
        final target = _address(arguments[3]);
        final old = profiles.singleWhere(
          (profile) =>
              profile.tool == source.tool && profile.name == source.name,
        );
        profiles.remove(old);
        profiles.add((tool: target.tool, name: target.name, type: old.type));
        data = _mutationData(target, type: old.type, from: source);
        break;
      case 'delete':
        final target = _address(arguments[2]);
        profiles.removeWhere(
          (profile) =>
              profile.tool == target.tool && profile.name == target.name,
        );
        data = _mutationData(target);
        break;
      case 'list':
      case 'status':
        profiles.sort((a, b) {
          final byTool = a.tool.compareTo(b.tool);
          return byTool != 0 ? byTool : a.name.compareTo(b.name);
        });
        final items = profiles
            .map(
              (profile) =>
                  '{"tool":"${profile.tool}","name":"${profile.name}",'
                  '"type":"${profile.type}","schemaVersion":2,"sizeBytes":1}',
            )
            .join(',');
        data = '{"profiles":[$items],"count":${profiles.length}}';
        break;
      case 'tools':
        data =
            '{"platform":"linux","tools":['
            '{"id":"codex","kind":"cli","strategy":"accountOverlay","supportLevel":"supported","installed":true}'
            '],"count":1}';
        break;
      default:
        throw StateError('Unexpected command: $command');
    }
    final now = DateTime.now().toUtc();
    return SafeProcessResult(
      exitCode: 0,
      stdout:
          '{"schemaVersion":1,"command":"$command","ok":true,'
          '"data":$data,"error":null}',
      stderr: '',
      startedAt: now,
      completedAt: now,
    );
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

({String tool, String name}) _address(String value) {
  final separator = value.indexOf('/');
  return (
    tool: value.substring(0, separator),
    name: value.substring(separator + 1),
  );
}

String _mutationData(
  ({String tool, String name}) target, {
  String? type,
  ({String tool, String name})? from,
}) {
  final fromJson = from == null
      ? ''
      : '"from":{"tool":"${from.tool}","name":"${from.name}"},';
  final typeJson = type == null ? '' : ',"type":"$type","schemaVersion":2';
  return '{"state":"applied",$fromJson"profile":{'
      '"tool":"${target.tool}","name":"${target.name}"$typeJson}}';
}
