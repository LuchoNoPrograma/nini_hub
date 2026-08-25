import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/accounts/application/account_device_auth.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/domain/account_repository.dart';
import 'package:nini_hub/features/accounts/presentation/controllers/accounts_controller.dart';
import 'package:nini_hub/features/activity/application/activity_history.dart';
import 'package:nini_hub/features/activity/domain/activity_log.dart';
import 'package:nini_hub/features/activity/domain/activity_repository.dart';
import 'package:nini_hub/features/activity/presentation/controllers/activity_controller.dart';
import 'package:nini_hub/features/dashboard/presentation/dashboard_shell.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/usage/application/usage_calendar.dart';
import 'package:nini_hub/features/usage/application/usage_refresh.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/features/usage/presentation/calendar_view.dart';
import 'package:nini_hub/features/usage/presentation/controllers/usage_controller.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets(
    'dashboard refresh all keeps the legacy visible synchronization order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _PresentationFixture(
        profiles: [_profile('primary')],
        calendar: _calendar(),
      );
      addTearDown(fixture.dispose);
      await fixture.initializeCalendar();
      fixture.events.clear();

      await tester.pumpWidget(fixture.dashboardWidget());
      await tester.pumpAndSettle();
      final knownBrandOverflow = tester.takeException();
      expect(
        knownBrandOverflow,
        isA<FlutterError>().having(
          (error) => error.toString(),
          'message',
          contains('A RenderFlex overflowed by 25 pixels on the right'),
        ),
      );
      expect(find.byKey(const ValueKey('calendar')), findsOneWidget);
      await tester.tap(find.text('Cuentas'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('accounts')), findsOneWidget);
      await tester.tap(find.text('Estadísticas'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar')), findsOneWidget);
      await tester.tap(find.byTooltip('Actualizar todas las cuentas'));
      await tester.pumpAndSettle();

      expect(fixture.events, [
        'discover',
        'provider:primary',
        'persist:primary',
        'activity-write:primary',
        'keep-alive:primary',
        'activity-reload',
        'calendar',
        'accounts-reload',
      ]);
      expect(
        fixture.container.read(usageControllerProvider).isRefreshing,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'failed batch retains the calendar and skips every visible reload',
    () async {
      final failure = StateError('provider unavailable');
      final fixture = _PresentationFixture(
        profiles: [_profile('primary')],
        calendar: _calendar(),
        providerFailure: failure,
      );
      addTearDown(fixture.dispose);
      await fixture.initializeCalendar();
      final original = fixture.container.read(usageControllerProvider).calendar;
      fixture.events.clear();

      await expectLater(
        fixture.container.read(usageRefreshCoordinatorProvider).refreshAll(),
        throwsA(isA<StateError>()),
      );

      final state = fixture.container.read(usageControllerProvider);
      expect(state.calendar, same(original));
      expect(state.isRefreshing, isFalse);
      expect(fixture.events, ['discover', 'provider:primary']);
    },
  );

  testWidgets(
    'calendar preserves selection month navigation and trend ranges at 900x620',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _PresentationFixture(
        profiles: const [],
        calendar: _calendar(),
      );
      addTearDown(fixture.dispose);
      await fixture.initializeCalendar(selectedDay: DateTime(2026, 8, 13));

      await tester.pumpWidget(fixture.calendarWidget());
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      expect(find.text('Estadísticas de uso'), findsOneWidget);
      expect(find.text('Tokens en Agosto 2026'), findsOneWidget);
      expect(find.text('Ari Personal'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.byKey(const ValueKey('calendar-day-2026-8-12')));
      await tester.pumpAndSettle();
      expect(
        fixture.container.read(usageControllerProvider).selectedDay,
        DateTime(2026, 8, 12),
      );
      expect(find.text('Sol Team'), findsOneWidget);
      expect(find.text('Ari Personal'), findsNothing);

      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Septiembre 2026'), findsOneWidget);

      for (final range in [7, 14, 30, 90]) {
        await tester.tap(find.text('$range d'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          {range},
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar stacks into scroll below its wide breakpoint', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _PresentationFixture(
      profiles: const [],
      calendar: _calendar(),
    );
    addTearDown(fixture.dispose);
    await fixture.initializeCalendar(selectedDay: DateTime(2026, 8, 13));

    await tester.pumpWidget(fixture.calendarWidget());
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Ari Personal'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tendencia de tokens'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _PresentationFixture {
  _PresentationFixture({
    required List<Profile> profiles,
    required UsageCalendar calendar,
    Object? providerFailure,
  }) : database = AppDatabase(NativeDatabase.memory()),
       events = <String>[] {
    final discovery = _RecordingDiscovery(profiles, events);
    final refreshProfile = RefreshProfileUsage(
      provider: _RecordingUsageProvider(events, failure: providerFailure),
      repository: _RecordingSnapshotRepository(events),
      activity: _RecordingUsageActivity(events),
      keepAlive: _RecordingKeepAlive(events),
    );
    usageController = UsageController(
      refreshUsage: RefreshUsage(
        discovery: discovery,
        refreshProfile: refreshProfile,
      ),
      refreshAllUsage: RefreshAllUsage(
        discovery: discovery,
        refreshProfile: refreshProfile,
      ),
      loadUsageCalendar: LoadUsageCalendar(
        repository: _RecordingCalendarRepository(calendar, events),
      ),
    );
    final activityRepository = _RecordingActivityRepository(events);
    activityController = ActivityController(
      loadActivityHistory: LoadActivityHistory(repository: activityRepository),
      clearActivityHistory: ClearActivityHistory(
        repository: activityRepository,
      ),
    );
    final accountRepository = _RecordingAccountRepository(events);
    final authActivity = _UnusedDeviceAuthActivity();
    accountsController = AccountsController(
      loadAccounts: LoadAccounts(repository: accountRepository),
      updateAccount: UpdateAccount(
        accountRepository: accountRepository,
        profileRepository: const _UnusedProfileRepository(),
      ),
      startDeviceAuth: StartAccountDeviceAuth(
        gateway: _UnusedDeviceAuthGateway(),
        activity: authActivity,
      ),
      completeDeviceAuth: CompleteAccountDeviceAuth(
        activity: authActivity,
        authenticationStore: const _UnusedAccountAuthenticationStore(),
        discovery: discovery,
        accountRepository: accountRepository,
        monitorHeartbeatProfiles: (_) {},
        refreshUsage: (_) async {},
        synchronizeUsageProjections: () async {},
      ),
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        appStartupProvider.overrideWith((ref) async {}),
        usageControllerProvider.overrideWith(() => usageController),
        activityControllerProvider.overrideWith(() => activityController),
        accountsControllerProvider.overrideWith(() => accountsController),
      ],
    );
  }

  final AppDatabase database;
  final List<String> events;
  late final UsageController usageController;
  late final ActivityController activityController;
  late final AccountsController accountsController;
  late final ProviderContainer container;

  Future<void> initializeCalendar({DateTime? selectedDay}) async {
    final controller = container.read(usageControllerProvider.notifier);
    if (selectedDay != null) controller.selectDay(selectedDay);
    expect(await controller.loadCalendar(), isTrue);
  }

  Widget dashboardWidget() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.dark('cyan'),
      home: const DashboardShell(initialSection: DashboardSection.calendar),
    ),
  );

  Widget calendarWidget() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.dark('cyan'),
      home: const Scaffold(body: UsageCalendarView()),
    ),
  );

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}

final class _RecordingDiscovery implements ProfileDiscovery {
  const _RecordingDiscovery(this.profiles, this.events);

  final List<Profile> profiles;
  final List<String> events;

  @override
  Future<List<Profile>> discover() async {
    events.add('discover');
    return List.of(profiles);
  }
}

final class _RecordingUsageProvider implements UsageProvider {
  const _RecordingUsageProvider(this.events, {this.failure});

  final List<String> events;
  final Object? failure;

  @override
  Future<UsageSnapshot> refresh(Profile profile) async {
    events.add('provider:${profile.id}');
    final error = failure;
    if (error != null) throw error;
    return _snapshot();
  }
}

final class _RecordingSnapshotRepository implements UsageSnapshotRepository {
  const _RecordingSnapshotRepository(this.events);

  final List<String> events;

  @override
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  }) async {
    events.add('persist:$profileId');
  }
}

