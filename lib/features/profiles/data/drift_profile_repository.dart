import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/profiles/data/profile_mapper.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

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
