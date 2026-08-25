import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/usage/data/usage_mapper.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:uuid/uuid.dart';

final class DriftUsageSnapshotRepository implements UsageSnapshotRepository {
  DriftUsageSnapshotRepository(this.database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase database;
  final Uuid _uuid = const Uuid();
  final DateTime Function() _now;

  @override
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  }) async {
    final checkId = _uuid.v4();
    await database.transaction(() async {
      await database
          .into(database.usageChecks)
          .insert(
            UsageChecksCompanion.insert(
              id: checkId,
              profileId: profileId,
              status: UsageMapper.statusToStorage(snapshot.status),
              startedAt: snapshot.startedAt.toUtc(),
              completedAt: Value(snapshot.completedAt.toUtc()),
              durationMs: Value(snapshot.durationMs),
              planType: Value(snapshot.planType),
              accountEmail: Value(snapshot.accountEmail),
              accountDisplayName: Value(snapshot.accountDisplayName),
              errorCode: Value(snapshot.errorCode),
              errorMessage: Value(snapshot.errorMessage),
            ),
          );

      if (snapshot.windows.isNotEmpty) {
        await database.batch((batch) {
          batch.insertAll(
            database.quotaWindows,
            snapshot.windows
                .map(
                  (window) => QuotaWindowsCompanion.insert(
                    id: _uuid.v4(),
                    checkId: checkId,
                    limitId: window.limitId,
                    limitName: Value(window.limitName),
                    windowType: window.windowType,
                    usedPercent: Value(window.usedPercent),
                    windowDurationMinutes: Value(window.windowDurationMinutes),
                    resetsAt: Value(window.resetsAt?.toUtc()),
                    reachedType: Value(window.reachedType),
                    planType: Value(window.planType),
                  ),
                )
                .toList(growable: false),
          );
        });
      }

      await database
          .into(database.resetCreditSnapshots)
          .insert(
            ResetCreditSnapshotsCompanion.insert(
              checkId: checkId,
              availableCount: Value(snapshot.resetCredits),
              nextExpiresAt: Value(snapshot.nextCreditExpiry?.toUtc()),
            ),
          );

      if (snapshot.dailyUsage.isNotEmpty) {
        await database.batch((batch) {
          batch.insertAll(
            database.dailyUsageBuckets,
            snapshot.dailyUsage
                .map(
                  (daily) => DailyUsageBucketsCompanion.insert(
                    id: _uuid.v4(),
                    checkId: checkId,
                    profileId: profileId,
                    day: daily.day.toUtc(),
                    tokens: Value(daily.tokens),
                    activeMinutes: Value(daily.activeMinutes),
                    messageCount: Value(daily.messageCount),
                    source: daily.source,
                  ),
                )
                .toList(growable: false),
          );
        });
      }

      final observedEmail = snapshot.accountEmail?.trim() ?? '';
      final existing = await (database.select(
        database.profileMetadatas,
      )..where((row) => row.profileId.equals(profileId))).getSingleOrNull();
      if (existing == null && observedEmail.isNotEmpty) {
        await database
            .into(database.profileMetadatas)
            .insert(
              ProfileMetadatasCompanion.insert(
                profileId: profileId,
                accountEmail: Value(observedEmail),
                accountDisplayName: Value(snapshot.accountDisplayName ?? ''),
                updatedAt: _now().toUtc(),
              ),
            );
      }
    });
  }
}