final class _RecordingUsageActivity implements UsageActivityRecorder {
  const _RecordingUsageActivity(this.events);

  final List<String> events;

  @override
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) async {
    events.add('activity-write:${profile.id}');
  }
}

final class _RecordingKeepAlive implements UsageKeepAliveScheduler {
  const _RecordingKeepAlive(this.events);

  final List<String> events;

  @override
  bool scheduleIfEligible({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) {
    events.add('keep-alive:${profile.id}');
    return true;
  }
}

final class _RecordingCalendarRepository implements UsageCalendarRepository {
  const _RecordingCalendarRepository(this.calendar, this.events);

  final UsageCalendar calendar;
  final List<String> events;

  @override
  Future<UsageCalendar> loadCalendar() async {
    events.add('calendar');
    return calendar;
  }
}

final class _RecordingActivityRepository implements ActivityRepository {
  const _RecordingActivityRepository(this.events);

  final List<String> events;

  @override
  Future<List<ActivityLog>> loadRecent({required int limit}) async {
    events.add('activity-reload');
    return const [];
  }

  @override
  Future<void> clearAll() async {}
}

final class _RecordingAccountRepository implements AccountRepository {
  const _RecordingAccountRepository(this.events);

  final List<String> events;

  @override
  Future<List<Account>> loadAll() async {
    events.add('accounts-reload');
    return const [];
  }

