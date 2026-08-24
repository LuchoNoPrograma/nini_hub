import 'dart:io';

import 'package:drift/drift.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/profiles/domain/agent_profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_provider.dart';
import 'package:path/path.dart' as p;

class MultiCliGateway {
  MultiCliGateway(this.database, this.runner);

  final AppDatabase database;
  final ProcessRunner runner;

  static final RegExp _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$');

  String get userHomeDirectory {
    final environment = Platform.environment;
    final home = Platform.isWindows
        ? environment['USERPROFILE']
        : environment['HOME'];
    if (home == null || home.trim().isEmpty) {
      throw StateError('No se pudo determinar la carpeta de Inicio.');
    }
    return validateWorkingDirectory(home, label: 'La carpeta de Inicio');
  }

  static String _validateName(String raw) {
    final name = raw.trim();
    if (!_safeName.hasMatch(name)) {
      throw const FormatException(
        'Usa entre 1 y 48 caracteres: letras, números, guion o guion bajo.',
      );
    }
    return name;
  }

  Future<SafeProcessResult> createProfile({
    required String toolKey,
    required ProfileName profileName,
    required ProfileSetupMode setupMode,
    required bool seedFromBase,
  }) async {
    final name = _validateName(profileName.value);
    final provider = profileProvider(toolKey);
    final args = <String>['new', provider.profileSpec(name)];
    if (setupMode == ProfileSetupMode.shared) args.add('--shared');
    if (setupMode == ProfileSetupMode.cli) args.add('--cli');
    if (!seedFromBase) args.add('--no-seed');
    final result = await runner.run(
      executable: 'multi-cli',
      arguments: args,
      summary: 'Crear perfil ${provider.productName} $name',
      timeout: const Duration(minutes: 2),
    );
    if (!result.succeeded) {
      throw StateError(
        result.combinedOutput.isEmpty
            ? 'Multi CLI no pudo crear el perfil.'
            : result.combinedOutput,
      );
    }
    return result;
  }

  Future<SafeProcessResult> renameProfile(
    Profile profile,
    ProfileName profileName,
  ) => _rename(
    id: profile.id,
    toolKey: profile.toolKey,
    currentName: profile.profileName,
    currentHome: profile.profileHome,
    profileSource: profile.source == ProfileSource.multiCli
        ? 'multicli'
        : 'default',
    rawName: profileName.value,
  );

  Future<SafeProcessResult> _rename({
    required String id,
    required String toolKey,
    required String currentName,
    required String currentHome,
    required String profileSource,
    required String rawName,
  }) async {
    if (profileSource != 'multicli') {
      throw StateError(
        'El perfil principal no puede renombrarse con Multi CLI.',
      );
    }
    final name = _validateName(rawName);
    final provider = profileProvider(toolKey);
    if (name == currentName) {
      throw StateError('El nombre físico no cambió.');
    }
    final result = await runner.run(
      executable: 'multi-cli',
      arguments: [
        'rename',
        provider.profileSpec(currentName),
        provider.profileSpec(name),
      ],
      summary: 'Renombrar $currentName a $name',
      profileId: id,
      timeout: const Duration(minutes: 2),
    );
    if (!result.succeeded) throw StateError(result.combinedOutput);

    final newHome = p.join(p.dirname(currentHome), name);
    await (database.update(
      database.cliProfiles,
    )..where((row) => row.id.equals(id))).write(
      CliProfilesCompanion(
        profileName: Value(name),
        commandName: Value(provider.commandName(name)),
        profileHome: Value(newHome),
        lastDiscoveredAt: Value(DateTime.now().toUtc()),
      ),
    );
    return result;
  }

  Future<SafeProcessResult> deleteProfile(Profile profile) => _delete(
    id: profile.id,
    toolKey: profile.toolKey,
    profileName: profile.profileName,
    profileSource: profile.source == ProfileSource.multiCli
        ? 'multicli'
        : 'default',
  );

