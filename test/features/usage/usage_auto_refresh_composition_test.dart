import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/heartbeat/data/heartbeat_usage_keep_alive_scheduler.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/usage/data/drift_usage_snapshot_repository.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';
import 'package:nini_hub/providers/codex/codex_client_runtime.dart';

void main() {
  for (final scenario in ['normal', 'remove', 'relink', 'heartbeat']) {
    final withHeartbeat = scenario == 'heartbeat';
    final removeDuringRead = scenario == 'remove';
    final relinkDuringRead = scenario == 'relink';
    test('automatic provider flow: $scenario', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final client = _Client();
      final discovery = _Discovery(db);
      final observed = Completer<UsageSnapshot>();
      var observations = 0;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          if (withHeartbeat)
            heartbeatUsageKeepAliveProvider.overrideWith(
              (ref) => HeartbeatUsageKeepAliveScheduler(
                scheduler: ref.watch(heartbeatSchedulerProvider),
                operationGate: ref.watch(usageOperationGateProvider),
                runner: ref.watch(processRunnerProvider),
                observe: ({required profile, required snapshot}) async {
                  observations++;
                  expect(profile.id, 'a');
                  expect(await db.select(db.usageChecks).get(), hasLength(2));
                  observed.complete(snapshot);
                  return const HeartbeatRunResult(
                    outcome: HeartbeatOutcome.skipped,
                    message: 'Synthetic observation',
                  );
                },
                publish:
                    ({
                      required profileId,
                      required snapshot,
                      previousSnapshot,
                    }) async {},
              ),
            ),
          profileDiscoveryProvider.overrideWithValue(discovery),
          codexClientRuntimeProvider.overrideWithValue(
            CodexClientRuntime(initialClient: client),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final old = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      await db
          .into(db.cliProfiles)
          .insert(
            CliProfilesCompanion.insert(
              id: 'a',
              toolKey: const Value('codex'),
              profileName: 'a',
              displayName: 'A',
              profileHome: '/synthetic/a',
              profileSource: 'multicli',
              profileType: 'full',
              hasAuthFile: const Value(true),
              isAvailable: const Value(true),
              createdAt: old,
              lastDiscoveredAt: old,
            ),
          );
      await DriftUsageSnapshotRepository(db).saveSnapshot(
        profileId: 'a',
        snapshot: UsageSnapshot(
          status: UsageRefreshStatus.success,
          startedAt: old,
          completedAt: old,
          windows: [
            UsageQuotaWindow(
              limitId: 'codex',
              windowType: 'primary',
              usedPercent: 100,
              reachedType: 'rate_limit_reached',
              windowDurationMinutes: 300,
              resetsAt: old.add(const Duration(hours: 1)),
            ),
            // Codex reports the reached flag on the group, including a
            // weekly window that still has quota. It must not postpone startup.
            UsageQuotaWindow(
              limitId: 'codex',
              windowType: 'secondary',
              usedPercent: 32,
              reachedType: 'rate_limit_reached',
              windowDurationMinutes: 10080,
              resetsAt: old.add(const Duration(days: 5)),
            ),
          ],
        ),
      );
      container.read(heartbeatSchedulerProvider).enabled = withHeartbeat;
      final updated = Completer<void>();
      container.listen(accountsControllerProvider, (_, state) {
        if (!updated.isCompleted &&
            state.accounts.any(
              (account) => account.currentCheck!.startedAt.isAfter(old),
            )) {
          updated.complete();
        }
      });
      late final Future<void> pending;
      if (removeDuringRead || relinkDuringRead || withHeartbeat) {
        await container.read(accountsControllerProvider.notifier).load();
        pending = container.read(usageAutoRefreshProvider).refreshDue();
      } else {
        // No Accounts widget: startup must activate the whole-session service.
        await container.read(appStartupProvider.future);
        pending = updated.future;
      }
      final automatic = container.read(usageAutoRefreshProvider);
      await client.started.future.timeout(const Duration(seconds: 5));
      if (removeDuringRead) {
        await (db.delete(
          db.cliProfiles,
        )..where((row) => row.id.equals('a'))).go();
      }
      if (relinkDuringRead) automatic.invalidatePendingReads();
      client.release.complete();
      await pending.timeout(const Duration(seconds: 5));
      expect(client.calls, 1);
      if (withHeartbeat) {
        final snapshot = await observed.future.timeout(
          const Duration(seconds: 5),
        );
        expect(snapshot, same(automatic.recentSnapshot('a')));
        expect(observations, 1);
      }
      expect(
        discovery.calls,
        removeDuringRead || relinkDuringRead || withHeartbeat ? 0 : 1,
      );
      final checks = await db.select(db.usageChecks).get();
      expect(
        checks,
        hasLength(
          removeDuringRead
              ? 0
              : relinkDuringRead
              ? 1
              : 2,
        ),
      );
      expect(container.read(heartbeatControllerProvider).isBusy, isFalse);
      expect(
        container.read(heartbeatSchedulerProvider).nextProbeAt('a'),
        isNull,
      );
      if (!removeDuringRead && !relinkDuringRead) {
        expect(
          container.read(usageControllerProvider).latestSnapshotByProfile['a'],
          isNotNull,
        );
        final account = container
            .read(accountsControllerProvider)
            .accounts
            .single;
        expect(
          account.currentWindows.single.resetsAt!.isAfter(
            DateTime.now().toUtc(),
          ),
          isTrue,
        );
        await automatic.refreshDue();
        expect(client.calls, 1);
        if (withHeartbeat) expect(observations, 1);
        // A heartbeat that reuses the same reading must not persist it twice.
        final snapshot = automatic.recentSnapshot('a')!;
        await container.read(heartbeatUsageSnapshotPublisherProvider)(
          profileId: 'a',
          snapshot: snapshot,
        );
        expect(await db.select(db.usageChecks).get(), hasLength(2));
      }
    });
  }
}

final class _Discovery extends ProfileDiscoveryService {
  _Discovery(super.database) : super.test();
  int calls = 0;
  @override
  Future<List<CliProfile>> discoverProfiles() {
    calls++;
    return database.select(database.cliProfiles).get();
  }
}

final class _Client extends CodexAppServerClient {
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<CodexRefreshResult> refresh(Profile profile) async {
    calls++;
    final now = DateTime.now().toUtc();
    started.complete();
    await release.future;
    return CodexRefreshResult(
      state: UsageCheckState.success,
      startedAt: now,
      completedAt: DateTime.now().toUtc(),
      rateLimitsReadSucceeded: true,
      windows: [
        QuotaSnapshot(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 0,
          windowDurationMinutes: 300,
          resetsAt: now.add(const Duration(hours: 5)),
        ),
      ],
    );
  }
}
