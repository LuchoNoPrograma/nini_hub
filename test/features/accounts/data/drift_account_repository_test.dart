import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/accounts/data/drift_account_repository.dart';
import 'package:multi_cli_ai/features/accounts/domain/account.dart';

void main() {
  late AppDatabase database;
  late DriftAccountRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftAccountRepository(database);
  });

  tearDown(() => database.close());

  test(
    'loads visible accounts with legacy ordering, fallback, and deduplication',
    () async {
      final latestAt = DateTime.utc(2026, 8, 22, 15);
      final successfulAt = latestAt.subtract(const Duration(hours: 1));
      final oldestAt = latestAt.subtract(const Duration(hours: 2));
      await database.batch((batch) {
        batch.insertAll(database.cliProfiles, [
          _profile(
            id: 'codex-zeta',
            toolKey: 'codex',
            displayName: 'Zeta',
            source: 'multicli',
            now: oldestAt,
          ),
          _profile(
            id: 'claude-favorite',
            toolKey: 'claude-cli',
            displayName: 'Mu',
            source: 'multicli',
            favorite: true,
            now: oldestAt,
          ),
          _profile(
            id: 'hidden-claude-default',
            toolKey: 'claude-cli',
            displayName: 'Hidden',
            source: 'default',
            favorite: true,
            now: oldestAt,
          ),
          _profile(
            id: 'unsupported',
            toolKey: 'other',
            displayName: 'Other',
            source: 'multicli',
            now: oldestAt,
          ),
        ]);
        batch.insert(
          database.profileMetadatas,
          _metadata('codex-zeta', email: 'owner@example.com', now: latestAt),
        );
        batch.insertAll(database.costShares, [
          _share(id: 'zoe', profileId: 'codex-zeta', personName: 'Zoe'),
          _share(id: 'ana', profileId: 'codex-zeta', personName: 'Ana'),
        ]);
        batch.insertAll(database.usageChecks, [
          _check(
            id: 'old-success',
            profileId: 'codex-zeta',
            status: 'success',
            startedAt: oldestAt,
          ),
          _check(
            id: 'latest-success',
            profileId: 'codex-zeta',
            status: 'success',
            startedAt: successfulAt,
          ),
          _check(
            id: 'current-error',
            profileId: 'codex-zeta',
            status: 'error',
            startedAt: latestAt,
            errorCode: 'NETWORK_ERROR',
          ),
        ]);
      });
      await database.batch((batch) {
        batch.insertAll(database.quotaWindows, [
          _window(
            id: 'current-first',
            checkId: 'current-error',
            limitId: 'Codex',
            type: 'primary',
            used: 25,
            duration: 300,
          ),
          _window(
            id: 'current-duplicate',
            checkId: 'current-error',
            limitId: 'codex',
            type: 'primary',
            used: 80,
            duration: 600,
          ),
          _window(
            id: 'current-secondary',
            checkId: 'current-error',
            limitId: 'codex',
            type: 'secondary',
            used: 40,
            duration: 10080,
          ),
          _window(
            id: 'successful-weekly',
            checkId: 'latest-success',
            limitId: 'codex',
            type: 'secondary',
            used: 12,
            duration: 10080,
          ),
        ]);
        batch.insert(
          database.resetCreditSnapshots,
          ResetCreditSnapshot(
            checkId: 'latest-success',
            availableCount: 7,
            nextExpiresAt: latestAt.add(const Duration(days: 2)),
          ),
        );
      });

      final accounts = await repository.loadAll();

      expect(accounts.map((account) => account.profile.id), [
        'claude-favorite',
        'codex-zeta',
      ]);
      final account = accounts.last;
      expect(account.metadata?.accountEmail, 'owner@example.com');
      expect(account.costShares.map((share) => share.personName), [
        'Ana',
        'Zoe',
      ]);
      expect(
        account.currentCheck?.startedAt.millisecondsSinceEpoch,
        latestAt.millisecondsSinceEpoch,
      );
      expect(account.currentCheck?.state, AccountUsageState.error);
      expect(account.currentIssue, AccountUsageIssue.network);
      expect(
        account.lastSuccessfulCheck?.startedAt.millisecondsSinceEpoch,
        successfulAt.millisecondsSinceEpoch,
      );
      expect(account.currentWindows, hasLength(2));
      expect(account.currentWindows.first.usedPercent, 25);
      expect(account.visibleWindows, hasLength(1));
      expect(account.visibleWindows.single.usedPercent, 12);
      expect(account.resetCredits?.availableCount, 7);
    },
  );

  test('findById respects account visibility and missing profiles', () async {
    final now = DateTime.utc(2026, 8, 22);
    await database.batch((batch) {
      batch.insertAll(database.cliProfiles, [
        _profile(
          id: 'visible',
          toolKey: 'codex',
          displayName: 'Visible',
          source: 'default',
          now: now,
        ),
        _profile(
          id: 'hidden',
          toolKey: 'claude-cli',
          displayName: 'Hidden',
          source: 'default',
          now: now,
        ),
      ]);
    });

    expect((await repository.findById('visible'))?.profile.id, 'visible');
    expect(await repository.findById('hidden'), isNull);
    expect(await repository.findById('missing'), isNull);
  });

  test('loadAll uses a constant maximum of seven selects', () async {
    await database.close();
    final counter = _SelectCounter();
    database = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    repository = DriftAccountRepository(database);
    final now = DateTime.utc(2026, 8, 22);
    await _insertCompleteAccount(database, id: 'account-0', now: now);

    counter.selects = 0;
    expect(await repository.loadAll(), hasLength(1));
    expect(counter.selects, 7);

    for (var index = 1; index < 6; index++) {
      await _insertCompleteAccount(
        database,
        id: 'account-$index',
        now: now.add(Duration(minutes: index)),
      );
    }
    counter.selects = 0;
    expect(await repository.loadAll(), hasLength(6));
    expect(counter.selects, 7);
  });

  test(
    'saveDetails normalizes values and replaces shares atomically',
    () async {
      final before = DateTime.now().toUtc();
      await database
          .into(database.cliProfiles)
          .insert(
            _profile(
              id: 'account',
              toolKey: 'codex',
              displayName: 'Account',
              source: 'multicli',
              now: before,
            ),
          );
      await database
          .into(database.profileMetadatas)
          .insert(_metadata('account', email: 'old@example.com', now: before));
      await database
          .into(database.costShares)
          .insert(_share(id: 'old', profileId: 'account', personName: 'Old'));
      final purchasedOn = DateTime.utc(2026, 7, 1);

      await repository.saveDetails(
        AccountDetails(
          profileId: 'account',
          metadata: AccountMetadata(
            accountEmail: ' owner@example.com ',
            accountDisplayName: ' Owner ',
            planName: ' Team ',
            notes: ' Notes ',
            purchasedOn: purchasedOn,
            nextRenewalOn: null,
            billingInterval: 'yearly',
            expectedAmountMinor: 12345,
            currencyCode: ' bob ',
            autoRenew: false,
            subscriptionStatus: 'paused',
            purchasedFrom: ' Store ',
            paymentMethodLabel: ' Visa ',
          ),
          costShares: const [
            AccountCostShare(
              id: 'blank',
              personName: '   ',
              expectedAmountMinor: 0,
              paidAmountMinor: 0,
              currencyCode: 'usd',
              paymentStatus: 'pending',
              paidOn: null,
              notes: '',
            ),
            AccountCostShare(
              id: 'new',
              personName: ' Bea ',
              expectedAmountMinor: 5000,
              paidAmountMinor: 2500,
              currencyCode: ' bob ',
              paymentStatus: 'partial',
              paidOn: null,
              notes: ' Half ',
            ),
          ],
        ),
      );
      final after = DateTime.now().toUtc();

      final metadata = await database
          .select(database.profileMetadatas)
          .getSingle();
      final shares = await database.select(database.costShares).get();
      expect(metadata.accountEmail, 'owner@example.com');
      expect(metadata.accountDisplayName, 'Owner');
      expect(metadata.planName, 'Team');
      expect(metadata.notes, 'Notes');
      expect(metadata.currencyCode, 'BOB');
      expect(metadata.purchasedFrom, 'Store');
      expect(metadata.paymentMethodLabel, 'Visa');
      expect(
        metadata.purchasedOn?.millisecondsSinceEpoch,
        purchasedOn.millisecondsSinceEpoch,
      );
      expect(
        metadata.updatedAt.millisecondsSinceEpoch,
        inInclusiveRange(
          before.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
          after.millisecondsSinceEpoch,
        ),
      );
      expect(shares, hasLength(1));
      expect(shares.single.id, 'new');
      expect(shares.single.personName, 'Bea');
      expect(shares.single.currencyCode, 'BOB');
      expect(shares.single.notes, 'Half');
    },
  );

  test(
    'saveDetails rolls metadata and shares back on duplicate share',
    () async {
      final now = DateTime.utc(2026, 8, 22);
      await database
          .into(database.cliProfiles)
          .insert(
            _profile(
              id: 'account',
              toolKey: 'codex',
              displayName: 'Account',
              source: 'multicli',
              now: now,
            ),
          );
      await database
          .into(database.profileMetadatas)
          .insert(_metadata('account', email: 'old@example.com', now: now));
      await database
          .into(database.costShares)
          .insert(_share(id: 'old', profileId: 'account', personName: 'Old'));

      await expectLater(
        repository.saveDetails(
          AccountDetails(
            profileId: 'account',
            metadata: _domainMetadata(email: 'new@example.com'),
            costShares: const [
              AccountCostShare(
                id: 'duplicate',
                personName: 'One',
                expectedAmountMinor: 100,
                paidAmountMinor: 0,
                currencyCode: 'USD',
                paymentStatus: 'pending',
                paidOn: null,
                notes: '',
              ),
              AccountCostShare(
                id: 'duplicate',
                personName: 'Two',
                expectedAmountMinor: 200,
                paidAmountMinor: 0,
                currencyCode: 'USD',
                paymentStatus: 'pending',
                paidOn: null,
                notes: '',
              ),
            ],
          ),
        ),
        throwsA(anything),
      );

      final metadata = await database
          .select(database.profileMetadatas)
          .getSingle();
      final shares = await database.select(database.costShares).get();
      expect(metadata.accountEmail, 'old@example.com');
      expect(shares.single.id, 'old');
    },
  );
}

