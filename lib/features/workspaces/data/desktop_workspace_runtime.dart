import 'dart:io';

import 'package:path/path.dart' as p;

abstract final class DesktopWorkspaceRuntime {
  static String userHomeDirectory({
    Map<String, String>? environment,
    bool? isWindows,
  }) {
    final values = environment ?? Platform.environment;
    final windows = isWindows ?? Platform.isWindows;
    final home = windows ? values['USERPROFILE'] : values['HOME'];
    if (home == null || home.trim().isEmpty) {
      throw StateError('No se pudo determinar la carpeta de Inicio.');
    }
    return validateWorkingDirectory(home, label: 'La carpeta de Inicio');
  }

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
}
