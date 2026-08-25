import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';

final class DriftAccountAuthenticationStore
    implements AccountAuthenticationStore {
  const DriftAccountAuthenticationStore(this._database);

  final AppDatabase _database;

  @override
  Future<void> markAuthenticated(String profileId) async {
    final updated =
        await (_database.update(_database.cliProfiles)
              ..where((profile) => profile.id.equals(profileId)))
            .write(const CliProfilesCompanion(hasAuthFile: Value(true)));
    if (updated != 1) throw AccountNotFoundFailure(profileId);
  }
}
