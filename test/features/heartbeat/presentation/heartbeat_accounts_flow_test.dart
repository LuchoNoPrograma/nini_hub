import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/accounts/presentation/accounts_view.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat_policy.dart';

void main() {
  testWidgets('manual heartbeat refreshes projections only after success', (
    tester,
  ) async {
    await _runFlow(
      tester,
      result: const HeartbeatRunResult(
        outcome: HeartbeatOutcome.verified,
        message: 'Heartbeat verificado.',
      ),
      expectsRefresh: true,
    );
  });

  testWidgets('manual heartbeat does not refresh projections after failure', (
    tester,
  ) async {
    await _runFlow(
      tester,
      result: const HeartbeatRunResult(
        outcome: HeartbeatOutcome.failed,
        message: 'Codex rechazó el heartbeat.',
      ),
      expectsRefresh: false,
    );
  });
}

Future<void> _runFlow(
  WidgetTester tester, {
  required HeartbeatRunResult result,
  required bool expectsRefresh,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final database = AppDatabase(NativeDatabase.memory());
  final now = DateTime.utc(2026, 8, 23);
  await database
      .into(database.cliProfiles)
      .insert(
        CliProfile(
          id: 'account',
          toolKey: 'codex',
          profileName: 'account',
          commandName: 'codex-account',
          displayName: 'Account',
          profileHome: '/profiles/account',
          profileSource: 'multicli',
          profileType: 'full',
          hasAuthFile: true,
          isAvailable: true,
          isFavorite: false,
          createdAt: now,
          lastDiscoveredAt: now,
        ),
      );
  await database
      .into(database.usageChecks)
      .insert(
        UsageCheck(
          id: 'check',
          profileId: 'account',
          queryMethod: 'test',
          status: 'success',
          startedAt: now,
        ),
      );
  await database.batch((batch) {
    batch.insertAll(database.quotaWindows, [
      QuotaWindow(
        id: 'short',
        checkId: 'check',
        limitId: 'codex',
        windowType: 'primary',
        usedPercent: 1,
        windowDurationMinutes: 300,
      ),
      QuotaWindow(
        id: 'weekly',
        checkId: 'check',
        limitId: 'weekly',
        windowType: 'secondary',
        usedPercent: 1,
        windowDurationMinutes: HeartbeatPolicy.weeklyMinutes,
      ),
    ]);
  });

  final operation = Completer<HeartbeatRunResult>();
  final started = Completer<void>();
  final refreshed = <String>[];
  int? recordedWindowMinutes;
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      heartbeatRunnerProvider.overrideWithValue(({
        required String profileId,
        int? expectedWindowMinutes,
      }) async {
        recordedWindowMinutes = expectedWindowMinutes;
        if (!started.isCompleted) started.complete();
        return operation.future;
      }),
      heartbeatPostRunRefreshProvider.overrideWithValue((profileId) async {
        refreshed.add(profileId);
      }),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await database.close();
  });
  expect(
    await container.read(accountsControllerProvider.notifier).load(),
    isTrue,
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: AccountsView())),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Más acciones'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enviar heartbeat'));
  await tester.pumpAndSettle();
  expect(find.text('Enviar heartbeat a Account'), findsOneWidget);
  await tester.tap(find.text('Enviar'));
  await tester.pump();
  await started.future;

  expect(recordedWindowMinutes, HeartbeatPolicy.weeklyMinutes);
  expect(
    container.read(heartbeatControllerProvider).isRunningProfile('account'),
    isTrue,
  );
  operation.complete(result);
  await tester.pumpAndSettle();

  expect(refreshed, expectsRefresh ? ['account'] : isEmpty);
  expect(
    find.text(result.message),
    expectsRefresh ? findsOneWidget : findsWidgets,
  );
}
