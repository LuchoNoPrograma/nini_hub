import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/accounts/data/drift_account_authentication_store.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';

void main() {
  late AppDatabase database;
  late DriftAccountAuthenticationStore store;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftAccountAuthenticationStore(database);
  });

  tearDown(() => database.close());

  test('marks only the confirmed profile and is idempotent', () async {
    final now = DateTime.utc(2026, 8, 24);
    await database.batch((batch) {
      batch.insertAll(database.cliProfiles, [
        _profile(id: 'confirmed', now: now),
        _profile(id: 'other', now: now),
      ]);
    });

    await store.markAuthenticated('confirmed');
    await store.markAuthenticated('confirmed');

    final profiles = await database.select(database.cliProfiles).get();
    expect(
      profiles.singleWhere((profile) => profile.id == 'confirmed').hasAuthFile,
      isTrue,
    );
    expect(
      profiles.singleWhere((profile) => profile.id == 'other').hasAuthFile,
      isFalse,
    );
  });

  test('reports a missing confirmed profile with a typed failure', () async {
    await expectLater(
      store.markAuthenticated('missing'),
      throwsA(
        isA<AccountNotFoundFailure>().having(
          (failure) => failure.profileId,
          'profileId',
          'missing',
        ),
      ),
    );
  });
}

CliProfile _profile({required String id, required DateTime now}) => CliProfile(
  id: id,
  toolKey: 'codex',
  profileName: id,
  commandName: 'codex-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  profileSource: 'multicli',
  profileType: 'full',
  hasAuthFile: false,
  isAvailable: true,
  isFavorite: false,
  createdAt: now,
  lastDiscoveredAt: now,
);
