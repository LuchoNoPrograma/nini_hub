import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/presentation/accounts_quota_clock.dart';
import 'package:nini_hub/features/accounts/presentation/accounts_view.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('shared quota clock publishes a new timestamp each minute', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 25, 12, 30);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountsQuotaNowProvider.overrideWithValue(() => now)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              final value = ref.watch(accountsQuotaClockProvider).asData?.value;
              return Text(value?.toIso8601String() ?? 'waiting');
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2026-08-25T12:30:00.000Z'), findsOneWidget);

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('2026-08-25T12:31:00.000Z'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('quota card advances countdown and distinguishes projections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 8, 25, 12, 30);

    await tester.pumpWidget(_card(_account(floating: true), now));

    expect(find.text('Estimado en 5 h'), findsOneWidget);

    await tester.pumpWidget(
      _card(_account(floating: true), now.add(const Duration(minutes: 1))),
    );

    expect(find.text('Estimado en 4 h 59 min'), findsOneWidget);

    await tester.pumpWidget(_card(_account(floating: false), now));

    expect(find.text('Reinicia en 4 h 30 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _card(Account account, DateTime now) => MaterialApp(
  theme: AppTheme.dark('cyan'),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 500,
        height: 330,
        child: AccountCard(
          account: account,
          quotaNow: now,
          refreshing: false,
          compact: false,
          accountBusy: false,
          profileMutationBusy: false,
          onEditAccount: () async {},
          onHeartbeat: (_) async {},
          onRefresh: (_) async {},
          onDeviceAuth: (_) async {},
          onRenameProfile: (_) async {},
          onDeleteProfile: (_) async {},
          onLaunchAgent: (_) {},
        ),
      ),
    ),
  ),
);

Account _account({required bool floating}) {
  final previousAt = DateTime.utc(2026, 8, 25, 12);
  final currentAt = DateTime.utc(2026, 8, 25, 12, 30);
  final previousReset = DateTime.utc(2026, 8, 25, 17);
  final currentReset = floating
      ? DateTime.utc(2026, 8, 25, 17, 30)
      : previousReset;
  AccountQuotaWindow window(DateTime reset) => AccountQuotaWindow(
    limitId: 'codex',
    windowType: 'primary',
    usedPercent: 0,
    windowDurationMinutes: 300,
    resetsAt: reset,
  );

  return Account(
    profile: const Profile(
      id: 'quota',
      toolKey: 'codex',
      profileName: 'quota',
      commandName: 'codex-quota',
      displayName: 'Quota',
      profileHome: '/profiles/quota',
      source: ProfileSource.multiCli,
      kind: ProfileKind.full,
      hasAuthFile: true,
      isAvailable: true,
      isFavorite: false,
    ),
    metadata: null,
    costShares: const [],
    currentCheck: AccountUsageCheck(
      state: AccountUsageState.success,
      startedAt: currentAt,
      completedAt: currentAt,
      planType: 'plus',
    ),
    currentWindows: [window(currentReset)],
    lastSuccessfulCheck: AccountUsageCheck(
      state: AccountUsageState.success,
      startedAt: currentAt,
      completedAt: currentAt,
      planType: 'plus',
    ),
    lastSuccessfulWindows: [window(currentReset)],
    previousSuccessfulCheck: AccountUsageCheck(
      state: AccountUsageState.success,
      startedAt: previousAt,
      completedAt: previousAt,
      planType: 'plus',
    ),
    previousSuccessfulWindows: [window(previousReset)],
    resetCredits: null,
  );
}
