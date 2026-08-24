import 'package:drift/drift.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/profiles/data/profile_mapper.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_ports.dart';

final class DriftProfileRepository implements ProfileRepository {
  const DriftProfileRepository(this._database);

  final AppDatabase _database;

  @override
  Future<Profile?> findById(String profileId) async {
    final row = await (_database.select(
      _database.cliProfiles,
    )..where((item) => item.id.equals(profileId))).getSingleOrNull();
    return row == null ? null : ProfileMapper.fromRow(row);
  }

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) =>
      (_database.update(
        _database.cliProfiles,
      )..where((row) => row.id.equals(profileId))).write(
        CliProfilesCompanion(
          displayName: Value(displayName),
          isFavorite: Value(isFavorite),
        ),
      );
}
