import 'package:nini_hub/core/database/database_bootstrap.dart';
import 'package:nini_hub/core/database/legacy_database_migrator.dart';
import 'package:nini_hub/core/process/process_runner.dart';

enum AppStartupFailureKind {
  updateRequired,
  databaseInUse,
  databaseConflict,
  invalidDatabase,
  databaseUnavailable,
  unexpected,
}

final class AppStartupFailure {
  const AppStartupFailure({
    required this.kind,
    required this.title,
    required this.message,
  });

  factory AppStartupFailure.from(Object error) {
    if (error case final LegacyDatabaseMigrationException failure) {
      return _fromLegacyDatabaseMigration(failure.kind);
    }
    if (error case final DatabaseBootstrapException failure) {
      return _fromDatabaseBootstrap(failure.kind);
    }

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
            'Nini Hub y vuelve a abrir la aplicación. Tus datos se '
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

  static AppStartupFailure _fromLegacyDatabaseMigration(
    LegacyDatabaseMigrationFailureKind kind,
  ) => switch (kind) {
    LegacyDatabaseMigrationFailureKind.sourceInUse => const AppStartupFailure(
      kind: AppStartupFailureKind.databaseInUse,
      title: 'Cierra MultiCLI AI',
      message:
          'La base anterior sigue en uso. Cierra MultiCLI AI por completo y '
          'vuelve a abrir Nini Hub para continuar la migración sin riesgo.',
    ),
    LegacyDatabaseMigrationFailureKind.samePath ||
    LegacyDatabaseMigrationFailureKind.destinationConflict =>
      const AppStartupFailure(
        kind: AppStartupFailureKind.databaseConflict,
        title: 'Datos de Nini Hub en conflicto',
        message:
            'Ya existe un destino diferente o la ruta no es segura. Nini Hub '
            'no sobrescribió ningún dato. Revisa la instalación antes de '
            'volver a intentarlo.',
      ),
    LegacyDatabaseMigrationFailureKind.invalidSource ||
    LegacyDatabaseMigrationFailureKind.validationFailed =>
      const AppStartupFailure(
        kind: AppStartupFailureKind.invalidDatabase,
        title: 'No se pudo validar la base anterior',
        message:
            'La base local no coincide con el formato esperado o no superó '
            'las comprobaciones de integridad. El origen se conservó sin '
            'reemplazar el destino.',
      ),
    LegacyDatabaseMigrationFailureKind.sourceMissing ||
    LegacyDatabaseMigrationFailureKind.exportFailed ||
    LegacyDatabaseMigrationFailureKind.activationFailed ||
    LegacyDatabaseMigrationFailureKind.temporaryCleanupFailed =>
      const AppStartupFailure(
        kind: AppStartupFailureKind.databaseUnavailable,
        title: 'No se pudo preparar la base local',
        message:
            'La migración no pudo completarse de forma segura. No se '
            'sobrescribió la base de Nini Hub; vuelve a abrir la aplicación '
            'cuando el almacenamiento esté disponible.',
      ),
  };

  static AppStartupFailure _fromDatabaseBootstrap(
    DatabaseBootstrapFailureKind kind,
  ) => switch (kind) {
    DatabaseBootstrapFailureKind.destinationConflict => const AppStartupFailure(
      kind: AppStartupFailureKind.databaseConflict,
      title: 'Datos de Nini Hub en conflicto',
      message:
          'La ruta de datos de Nini Hub contiene un destino que no es una '
          'base SQLite regular. No se sobrescribió ningún archivo.',
    ),
    DatabaseBootstrapFailureKind.unsupportedPlatform => const AppStartupFailure(
      kind: AppStartupFailureKind.databaseUnavailable,
      title: 'Plataforma no compatible',
      message:
          'La migración local de Nini Hub está disponible únicamente en '
          'Linux y Windows.',
    ),
    DatabaseBootstrapFailureKind.supportDirectoryUnavailable ||
    DatabaseBootstrapFailureKind.databaseOpenFailed => const AppStartupFailure(
      kind: AppStartupFailureKind.databaseUnavailable,
      title: 'No se pudo abrir la base local',
      message:
          'Nini Hub no pudo preparar su almacenamiento local. Comprueba '
          'los permisos y el espacio disponible, y vuelve a abrir la '
          'aplicación.',
    ),
  };
}
