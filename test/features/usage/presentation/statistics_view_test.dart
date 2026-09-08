import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/features/usage/application/usage_calendar.dart';
import 'package:nini_hub/features/usage/application/usage_refresh.dart';
import 'package:nini_hub/features/usage/presentation/calendar_view.dart';
import 'package:nini_hub/features/usage/presentation/controllers/usage_controller.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<ProviderContainer> mount(
    WidgetTester tester,
    UsageCalendar calendar,
    Size size,
  ) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        usageControllerProvider.overrideWith(() => _usageController(calendar)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(usageControllerProvider.notifier);
    controller.selectDay(DateTime(2026, 8, 13));
    await controller.loadCalendar();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark('cyan'),
          home: const Scaffold(body: UsageCalendarView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'check-only records are explained without implying token consumption',
    (tester) async {
      await mount(
        tester,
        UsageCalendar([
          UsageCalendarDay(
            day: DateTime(2026, 8, 13),
            tokens: 0,
            successfulChecks: 3,
            failedChecks: 1,
            lowestRemaining: 42,
            resetCount: 1,
            renewalCount: 1,
            accounts: const [
              UsageAccountDay(
                profileId: 'one',
                displayName: 'Cuenta de prueba',
                email: '',
                tokens: 0,
                successfulChecks: 3,
                failedChecks: 1,
                lowestRemaining: 42,
                resetCount: 1,
                renewalCount: 1,
              ),
            ],
          ),
        ]),
        const Size(900, 600),
      );
      expect(find.text('Días con registros'), findsOneWidget);
      expect(find.text('Comprobaciones de uso'), findsOneWidget);
      expect(find.text('Días con uso'), findsNothing);
      expect(
        find.text('No hay tokens registrados en este período'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Detalle por día'));
      await tester.pumpAndSettle();
      expect(find.text('Reinicio previsto'), findsOneWidget);
      expect(find.text('Renovación'), findsOneWidget);
      expect(find.text('Comprobación fallida'), findsOneWidget);
      expect(find.text('1 cuenta con registros'), findsOneWidget);
      expect(find.text('Mínimo disponible del día'), findsOneWidget);
      expect(find.text('42% disponible'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'month navigation keeps detail and trend dates together and today restores them',
    (tester) async {
      final container = await mount(
        tester,
        UsageCalendar(const []),
        const Size(900, 600),
      );
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(
        container.read(usageControllerProvider).selectedDay,
        DateTime(2026, 9, 1),
      );
      expect(find.text('Tokens en Septiembre 2026'), findsOneWidget);
      for (final range in [7, 14, 30, 90]) {
        await tester.ensureVisible(find.text('$range d'));
        await tester.tap(find.text('$range d'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          {range},
        );
      }
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Hoy'));
      await tester.tap(find.widgetWithText(TextButton, 'Hoy'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      expect(
        container.read(usageControllerProvider).selectedDay,
        DateTime(now.year, now.month, now.day),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty statistics remain readable when resized and scrolled', (
    tester,
  ) async {
    await mount(tester, UsageCalendar(const []), const Size(900, 600));
    for (final size in [
      const Size(900, 600),
      const Size(700, 600),
      const Size(1200, 760),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('No hay datos para este día'));
      await tester.pumpAndSettle();
      expect(find.text('Sin actividad registrada'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Resumen del mes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

UsageController _usageController(UsageCalendar calendar) {
  const discovery = _EmptyProfileDiscovery();
  const provider = _UnusedUsageProvider();
  const repository = _UnusedUsageSnapshotRepository();
  const activity = _UnusedUsageActivityRecorder();
  final refreshProfile = RefreshProfileUsage(
    provider: provider,
    repository: repository,
    activity: activity,
  );
  return UsageController(
    refreshUsage: RefreshUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    ),
    refreshAllUsage: RefreshAllUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    ),
    loadUsageCalendar: LoadUsageCalendar(
      repository: _StaticUsageCalendarRepository(calendar),
    ),
  );
}

final class _EmptyProfileDiscovery implements ProfileDiscovery {
  const _EmptyProfileDiscovery();

  @override
  Future<List<Profile>> discover() async => const [];
}

final class _UnusedUsageProvider implements UsageProvider {
  const _UnusedUsageProvider();

  @override
  Future<UsageSnapshot> refresh(Profile profile) =>
      throw UnsupportedError('Refresh is outside this calendar test.');
}

final class _UnusedUsageSnapshotRepository implements UsageSnapshotRepository {
  const _UnusedUsageSnapshotRepository();

  @override
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  }) => throw UnsupportedError('Refresh is outside this calendar test.');
}

final class _UnusedUsageActivityRecorder implements UsageActivityRecorder {
  const _UnusedUsageActivityRecorder();

  @override
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) => throw UnsupportedError('Refresh is outside this calendar test.');
}

final class _StaticUsageCalendarRepository implements UsageCalendarRepository {
  const _StaticUsageCalendarRepository(this.calendar);

  final UsageCalendar calendar;

  @override
  Future<UsageCalendar> loadCalendar() async => calendar;
}