final class _SelectCounter extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return super.runSelect(executor, statement, args);
  }
}

Future<void> _insertCompleteAccount(
  AppDatabase database, {
  required String id,
  required DateTime now,
}) async {
  final checkId = '$id-check';
  await database.batch((batch) {
    batch.insert(
      database.cliProfiles,
      _profile(
        id: id,
        toolKey: 'codex',
        displayName: id,
        source: 'multicli',
        now: now,
      ),
    );
    batch.insert(
      database.profileMetadatas,
      _metadata(id, email: '$id@example.com', now: now),
    );
    batch.insert(database.costShares, _share(id: '$id-share', profileId: id));
    batch.insert(
      database.usageChecks,
      _check(id: checkId, profileId: id, status: 'success', startedAt: now),
    );
  });
  await database.batch((batch) {
    batch.insert(
      database.quotaWindows,
      _window(
        id: '$id-window',
        checkId: checkId,
        limitId: id,
        type: 'primary',
        used: 10,
        duration: 300,
      ),
    );
    batch.insert(
      database.resetCreditSnapshots,
      ResetCreditSnapshot(checkId: checkId, availableCount: 1),
    );
  });
}

CliProfile _profile({
  required String id,
  required String toolKey,
  required String displayName,
  required String source,
  required DateTime now,
  bool favorite = false,
}) => CliProfile(
  id: id,
  toolKey: toolKey,
  profileName: id,
  commandName: '$toolKey-$id',
  displayName: displayName,
  profileHome: '/profiles/$id',
  profileSource: source,
  profileType: 'full',
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: favorite,
  createdAt: now,
  lastDiscoveredAt: now,
);

