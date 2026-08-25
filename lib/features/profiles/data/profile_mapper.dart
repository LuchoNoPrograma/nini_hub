import 'package:nini_hub/core/database/app_database.dart' as db;
import 'package:nini_hub/features/profiles/domain/profile.dart';

abstract final class ProfileMapper {
  static Profile fromRow(db.CliProfile row) => Profile(
    id: row.id,
    toolKey: row.toolKey,
    profileName: row.profileName,
    commandName: row.commandName,
    displayName: row.displayName,
    profileHome: row.profileHome,
    source: _source(row.profileSource),
    kind: _kind(row.profileType),
    hasAuthFile: row.hasAuthFile,
    isAvailable: row.isAvailable,
    isFavorite: row.isFavorite,
  );

  static ProfileSource _source(String value) => switch (value) {
    'default' => ProfileSource.defaultProfile,
    'multicli' => ProfileSource.multiCli,
    _ => throw StateError('Fuente de perfil persistida no compatible: $value'),
  };

  static ProfileKind _kind(String value) => switch (value) {
    'base' => ProfileKind.base,
    'full' => ProfileKind.full,
    'shared' => ProfileKind.shared,
    'cli' => ProfileKind.cli,
    'isolated' => ProfileKind.isolated,
    'deactivated' => ProfileKind.deactivated,
    _ => throw StateError('Tipo de perfil persistido no compatible: $value'),
  };
}
