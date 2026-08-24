import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/heartbeat/data/drift_heartbeat_repository.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat_policy.dart';

void main() {
  group('DriftHeartbeatRepository', () {
    test(
      'loads safely and saves isolated version 2 state per profile',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final repository = DriftHeartbeatRepository(database);
        await database.saveSetting(_key('profile'), '{not-json');
        await database.saveSetting(_key('other'), 'untouched');

        final fallback = await repository.load('profile');
        await repository.save(
          profileId: 'profile',
          state: HeartbeatState(
            status: HeartbeatStatus.failed,
            message: 'offline',
            retryAfter: DateTime.utc(2026, 8, 22, 12, 15),
            retryCount: 1,
          ),
        );

        expect(fallback.status, HeartbeatStatus.unknown);
        final persisted =
            jsonDecode((await database.setting(_key('profile')))!)
                as Map<String, dynamic>;
        expect(persisted['version'], 2);
        expect(persisted['status'], 'failed');
        expect(persisted['retryCount'], 1);
        expect(await database.setting(_key('other')), 'untouched');
      },
    );

    test(
      'loads the preferred profile-scoped history with one select',
      () async {
        final recorder = _QueryRecorder();
        final database = AppDatabase(
          NativeDatabase.memory().interceptWith(recorder),
        );
        addTearDown(database.close);
        final repository = DriftHeartbeatRepository(database);
        final before = DateTime.utc(2026, 8, 22, 12);
        await _insertProfile(database, 'target');
        await _insertProfile(database, 'other');
        await _insertCheck(
          database,
          id: 'target-current',
          profileId: 'target',
          startedAt: before.subtract(const Duration(minutes: 1)),
          completedAt: before.subtract(const Duration(seconds: 30)),
          email: 'target@example.com',
        );
        await database
            .into(database.quotaWindows)
            .insert(
              QuotaWindow(
                id: 'secondary',
                checkId: 'target-current',
                limitId: 'secondary',
                windowType: 'rolling',
                usedPercent: 0,
                windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
                resetsAt: before.add(const Duration(days: 7)),
              ),
            );
        await database
            .into(database.quotaWindows)
            .insert(
              QuotaWindow(
                id: 'codex',
                checkId: 'target-current',
                limitId: 'codex',
                windowType: 'rolling',
                usedPercent: 4,
                windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
                resetsAt: before.add(const Duration(days: 6)),
              ),
            );
        await _insertCheck(
          database,
          id: 'future',
          profileId: 'target',
          startedAt: before.add(const Duration(minutes: 1)),
        );
        await _insertCheck(
          database,
          id: 'other-check',
          profileId: 'other',
          startedAt: before.subtract(const Duration(seconds: 1)),
        );
        recorder.statements.clear();

        final observation = await repository.loadLatestBefore(
          profileId: 'target',
          before: before,
          expectedWindowMinutes: HeartbeatPolicy.weeklyMinutes,
        );

        expect(recorder.statements, hasLength(1));
        expect(observation?.limitId, 'codex');
        expect(observation?.usedPercent, 4);
        expect(observation?.accountEmail, 'target@example.com');
        expect(
          observation?.observedAt.millisecondsSinceEpoch,
          before.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch,
        );
        expect(
          observation?.resetsAt?.millisecondsSinceEpoch,
          before.add(const Duration(days: 6)).millisecondsSinceEpoch,
        );
      },
    );

    test('keeps the legacy twenty-check history bound in one select', () async {
      final recorder = _QueryRecorder();
      final database = AppDatabase(
        NativeDatabase.memory().interceptWith(recorder),
      );
      addTearDown(database.close);
      final repository = DriftHeartbeatRepository(database);
      final before = DateTime.utc(2026, 8, 22, 12);
      await _insertProfile(database, 'bounded');
      for (var index = 0; index < 21; index++) {
        final id = 'check-$index';
        await _insertCheck(
          database,
          id: id,
          profileId: 'bounded',
          startedAt: before.subtract(Duration(minutes: index + 1)),
        );
        if (index == 20) {
          await database
              .into(database.quotaWindows)
              .insert(
                QuotaWindow(
                  id: 'window-$index',
                  checkId: id,
                  limitId: 'codex',
                  windowType: 'rolling',
                  usedPercent: 0,
                  windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
                  resetsAt: before.add(const Duration(days: 7)),
                ),
              );
        }
      }
      recorder.statements.clear();

      final observation = await repository.loadLatestBefore(
        profileId: 'bounded',
        before: before,
        expectedWindowMinutes: HeartbeatPolicy.weeklyMinutes,
      );

      expect(observation, isNull);
      expect(recorder.statements, hasLength(1));
    });
  });
}

final class _QueryRecorder extends QueryInterceptor {
  final List<String> statements = [];

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

Future<void> _insertProfile(AppDatabase database, String id) => database
    .into(database.cliProfiles)
    .insert(
      CliProfile(
        id: id,
        toolKey: 'codex',
        profileName: id,
        displayName: id,
        profileHome: '/tmp/$id',
        profileSource: 'multicli',
        profileType: 'shared',
        hasAuthFile: true,
        isAvailable: true,
        isFavorite: false,
        createdAt: DateTime.utc(2026, 8, 22),
        lastDiscoveredAt: DateTime.utc(2026, 8, 22),
      ),
    );

Future<void> _insertCheck(
  AppDatabase database, {
  required String id,
  required String profileId,
  required DateTime startedAt,
  DateTime? completedAt,
  String? email,
}) => database
    .into(database.usageChecks)
    .insert(
      UsageCheck(
        id: id,
        profileId: profileId,
        queryMethod: 'test',
        status: 'success',
        startedAt: startedAt,
        completedAt: completedAt,
        accountEmail: email,
        planType: 'pro',
      ),
    );

String _key(String profileId) => 'codex_weekly_keep_alive_state_$profileId';