UsageCheck _check({
  required String id,
  required String profileId,
  required String status,
  required DateTime startedAt,
  String? errorCode,
}) => UsageCheck(
  id: id,
  profileId: profileId,
  queryMethod: 'test',
  status: status,
  startedAt: startedAt,
  errorCode: errorCode,
);

ProfileMetadata _metadata(
  String profileId, {
  required String email,
  required DateTime now,
}) => ProfileMetadata(
  profileId: profileId,
  accountEmail: email,
  accountDisplayName: '',
  planName: '',
  notes: '',
  tagsJson: '[]',
  billingInterval: 'monthly',
  expectedAmountMinor: 0,
  currencyCode: 'USD',
  autoRenew: true,
  subscriptionStatus: 'active',
  purchasedFrom: '',
  paymentMethodLabel: '',
  updatedAt: now,
);

CostShare _share({
  required String id,
  required String profileId,
  String personName = 'Person',
}) => CostShare(
  id: id,
  profileId: profileId,
  personName: personName,
  expectedAmountMinor: 100,
  paidAmountMinor: 0,
  currencyCode: 'USD',
  paymentStatus: 'pending',
  notes: '',
);

QuotaWindow _window({
  required String id,
  required String checkId,
  required String limitId,
  required String type,
  required double used,
  required int duration,
}) => QuotaWindow(
  id: id,
  checkId: checkId,
  limitId: limitId,
  windowType: type,
  usedPercent: used,
  windowDurationMinutes: duration,
);

AccountMetadata _domainMetadata({required String email}) => AccountMetadata(
  accountEmail: email,
  accountDisplayName: '',
  planName: '',
  notes: '',
  purchasedOn: null,
  nextRenewalOn: null,
  billingInterval: 'monthly',
  expectedAmountMinor: 0,
  currencyCode: 'USD',
  autoRenew: true,
  subscriptionStatus: 'active',
  purchasedFrom: '',
  paymentMethodLabel: '',
);
