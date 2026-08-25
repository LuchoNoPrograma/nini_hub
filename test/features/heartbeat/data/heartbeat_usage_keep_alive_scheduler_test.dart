import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/heartbeat/data/dart_heartbeat_scheduler.dart';
import 'package:nini_hub/features/heartbeat/data/heartbeat_usage_keep_alive_scheduler.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  test(
    'queues only eligible work and logs detached failures sanitized',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final scheduler = DartHeartbeatScheduler(onScheduledProbe: (_) async {});
      addTearDown(() async {
        scheduler.dispose();
        await database.close();
      });
      final gate = Completer<void>();
      final observed = <String>[];
      final adapter = HeartbeatUsageKeepAliveScheduler(
        scheduler: scheduler,
        runner: ProcessRunner(database),
        observe: ({required profile, required snapshot}) async {
          observed.add(profile.id);
          if (profile.id == 'running') await gate.future;
          if (profile.id == 'failing') {
            throw StateError('access_token=secret-value');
          }
        },
      );

      expect(
        adapter.scheduleIfEligible(
          profile: _profile('running'),
          snapshot: _snapshot(),
        ),
        isTrue,
      );
      expect(
        adapter.scheduleIfEligible(
          profile: _profile('running'),
          snapshot: _snapshot(),
        ),
        isFalse,
      );
      expect(
        adapter.scheduleIfEligible(
          profile: _profile('other', toolKey: 'claude'),
          snapshot: _snapshot(),
        ),
        isFalse,
      );
      await Future<void>.delayed(Duration.zero);
      expect(observed, ['running']);

      gate.complete();
      await scheduler.waitUntilIdle();
      expect(
        adapter.scheduleIfEligible(
          profile: _profile('failing'),
          snapshot: _snapshot(),
        ),
        isTrue,
      );
      await scheduler.waitUntilIdle();

      final log = await database.select(database.commandLogs).getSingle();
      expect(log.profileId, 'failing');
      expect(log.command, 'heartbeat automatic observation');
      expect(log.status, 'error');
      expect(log.output, contains('[REDACTADO]'));
      expect(log.output, isNot(contains('secret-value')));

      scheduler.enabled = false;
      expect(
        adapter.scheduleIfEligible(
          profile: _profile('disabled'),
          snapshot: _snapshot(),
        ),
        isFalse,
      );
    },
  );
}

Profile _profile(String id, {String toolKey = 'codex'}) => Profile(
  id: id,
  toolKey: toolKey,
  profileName: id,
  commandName: '$toolKey-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);

UsageSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 23);
  return UsageSnapshot(
    status: UsageRefreshStatus.success,
    startedAt: now,
    completedAt: now,
  );
}
