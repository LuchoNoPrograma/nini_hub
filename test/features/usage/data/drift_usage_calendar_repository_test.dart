import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/usage/data/drift_usage_calendar_repository.dart';

void main() {
  late _SelectCounter selects;
  late AppDatabase database;
  late DriftUsageCalendarRepository repository;

  setUp(() {
    selects = _SelectCounter();
    database = AppDatabase(NativeDatabase.memory().interceptWith(selects));
    repository = DriftUsageCalendarRepository(database);
  });

  tearDown(() => database.close());

  test(
    'loads the legacy calendar projection with one aggregate select',
    () async {
      final primary = _profile('primary', displayName: 'Zulu');
      final secondary = _profile('secondary', displayName: 'Alpha');
      await database.batch((batch) {
        batch.insertAll(database.cliProfiles, [primary, secondary]);
        batch.insert(
          database.profileMetadatas,
          ProfileMetadatasCompanion.insert(
            profileId: primary.id,
            accountEmail: const Value('billing@example.com'),
            accountDisplayName: const Value('Billing'),
            nextRenewalOn: Value(DateTime.utc(2026, 8, 15, 12)),
            updatedAt: DateTime.utc(2026, 8, 1),
          ),
        );
      });
      final checkedAt = DateTime.utc(2026, 8, 13, 12);
      final resetAt = DateTime.utc(2026, 8, 14, 12);
      await database.batch((batch) {
        batch.insertAll(database.usageChecks, [
          _check(
            id: 'primary-success',
            profileId: primary.id,
            status: 'success',
            startedAt: checkedAt,
            email: 'observed-primary@example.com',
          ),
          _check(
            id: 'primary-error',
            profileId: primary.id,
            status: 'error',
            startedAt: checkedAt.add(const Duration(minutes: 1)),
          ),
          _check(
            id: 'secondary-partial',
            profileId: secondary.id,
            status: 'partial',
            startedAt: checkedAt.add(const Duration(minutes: 2)),
            email: 'observed-secondary@example.com',
          ),
        ]);
        batch.insertAll(database.quotaWindows, [
          _window(
            id: 'primary-window-1',
            checkId: 'primary-success',
            used: 20,
            resetAt: resetAt,
          ),
          _window(
            id: 'primary-window-2',
            checkId: 'primary-error',
            used: 90,
            resetAt: resetAt,
          ),
          _window(
            id: 'secondary-window',
            checkId: 'secondary-partial',
            used: 40,
            resetAt: resetAt,
          ),
        ]);
        batch.insertAll(database.dailyUsageBuckets, [
          _bucket(
            id: 'primary-low',
            checkId: 'primary-success',
            profileId: primary.id,
            tokens: 100,
          ),
          _bucket(
            id: 'primary-high',
            checkId: 'primary-error',
            profileId: primary.id,
            tokens: 150,
          ),
          _bucket(
            id: 'secondary',
            checkId: 'secondary-partial',
            profileId: secondary.id,
            tokens: 70,
          ),
        ]);
      });

      selects.reset();
      final calendar = await repository.loadCalendar();

      expect(selects.statements, hasLength(1));
      expect(
        selects.statements.single,
        contains('GROUP BY profile_id, day_key'),
      );
      final usageDay = calendar[DateTime(2026, 8, 13)]!;
      expect(usageDay.tokens, 220);
      expect(usageDay.successfulChecks, 2);
      expect(usageDay.failedChecks, 1);
      expect(usageDay.lowestRemaining, 10);
      expect(usageDay.accounts.map((account) => account.profileId), [
        primary.id,
        secondary.id,
      ]);
      expect(usageDay.accounts.first.tokens, 150);
      expect(usageDay.accounts.first.successfulChecks, 1);
      expect(usageDay.accounts.first.failedChecks, 1);
      expect(usageDay.accounts.first.email, 'billing@example.com');
      expect(usageDay.accounts.last.tokens, 70);
      expect(usageDay.accounts.last.successfulChecks, 1);
      expect(usageDay.accounts.last.failedChecks, 0);
      expect(usageDay.accounts.last.email, 'observed-secondary@example.com');

      final resetDay = calendar[DateTime(2026, 8, 14)]!;
      expect(resetDay.resetCount, 2);
      expect(resetDay.accounts.map((account) => account.resetCount), [1, 1]);
      final renewalDay = calendar[DateTime(2026, 8, 15)]!;
      expect(renewalDay.renewalCount, 1);
      expect(renewalDay.accounts.single.profileId, primary.id);
    },
  );

  test('empty history returns an immutable empty calendar', () async {
    selects.reset();

    final calendar = await repository.loadCalendar();

    expect(selects.statements, hasLength(1));
    expect(calendar.days, isEmpty);
    expect(calendar.days.clear, throwsUnsupportedError);
  });
}

final class _SelectCounter extends QueryInterceptor {
  final List<String> statements = [];

  void reset() => statements.clear();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

CliProfile _profile(String id, {required String displayName}) {
  final now = DateTime.utc(2026, 8, 13);
  return CliProfile(
    id: id,
    toolKey: 'codex',
    profileName: id,
    commandName: 'codex-$id',
    displayName: displayName,
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

UsageCheck _check({
  required String id,
  required String profileId,
  required String status,
  required DateTime startedAt,
  String? email,
}) => UsageCheck(
  id: id,
  profileId: profileId,
  queryMethod: 'test',
  status: status,
  startedAt: startedAt,
  accountEmail: email,
);

QuotaWindow _window({
  required String id,
  required String checkId,
  required double used,
  required DateTime resetAt,
}) => QuotaWindow(
  id: id,
  checkId: checkId,
  limitId: 'codex',
  windowType: 'primary',
  usedPercent: used,
  resetsAt: resetAt,
);

DailyUsageBucket _bucket({
  required String id,
  required String checkId,
  required String profileId,
  required int tokens,
}) => DailyUsageBucket(
  id: id,
  checkId: checkId,
  profileId: profileId,
  day: DateTime.utc(2026, 8, 13),
  tokens: tokens,
  source: 'provider',
);
