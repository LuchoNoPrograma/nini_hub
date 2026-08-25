import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/settings/data/desktop_settings_runtime.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('applies timeout and weekly keepalive through explicit callbacks', () {
    final timeoutValues = <int>[];
    final enabledValues = <bool>[];
    final runtime = DesktopSettingsRuntime(
      discovery: _RecordingDiscovery(database, const []),
      requestTimeoutSetter: timeoutValues.add,
      weeklyKeepAliveEnabledSetter: enabledValues.add,
      monitorWeeklyProfiles: (_) {},
      onProfilesRefreshed: () async {},
    );

    runtime.setRequestTimeoutSeconds(45);
    runtime.setWeeklyKeepAliveEnabled(false);

    expect(timeoutValues, [45]);
    expect(enabledValues, [false]);
  });

  test('refreshes before synchronizing only eligible Codex profiles', () async {
    final discovery = _RecordingDiscovery(database, [
      _profile('eligible'),
      _profile('missing-auth', hasAuthFile: false),
      _profile('unavailable', isAvailable: false),
      _profile('other-tool', toolKey: 'claude'),
    ]);
    var accountsReloads = 0;
    var monitoredIds = <String>[];
    final runtime = DesktopSettingsRuntime(
      discovery: discovery,
      requestTimeoutSetter: (_) {},
      weeklyKeepAliveEnabledSetter: (_) {},
      monitorWeeklyProfiles: (profiles) {
        monitoredIds = profiles.map((profile) => profile.id).toList();
      },
      onProfilesRefreshed: () async => accountsReloads++,
    );

    runtime.syncWeeklyScheduler();
    expect(monitoredIds, isEmpty);

    await runtime.refreshProfiles();
    runtime.syncWeeklyScheduler();

    expect(discovery.calls, 1);
    expect(accountsReloads, 1);
    expect(monitoredIds, ['eligible']);
  });
}

final class _RecordingDiscovery extends ProfileDiscoveryService {
  _RecordingDiscovery(super.database, this.profiles) : super.test();

  final List<CliProfile> profiles;
  int calls = 0;

  @override
  Future<List<CliProfile>> discoverProfiles() async {
    calls++;
    return profiles;
  }
}

CliProfile _profile(
  String id, {
  String toolKey = 'codex',
  bool hasAuthFile = true,
  bool isAvailable = true,
}) {
  final now = DateTime.utc(2026, 8, 22);
  return CliProfile(
    id: id,
    toolKey: toolKey,
    profileName: id,
    commandName: '$toolKey-$id',
    displayName: id,
    profileHome: '/tmp/$id',
    profileSource: 'multicli',
    profileType: 'full',
    hasAuthFile: hasAuthFile,
    isAvailable: isAvailable,
    isFavorite: false,
    createdAt: now,
    lastDiscoveredAt: now,
  );
}
