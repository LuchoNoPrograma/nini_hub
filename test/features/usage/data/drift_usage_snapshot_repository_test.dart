import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/usage/data/drift_usage_snapshot_repository.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  late AppDatabase database;
  late DriftUsageSnapshotRepository repository;
  final metadataNow = DateTime.utc(2026, 8, 22, 15);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftUsageSnapshotRepository(database, now: () => metadataNow);
  });

  tearDown(() => database.close());

  test('persists the complete snapshot and initializes metadata', () async {
    await database.into(database.cliProfiles).insert(_profile('primary'));
    final startedAt = DateTime.utc(2026, 8, 22, 10);
    final completedAt = startedAt.add(
      const Duration(seconds: 2, milliseconds: 500),
    );
    final resetAt = DateTime.utc(2026, 8, 29, 10);
    final expiry = DateTime.utc(2026, 9, 1, 10);
    final snapshot = UsageSnapshot(
      status: UsageRefreshStatus.authRequired,
      startedAt: startedAt,
      completedAt: completedAt,
      planType: 'plus',
      accountEmail: '  owner@example.com  ',
      accountDisplayName: 'Owner',
      errorCode: 'AUTH_REQUIRED',
      errorMessage: 'Authentication required',
      rateLimitsReadSucceeded: true,
      windows: [
        UsageQuotaWindow(
          limitId: 'codex',
          windowType: 'secondary',
          limitName: 'Weekly',
          usedPercent: 42.5,
          windowDurationMinutes: 10080,
          resetsAt: resetAt,
          reachedType: 'soft',
          planType: 'plus',
        ),
      ],
      dailyUsage: [
        UsageDailySnapshot(
          day: DateTime.utc(2026, 8, 21),
          tokens: 4200,
          activeMinutes: 18,
          messageCount: 7,
          source: 'codex-app-server',
        ),
      ],
      resetCredits: 3,
      nextCreditExpiry: expiry,
    );

    await repository.saveSnapshot(profileId: 'primary', snapshot: snapshot);

    final check = await database.select(database.usageChecks).getSingle();
    expect(check.profileId, 'primary');
    expect(check.queryMethod, 'codex-app-server');
    expect(check.status, 'auth_required');
    expect(check.startedAt.toUtc(), startedAt);
    expect(check.completedAt?.toUtc(), DateTime.utc(2026, 8, 22, 10, 0, 2));
    expect(check.durationMs, 2500);
    expect(check.planType, 'plus');
    expect(check.accountEmail, '  owner@example.com  ');
    expect(check.accountDisplayName, 'Owner');
    expect(check.errorCode, 'AUTH_REQUIRED');
    expect(check.errorMessage, 'Authentication required');

    final window = await database.select(database.quotaWindows).getSingle();
    expect(window.checkId, check.id);
    expect(window.limitId, 'codex');
    expect(window.limitName, 'Weekly');
    expect(window.windowType, 'secondary');
    expect(window.usedPercent, 42.5);
    expect(window.windowDurationMinutes, 10080);
    expect(window.resetsAt?.toUtc(), resetAt);
    expect(window.reachedType, 'soft');
    expect(window.planType, 'plus');

    final credits = await database
        .select(database.resetCreditSnapshots)
        .getSingle();
    expect(credits.checkId, check.id);
    expect(credits.availableCount, 3);
    expect(credits.nextExpiresAt?.toUtc(), expiry);

    final daily = await database.select(database.dailyUsageBuckets).getSingle();
    expect(daily.checkId, check.id);
    expect(daily.profileId, 'primary');
    expect(daily.day.toUtc(), DateTime.utc(2026, 8, 21));
    expect(daily.tokens, 4200);
    expect(daily.activeMinutes, 18);
    expect(daily.messageCount, 7);
    expect(daily.source, 'codex-app-server');

    final metadata = await database
        .select(database.profileMetadatas)
        .getSingle();
    expect(metadata.accountEmail, 'owner@example.com');
    expect(metadata.accountDisplayName, 'Owner');
    expect(metadata.updatedAt.toUtc(), metadataNow);
    expect(await database.select(database.commandLogs).get(), isEmpty);
  });

  test(
    'does not overwrite existing metadata or create it for blank email',
    () async {
      await database.batch((batch) {
        batch.insertAll(database.cliProfiles, [
          _profile('existing'),
          _profile('blank'),
        ]);
        batch.insert(
          database.profileMetadatas,
          ProfileMetadatasCompanion.insert(
            profileId: 'existing',
            accountEmail: const Value('billing@example.com'),
            accountDisplayName: const Value('Billing'),
            updatedAt: DateTime.utc(2026, 8, 1),
          ),
        );
      });

      await repository.saveSnapshot(
        profileId: 'existing',
        snapshot: _snapshot(email: 'observed@example.com'),
      );
      await repository.saveSnapshot(
        profileId: 'blank',
        snapshot: _snapshot(email: '   '),
      );

      final metadata = await database.select(database.profileMetadatas).get();
      expect(metadata, hasLength(1));
      expect(metadata.single.profileId, 'existing');
      expect(metadata.single.accountEmail, 'billing@example.com');
      final checks = await database.select(database.usageChecks).get();
      expect(
        checks
            .singleWhere((check) => check.profileId == 'existing')
            .accountEmail,
        'observed@example.com',
      );
      expect(
        checks.singleWhere((check) => check.profileId == 'blank').accountEmail,
        '   ',
      );
    },
  );

  test('rolls back every row when one snapshot write fails', () async {
    await database.into(database.cliProfiles).insert(_profile('rollback'));
    await database.customStatement('''
      CREATE TRIGGER fail_usage_window
      BEFORE INSERT ON quota_windows
      BEGIN
        SELECT RAISE(FAIL, 'forced quota failure');
      END
    ''');
    final snapshot = UsageSnapshot(
      status: UsageRefreshStatus.success,
      startedAt: DateTime.utc(2026, 8, 22, 10),
      completedAt: DateTime.utc(2026, 8, 22, 10, 0, 1),
      accountEmail: 'rollback@example.com',
      windows: const [
        UsageQuotaWindow(limitId: 'codex', windowType: 'primary'),
      ],
      dailyUsage: [
        UsageDailySnapshot(
          day: DateTime.utc(2026, 8, 21),
          tokens: 10,
          source: 'provider',
        ),
      ],
    );

    await expectLater(
      repository.saveSnapshot(profileId: 'rollback', snapshot: snapshot),
      throwsA(anything),
    );

    expect(await database.select(database.usageChecks).get(), isEmpty);
    expect(await database.select(database.quotaWindows).get(), isEmpty);
    expect(await database.select(database.resetCreditSnapshots).get(), isEmpty);
    expect(await database.select(database.dailyUsageBuckets).get(), isEmpty);
    expect(await database.select(database.profileMetadatas).get(), isEmpty);
  });
}

UsageSnapshot _snapshot({required String email}) => UsageSnapshot(
  status: UsageRefreshStatus.success,
  startedAt: DateTime.utc(2026, 8, 22, 10),
  completedAt: DateTime.utc(2026, 8, 22, 10, 0, 1),
  accountEmail: email,
);

CliProfile _profile(String id) {
  final now = DateTime.utc(2026, 8, 22);
  return CliProfile(
    id: id,
    toolKey: 'codex',
    profileName: id,
    commandName: 'codex-$id',
    displayName: id,
    profileHome: '/profiles/$id',
    profileSource: 'multicli',
    profileType: 'full',
    hasAuthFile: true,
    isAvailable: true,
    isFavorite: false,
    createdAt: now,
    lastDiscoveredAt: now,
  );
}
