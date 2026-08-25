import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/app_startup.dart';
import 'package:nini_hub/app/nini_hub_app.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/dashboard/presentation/dashboard_shell.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';

void main() {
  testWidgets('database failure gates settings without reading its providers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: NiniHubApp(
          startupFailure: AppStartupFailure(
            kind: AppStartupFailureKind.databaseInUse,
            title: 'Cierra MultiCLI AI',
            message: 'Cierra la aplicación anterior.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('database-startup-failure')),
      findsOneWidget,
    );
    expect(find.text('Cierra MultiCLI AI'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-startup-loading')),
      findsNothing,
    );
    expect(find.byType(DashboardShell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings failure gates dashboard and retry restarts bootstrap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final discovery = _RecordingProfileDiscovery(database);
    var attempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          profileDiscoveryProvider.overrideWithValue(discovery),
          settingsBootstrapProvider.overrideWith((ref) async {
            await Future<void>.delayed(Duration.zero);
            attempts += 1;
            return false;
          }),
        ],
        child: const NiniHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-startup-failure')),
      findsOneWidget,
    );
    expect(find.byType(DashboardShell), findsNothing);
    expect(discovery.calls, 0);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('settings-startup-retry')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(
      find.byKey(const ValueKey('settings-startup-failure')),
      findsOneWidget,
    );
    expect(find.byType(DashboardShell), findsNothing);
    expect(discovery.calls, 0);
    expect(tester.takeException(), isNull);
  });
}

final class _RecordingProfileDiscovery extends ProfileDiscoveryService {
  _RecordingProfileDiscovery(super.database) : super.test();

  int calls = 0;

  @override
  Future<List<CliProfile>> discoverProfiles() async {
    calls += 1;
    return database.select(database.cliProfiles).get();
  }
}