  @override
  Future<Account?> findById(String profileId) async => null;

  @override
  Future<void> saveDetails(AccountDetails details) async {}
}

final class _UnusedProfileRepository implements ProfileRepository {
  const _UnusedProfileRepository();

  @override
  Future<Profile?> findById(String profileId) async => null;

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {}
}

final class _UnusedDeviceAuthGateway implements AccountDeviceAuthGateway {
  @override
  Future<AccountDeviceAuthSession> start(Profile profile) async =>
      _UnusedDeviceAuthSession();
}

final class _UnusedDeviceAuthSession implements AccountDeviceAuthSession {
  @override
  String get userCode => '';

  @override
  String get verificationUrl => '';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> waitForCompletion() async => false;
}

final class _UnusedDeviceAuthActivity
    implements AccountDeviceAuthActivityRecorder {
  @override
  Future<void> recordStarted(Profile profile) async {}

  @override
  Future<void> recordCompleted(
    Profile profile, {
    required bool success,
  }) async {}
}

final class _UnusedAccountAuthenticationStore
    implements AccountAuthenticationStore {
  const _UnusedAccountAuthenticationStore();

  @override
  Future<void> markAuthenticated(String profileId) async {}
}

Profile _profile(String id) => Profile(
  id: id,
  toolKey: 'codex',
  profileName: id,
  commandName: 'codex-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);

UsageSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 22, 12);
  return UsageSnapshot(
    status: UsageRefreshStatus.success,
    startedAt: now,
    completedAt: now,
  );
}

UsageCalendar _calendar() => UsageCalendar([
  UsageCalendarDay(
    day: DateTime(2026, 8, 12),
    tokens: 4500000,
    successfulChecks: 1,
    failedChecks: 0,
    lowestRemaining: 61,
    resetCount: 0,
    renewalCount: 0,
    accounts: const [
      UsageAccountDay(
        profileId: 'sol',
        displayName: 'Sol Team',
        email: 'sol@example.com',
        tokens: 4500000,
        successfulChecks: 1,
        failedChecks: 0,
        lowestRemaining: 61,
        resetCount: 0,
        renewalCount: 0,
      ),
    ],
  ),
  UsageCalendarDay(
    day: DateTime(2026, 8, 13),
    tokens: 322242242,
    successfulChecks: 2,
    failedChecks: 0,
    lowestRemaining: 42,
    resetCount: 1,
    renewalCount: 0,
    accounts: const [
      UsageAccountDay(
        profileId: 'ari',
        displayName: 'Ari Personal',
        email: 'ari@example.com',
        tokens: 322242242,
        successfulChecks: 2,
        failedChecks: 0,
        lowestRemaining: 100,
        resetCount: 1,
        renewalCount: 0,
      ),
    ],
  ),
]);
