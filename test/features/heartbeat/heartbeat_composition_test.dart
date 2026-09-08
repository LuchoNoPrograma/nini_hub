import 'package:nini_hub/features/heartbeat/application/heartbeat.dart';
import 'package:nini_hub/features/profiles/data/drift_profile_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/heartbeat/data/dart_heartbeat_scheduler.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  test('recovers Usage outside a slot without running Codex', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        heartbeatSchedulerProvider.overrideWith((ref) {
          final scheduler = DartHeartbeatScheduler(
            onScheduledProbe: (profileId) =>
                ref.read(heartbeatScheduledProbeProvider)(profileId),
            clock: _Clock(DateTime(2026, 8, 23, 10).toUtc()),
          );
          ref.onDispose(scheduler.dispose);
          return scheduler;
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    final now = DateTime.now().toUtc();
    final profile = Profile(
      id: 'account',
      toolKey: 'codex',
      profileName: 'account',
      commandName: 'codex-account',
      displayName: 'Account',
      profileHome: '/profiles/account',
      source: ProfileSource.multiCli,
      kind: ProfileKind.full,
      hasAuthFile: true,
      isAvailable: true,
      isFavorite: false,
    );
    final snapshot = UsageSnapshot(
      status: UsageRefreshStatus.success,
      startedAt: now,
      completedAt: now,
      windows: [
        UsageQuotaWindow(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 12,
          windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
          resetsAt: now.add(const Duration(days: 6)),
        ),
      ],
    );

    final queued = container
        .read(heartbeatUsageKeepAliveProvider)
        .scheduleIfEligible(profile: profile, snapshot: snapshot);
    expect(queued, isTrue);
    await container.read(heartbeatSchedulerProvider).waitUntilIdle();

    final state = await container
        .read(heartbeatRepositoryProvider)
        .load(profile.id);
    expect(state.status, HeartbeatStatus.active);
    expect(state.observation?.usedPercent, 12);
    expect(await database.select(database.commandLogs).get(), isEmpty);
  });

  test('real publisher persists and projects heartbeat Usage', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final scheduledProbe = _UsageProbe();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        heartbeatProbeProvider.overrideWith(
          (ref) => ProbeHeartbeat(
            profiles: DriftProfileRepository(database),
            probe: scheduledProbe,
            scheduler: ref.read(heartbeatSchedulerProvider),
            observe: ref.read(heartbeatObserveUsageProvider),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    final observedAt = DateTime.utc(2026, 8, 25, 20, 15);
    await database
        .into(database.cliProfiles)
        .insert(
          CliProfile(
            id: 'stable-account-id',
            toolKey: 'codex',
            profileName: 'stable-account-id',
            commandName: 'codex-stable-account-id',
            displayName: 'Stable account',
            profileHome: '/profiles/stable-account-id',
            profileSource: 'multicli',
            profileType: 'full',
            hasAuthFile: true,
            isAvailable: true,
            isFavorite: false,
            createdAt: observedAt,
            lastDiscoveredAt: observedAt,
          ),
        );
    final snapshot = UsageSnapshot(
      status: UsageRefreshStatus.success,
      startedAt: observedAt,
      completedAt: observedAt,
      rateLimitsReadSucceeded: true,
      windows: [
        UsageQuotaWindow(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 0,
          windowDurationMinutes: 5 * Duration.minutesPerHour,
          resetsAt: observedAt.add(const Duration(hours: 5)),
        ),
      ],
    );

    final previous = UsageSnapshot(
      status: UsageRefreshStatus.success,
      startedAt: observedAt.subtract(const Duration(seconds: 5)),
      completedAt: observedAt.subtract(const Duration(seconds: 5)),
      rateLimitsReadSucceeded: true,
      windows: snapshot.windows,
    );
    await container.read(heartbeatUsageSnapshotPublisherProvider)(
      profileId: 'stable-account-id',
      snapshot: snapshot,
      previousSnapshot: previous,
    );
    final account = container.read(accountsControllerProvider).accounts.single;
    expect(
      account.currentWindows.single.resetsAt?.toUtc(),
      observedAt.add(const Duration(hours: 5)),
    );
    expect(account.previousSuccessfulCheck, isNotNull);

    final checks = await database.select(database.usageChecks).get();
    final windows = await database.select(database.quotaWindows).get();
    expect(checks, hasLength(2));
    expect(checks.map((check) => check.profileId).toSet(), {
      'stable-account-id',
    });
    expect(windows, hasLength(2));
    expect(
      windows.last.resetsAt?.toUtc(),
      observedAt.add(const Duration(hours: 5)),
    );
    expect(
      container
          .read(usageControllerProvider)
          .latestSnapshotByProfile['stable-account-id'],
      same(snapshot),
    );
    scheduledProbe.snapshot = UsageSnapshot(
      status: UsageRefreshStatus.success,
      startedAt: observedAt.add(const Duration(minutes: 30)),
      completedAt: observedAt.add(const Duration(minutes: 30)),
      rateLimitsReadSucceeded: true,
      windows: [
        UsageQuotaWindow(
          limitId: 'codex',
          windowType: 'primary',
          usedPercent: 37,
          windowDurationMinutes: 300,
          resetsAt: observedAt.add(const Duration(hours: 5)),
        ),
      ],
    );
    container.read(heartbeatSchedulerProvider).retainProfiles([
      'stable-account-id',
    ]);
    await container.read(heartbeatScheduledProbeProvider)('stable-account-id');
    expect(scheduledProbe.calls, 1);
    expect(
      container
          .read(accountsControllerProvider)
          .accounts
          .single
          .currentWindows
          .single
          .usedPercent,
      37,
    );
    expect(await database.select(database.usageChecks).get(), hasLength(3));
  });
}

final class _Clock implements HeartbeatClock {
  const _Clock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}

final class _UsageProbe implements HeartbeatQuotaProbe {
  late UsageSnapshot snapshot;
  int calls = 0;
  @override
  Future<UsageSnapshot> probe(Profile profile) async {
    calls++;
    return snapshot;
  }
}
