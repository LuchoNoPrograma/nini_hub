import 'package:drift/drift.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/accounts/data/account_mapper.dart';
import 'package:multi_cli_ai/features/accounts/domain/account.dart';
import 'package:multi_cli_ai/features/accounts/domain/account_repository.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_provider.dart';

final class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository(this.database);

  final AppDatabase database;

  @override
  Future<List<Account>> loadAll() => _load();

  @override
  Future<Account?> findById(String profileId) async {
    final accounts = await _load(profileId: profileId);
    return accounts.firstOrNull;
  }

  @override
  Future<void> saveDetails(AccountDetails details) async {
    final normalized = details.normalizedForSave();
    final metadata = normalized.metadata;
    await database.transaction(() async {
      await database
          .into(database.profileMetadatas)
          .insertOnConflictUpdate(
            ProfileMetadatasCompanion.insert(
              profileId: normalized.profileId,
              accountEmail: Value(metadata.accountEmail),
              accountDisplayName: Value(metadata.accountDisplayName),
              planName: Value(metadata.planName),
              notes: Value(metadata.notes),
              purchasedOn: Value(metadata.purchasedOn),
              nextRenewalOn: Value(metadata.nextRenewalOn),
              billingInterval: Value(metadata.billingInterval),
              expectedAmountMinor: Value(metadata.expectedAmountMinor),
              currencyCode: Value(metadata.currencyCode),
              autoRenew: Value(metadata.autoRenew),
              subscriptionStatus: Value(metadata.subscriptionStatus),
              purchasedFrom: Value(metadata.purchasedFrom),
              paymentMethodLabel: Value(metadata.paymentMethodLabel),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      await (database.delete(
        database.costShares,
      )..where((row) => row.profileId.equals(normalized.profileId))).go();
      if (normalized.costShares.isNotEmpty) {
        await database.batch((batch) {
          batch.insertAll(
            database.costShares,
            normalized.costShares
                .map(
                  (share) => CostSharesCompanion.insert(
                    id: share.id,
                    profileId: normalized.profileId,
                    personName: share.personName,
                    expectedAmountMinor: Value(share.expectedAmountMinor),
                    paidAmountMinor: Value(share.paidAmountMinor),
                    currencyCode: Value(share.currencyCode),
                    paymentStatus: Value(share.paymentStatus),
                    paidOn: Value(share.paidOn),
                    notes: Value(share.notes),
                  ),
                )
                .toList(),
          );
        });
      }
    });
  }

  Future<List<Account>> _load({String? profileId}) async {
    final profilesQuery = database.select(database.cliProfiles)
      ..orderBy([
        (row) => OrderingTerm.desc(row.isFavorite),
        (row) => OrderingTerm.asc(row.toolKey),
        (row) => OrderingTerm.asc(row.displayName),
      ]);
    profilesQuery.where((row) {
      Expression<bool> visible = const Constant(false);
      for (final provider in supportedProfileProviders) {
        final visibleSource = provider.showsDefaultProfile
            ? const Constant(true)
            : row.profileSource.isNotValue('default');
        visible =
            visible | (row.toolKey.equals(provider.toolKey) & visibleSource);
      }
      return visible;
    });
    if (profileId != null) {
      profilesQuery.where((row) => row.id.equals(profileId));
    }
    final profiles = await profilesQuery.get();
    if (profiles.isEmpty) return const [];

    final profileIds = profiles.map((profile) => profile.id).toList();
    final metadata = await (database.select(
      database.profileMetadatas,
    )..where((row) => row.profileId.isIn(profileIds))).get();
    final shares =
        await (database.select(database.costShares)
              ..where((row) => row.profileId.isIn(profileIds))
              ..orderBy([(row) => OrderingTerm.asc(row.personName)]))
            .get();
    final currentChecks = await _latestChecks(profileIds);
    final successfulChecks = await _latestChecks(
      profileIds,
      successfulOnly: true,
    );
    final selectedCheckIds = {
      ...currentChecks.map((check) => check.id),
      ...successfulChecks.map((check) => check.id),
    };
    final windows = selectedCheckIds.isEmpty
        ? const <QuotaWindow>[]
        : await (database.select(database.quotaWindows)
                ..where((row) => row.checkId.isIn(selectedCheckIds))
                ..orderBy([
                  (row) => OrderingTerm.asc(row.windowDurationMinutes),
                  (row) => OrderingTerm.asc(row.limitId),
                ]))
              .get();
    final successfulIds = successfulChecks.map((check) => check.id).toList();
    final credits = successfulIds.isEmpty
        ? const <ResetCreditSnapshot>[]
        : await (database.select(
            database.resetCreditSnapshots,
          )..where((row) => row.checkId.isIn(successfulIds))).get();

    final metadataByProfile = {
      for (final item in metadata) item.profileId: item,
    };
    final sharesByProfile = _groupBy(shares, (share) => share.profileId);
    final currentByProfile = {
      for (final check in currentChecks) check.profileId: check,
    };
    final successfulByProfile = {
      for (final check in successfulChecks) check.profileId: check,
    };
    final windowsByCheck = _deduplicatedWindows(windows);
    final creditsByCheck = {
      for (final credit in credits) credit.checkId: credit,
    };

    return [
      for (final profile in profiles)
        AccountMapper.fromRows(
          profile: profile,
          metadata: metadataByProfile[profile.id],
          costShares: sharesByProfile[profile.id] ?? const [],
          currentCheck: currentByProfile[profile.id],
          currentWindows:
              windowsByCheck[currentByProfile[profile.id]?.id] ?? const [],
          lastSuccessfulCheck: successfulByProfile[profile.id],
          lastSuccessfulWindows:
              windowsByCheck[successfulByProfile[profile.id]?.id] ?? const [],
          resetCredits: creditsByCheck[successfulByProfile[profile.id]?.id],
        ),
    ];
  }

  Future<List<UsageCheck>> _latestChecks(
    List<String> profileIds, {
    bool successfulOnly = false,
  }) {
    final placeholders = List.filled(profileIds.length, '?').join(', ');
    final statusClause = successfulOnly ? "AND status = 'success'" : '';
    return database
        .customSelect(
          '''
SELECT *
FROM (
  SELECT usage_checks.*,
         ROW_NUMBER() OVER (
           PARTITION BY profile_id
           ORDER BY started_at DESC
         ) AS account_rank
  FROM usage_checks
  WHERE profile_id IN ($placeholders)
    $statusClause
)
WHERE account_rank = 1
''',
          variables: profileIds.map(Variable<String>.new).toList(),
          readsFrom: {database.usageChecks},
        )
        .map((row) => database.usageChecks.map(row.data))
        .get();
  }

  static Map<String, List<T>> _groupBy<T>(
    Iterable<T> values,
    String Function(T value) keyOf,
  ) {
    final grouped = <String, List<T>>{};
    for (final value in values) {
      grouped.putIfAbsent(keyOf(value), () => []).add(value);
    }
    return grouped;
  }

  static Map<String, List<QuotaWindow>> _deduplicatedWindows(
    Iterable<QuotaWindow> windows,
  ) {
    final grouped = <String, Map<String, QuotaWindow>>{};
    for (final window in windows) {
      final unique = grouped.putIfAbsent(window.checkId, () => {});
      unique.putIfAbsent(
        '${window.limitId.toLowerCase()}\u0000${window.windowType}',
        () => window,
      );
    }
    return {
      for (final entry in grouped.entries)
        entry.key: entry.value.values.toList(),
    };
  }
}
