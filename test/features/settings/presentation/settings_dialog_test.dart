import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/settings/application/settings.dart';
import 'package:nini_hub/features/settings/domain/app_preferences.dart';
import 'package:nini_hub/features/settings/domain/settings_ports.dart';
import 'package:nini_hub/features/settings/presentation/controllers/settings_controller.dart';
import 'package:nini_hub/features/settings/presentation/settings_dialog.dart';
import 'package:nini_hub/features/settings/presentation/state/settings_state.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final systemScale in [1.0, 1.3]) {
      testWidgets(
        'preview, cancel and save at 900x600: $brightness / $systemScale',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(900, 600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final store = _SettingsStore();
          final runtime = _SettingsRuntime();
          final provider = NotifierProvider<SettingsController, SettingsState>(
            () => SettingsController(
              loadSettings: LoadSettings(repository: store, runtime: runtime),
              saveSettings: SaveSettings(repository: store, runtime: runtime),
            ),
          );
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await container.read(provider.notifier).load();
          ThemeData buildTheme(double scale) => brightness == Brightness.dark
              ? AppTheme.dark('cyan', fontScale: scale)
              : AppTheme.light('cyan', fontScale: scale);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: Consumer(
                builder: (context, ref, _) {
                  final preferences = ref.watch(provider).preferences;
                  return MaterialApp(
                    theme: buildTheme(preferences.fontScale),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(systemScale)),
                      child: child!,
                    ),
                    home: Builder(
                      builder: (context) => Scaffold(
                        body: Column(
                          children: [
                            const Text(
                              'Texto de la aplicación',
                              key: ValueKey('app-body'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  showSettingsDialog(context, provider),
                              child: const Text('Abrir configuración'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.tap(find.text('Abrir configuración'));
          await tester.pumpAndSettle();
          final slider = find.byKey(const ValueKey('settings-font-scale'));
          final body = find.byKey(const ValueKey('settings-preview-body'));
          final label = find.byKey(const ValueKey('settings-preview-label'));
          await tester.tap(
            find.widgetWithText(DropdownButtonFormField<String>, 'Tema'),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(brightness == Brightness.dark ? 'Oscuro' : 'Claro').last,
          );
          await tester.pumpAndSettle();
          final preview = tester.widget<Container>(
            find.byKey(const ValueKey('settings-typography-preview')),
          );
          expect(
            (preview.decoration! as BoxDecoration).color,
            buildTheme(.9).colorScheme.surface,
          );
          await tester.tap(
            find.widgetWithText(DropdownButtonFormField<String>, 'Tipografía'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Noto Sans').last);
          await tester.pumpAndSettle();
          expect(tester.widget<Text>(body).style!.fontFamily, 'Noto Sans');
          expect(container.read(provider).preferences.fontFamily, 'system');
          double? textSize(Finder finder) =>
              tester.widget<Text>(finder).style?.fontSize;
          final initialAppSize = Theme.of(
            tester.element(find.byKey(const ValueKey('app-body'))),
          ).textTheme.bodyMedium!.fontSize;
          Future<void> chooseSize(double value) async {
            // Exercise the slider with a pointer, including both range ends.
            await tester.ensureVisible(slider);
            final rect = tester.getRect(slider);
            await tester.tapAt(
              Offset(
                value == .8 ? rect.left + 1 : rect.right - 1,
                rect.center.dy,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.widget<Slider>(slider).value, closeTo(value, .00001));
          }

          await chooseSize(.8);
          expect(textSize(body), closeTo(9.6, .00001));
          expect(textSize(label), closeTo(8, .00001));
          final smallHeight = tester.getSize(body).height;
          final richText = find.descendant(
            of: body,
            matching: find.byType(RichText),
          );
          final paragraph = tester.renderObject<RenderParagraph>(richText);
          expect(
            paragraph.textScaler.scale(10),
            closeTo(10 * systemScale, .00001),
          );
          await chooseSize(1.2);
          expect(textSize(body), closeTo(14.4, .00001));
          expect(tester.getSize(body).height, greaterThan(smallHeight));
          expect(store.saveCalls, 0);
          expect(container.read(provider).preferences.fontScale, .9);
          expect(
            Theme.of(
              tester.element(find.byKey(const ValueKey('app-body'))),
            ).textTheme.bodyMedium!.fontSize,
            initialAppSize,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          expect(store.saveCalls, 0);
          await tester.tap(find.text('Abrir configuración'));
          await tester.pumpAndSettle();
          expect(tester.widget<Slider>(slider).value, .9);
          await chooseSize(.8);
          final times = find.byKey(const Key('heartbeat-times'));
          await tester.ensureVisible(times);
          await tester.enterText(times, '25:00');
          await tester.tap(find.text('Guardar'));
          await tester.pumpAndSettle();
          expect(store.saveCalls, 0);
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.ensureVisible(times);
          await tester.enterText(times, '08:30, 19:15');
          await tester.tap(find.text('Guardar'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(store.saveCalls, 1);
          expect(store.preferences.heartbeatSchedule.slots, [510, 1155]);
          expect(store.preferences.fontScale, .8);
          expect(
            Theme.of(
              tester.element(find.byKey(const ValueKey('app-body'))),
            ).textTheme.bodyMedium!.fontSize,
            closeTo(9.6, .00001),
          );
          await tester.tap(find.text('Abrir configuración'));
          await tester.pumpAndSettle();
          expect(tester.widget<Slider>(slider).value, .8);
          expect(textSize(body), closeTo(9.6, .00001));
          final frequency = find.byType(DropdownButtonFormField<bool>);
          await tester.ensureVisible(frequency);
          await tester.tap(frequency);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Repetir por intervalo').last);
          await tester.pumpAndSettle();
          final interval = find.byKey(const Key('heartbeat-interval'));
          await tester.ensureVisible(interval);
          await tester.enterText(interval, '90');
          await tester.tap(find.text('Guardar'));
          await tester.pumpAndSettle();
          expect(store.preferences.heartbeatSchedule.intervalMinutes, 90);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

final class _SettingsStore implements SettingsRepository {
  AppPreferences preferences = AppPreferences.defaults;
  int saveCalls = 0;
  @override
  Future<AppPreferences> load() async => preferences;
  @override
  Future<void> save(AppPreferences value) async {
    saveCalls++;
    preferences = value;
  }
}

final class _SettingsRuntime implements SettingsRuntime {
  @override
  void setHeartbeatSchedule(HeartbeatDailySchedule schedule) {}

  @override
  Future<void> refreshProfiles() async {}
  @override
  void setRequestTimeoutSeconds(int seconds) {}
  @override
  void setWeeklyKeepAliveEnabled(bool enabled) {}
  @override
  void syncWeeklyScheduler() {}
}
