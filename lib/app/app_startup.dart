import 'package:multi_cli_ai/core/process/process_runner.dart';

enum AppStartupFailureKind { updateRequired, unexpected }

final class AppStartupFailure {
  const AppStartupFailure({
    required this.kind,
    required this.title,
    required this.message,
  });

  factory AppStartupFailure.from(Object error) {
    final details = ProcessRunner.sanitizeOutput(error.toString());
    final normalized = details.toLowerCase();
    final needsDatabaseMigration =
        normalized.contains('bumped the schema version') &&
        (normalized.contains('migration') ||
            normalized.contains('schema updates'));

    if (needsDatabaseMigration) {
      return const AppStartupFailure(
        kind: AppStartupFailureKind.updateRequired,
        title: 'Ejecutable desactualizado',
        message:
            'Este ejecutable no incluye la actualización necesaria para abrir '
            'tu base de datos local. Instala la versión más reciente de '
            'MultiCLI AI y vuelve a abrir la aplicación. Tus datos se '
            'conservarán.',
      );
    }

    return AppStartupFailure(
      kind: AppStartupFailureKind.unexpected,
      title: 'No se pudo iniciar',
      message: details,
    );
  }

  final AppStartupFailureKind kind;
  final String title;
  final String message;
}