  Future<SafeProcessResult> _delete({
    required String id,
    required String toolKey,
    required String profileName,
    required String profileSource,
  }) async {
    if (profileSource != 'multicli') {
      throw StateError(
        'El perfil principal no se elimina desde esta aplicación.',
      );
    }
    final provider = profileProvider(toolKey);
    final result = await runner.run(
      executable: 'multi-cli',
      arguments: ['delete', provider.profileSpec(profileName)],
      summary: 'Eliminar perfil $profileName',
      profileId: id,
      stdinText: 'y\n',
      timeout: const Duration(minutes: 2),
    );
    if (!result.succeeded) throw StateError(result.combinedOutput);
    await (database.delete(
      database.cliProfiles,
    )..where((row) => row.id.equals(id))).go();
    return result;
  }

  Future<void> launch(CliProfile profile, {required String workingDirectory}) =>
      _launch(
        id: profile.id,
        toolKey: profile.toolKey,
        profileName: profile.profileName,
        displayName: profile.displayName,
        profileHome: profile.profileHome,
        profileSource: profile.profileSource,
        workingDirectory: workingDirectory,
      );

  Future<void> launchAgentProfile(
    AgentProfile profile, {
    required String workingDirectory,
  }) => _launch(
    id: profile.id,
    toolKey: profile.toolKey,
    profileName: profile.profileName,
    displayName: profile.displayName,
    profileHome: profile.profileHome,
    profileSource: profile.profileSource,
    workingDirectory: workingDirectory,
  );

  Future<void> _launch({
    required String id,
    required String toolKey,
    required String profileName,
    required String displayName,
    required String profileHome,
    required String profileSource,
    required String workingDirectory,
  }) async {
    if (!Directory(profileHome).existsSync()) {
      throw StateError('La carpeta del perfil ya no existe.');
    }
    final launchDirectory = validateWorkingDirectory(
      workingDirectory,
      label: 'La carpeta seleccionada',
    );
    final terminalTitle = buildTerminalTitle(
      profileName: profileName,
      workingDirectory: launchDirectory,
    );
    final provider = profileProvider(toolKey);
    if (profileSource == 'multicli') {
      await runner.startInTerminal(
        executable: 'multi-cli',
        arguments: [
          'launch',
          provider.profileSpec(profileName),
          if (provider.launchArguments.isNotEmpty) ...[
            '--',
            ...provider.launchArguments,
          ],
        ],
        summary: 'Abrir $displayName',
        profileId: id,
        workingDirectory: launchDirectory,
        title: terminalTitle,
      );
    } else {
      await runner.startInTerminal(
        executable: provider.executable,
        arguments: provider.launchArguments,
        summary: 'Abrir ${provider.productName} principal',
        profileId: id,
        workingDirectory: launchDirectory,
        title: terminalTitle,
      );
    }
    await (database.update(
      database.cliProfiles,
    )..where((row) => row.id.equals(id))).write(
      CliProfilesCompanion(lastLaunchedAt: Value(DateTime.now().toUtc())),
    );
  }

  static String buildTerminalTitle({
    required String profileName,
    required String workingDirectory,
  }) {
    final directoryName = p.basename(workingDirectory);
    final directoryLabel = directoryName.isEmpty
        ? workingDirectory
        : directoryName;
    return '$profileName · $directoryLabel';
  }

  Future<void> saveDisplayData({
    required CliProfile profile,
    required String displayName,
    required bool favorite,
  }) =>
      (database.update(
        database.cliProfiles,
      )..where((row) => row.id.equals(profile.id))).write(
        CliProfilesCompanion(
          displayName: Value(
            displayName.trim().isEmpty
                ? profile.profileName
                : displayName.trim(),
          ),
          isFavorite: Value(favorite),
        ),
      );

  static String validateWorkingDirectory(
    String value, {
    String label = 'La carpeta seleccionada',
  }) {
    final directory = Directory(value.trim()).absolute;
    if (!directory.existsSync()) {
      throw StateError('$label no existe.');
    }
    return p.normalize(directory.path);
  }
}
