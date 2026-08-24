import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';

void main() {
  test('real composition observes Usage without running Codex', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
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
}
