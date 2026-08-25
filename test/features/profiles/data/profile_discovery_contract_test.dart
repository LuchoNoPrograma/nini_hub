import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('maps one discovery result without changing order', () async {
    final rows = [
      _row(id: 'favorite', profileSource: 'default', profileType: 'base'),
      _row(id: 'managed', profileType: 'shared'),
      _row(id: 'inactive', profileType: 'deactivated'),
    ];
    final discovery = _StaticProfileDiscovery(database, rows);

    final profiles = await discovery.discover();

    expect(discovery.calls, 1);
    expect(profiles.map((profile) => profile.id), [
      'favorite',
      'managed',
      'inactive',
    ]);
    expect(profiles[0].source, ProfileSource.defaultProfile);
    expect(profiles[0].kind, ProfileKind.base);
    expect(profiles[1].source, ProfileSource.multiCli);
    expect(profiles[1].kind, ProfileKind.shared);
    expect(profiles[2].kind, ProfileKind.deactivated);
  });

  test('preserves the exact discovery failure', () async {
    final failure = StateError('discovery failed');
    final discovery = _StaticProfileDiscovery(database, const [], failure);

    await expectLater(discovery.discover(), throwsA(same(failure)));
    expect(discovery.calls, 1);
  });
}

final class _StaticProfileDiscovery extends ProfileDiscoveryService {
  _StaticProfileDiscovery(super.database, this.rows, [this.failure])
    : super.test();

  final List<CliProfile> rows;
  final Object? failure;
  int calls = 0;

  @override
  Future<List<CliProfile>> discoverProfiles() async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return rows;
  }
}

CliProfile _row({
  required String id,
  String profileSource = 'multicli',
  String profileType = 'full',
}) => CliProfile(
  id: id,
  toolKey: 'codex',
  profileName: id,
  commandName: 'codex-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  profileSource: profileSource,
  profileType: profileType,
  hasAuthFile: true,
  isAvailable: profileType != 'deactivated',
  isFavorite: id == 'favorite',
  createdAt: DateTime.utc(2025, 1, 2),
  lastDiscoveredAt: DateTime.utc(2025, 2, 3),
);
