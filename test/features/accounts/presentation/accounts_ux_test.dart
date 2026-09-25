import 'dart:async';
import 'package:nini_hub/features/accounts/application/create_linked_account.dart';
import 'package:nini_hub/features/profiles/domain/profile_draft.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:nini_hub/features/accounts/presentation/accounts_view.dart';
import 'package:nini_hub/features/accounts/presentation/accounts_quota_clock.dart';
import 'package:nini_hub/features/accounts/presentation/account_dialogs.dart';
import 'package:nini_hub/features/accounts/presentation/controllers/accounts_controller.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/presentation/profile_dialogs.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

final _now = DateTime.utc(2026, 9, 5, 12);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
    // Optional review artifacts use a caller-supplied font and output directory.
    final font = Platform.environment['NINI_UI_REVIEW_FONT'];
    if (font != null) {
      final loader = FontLoader('Review');
      loader.addFont(
        File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  for (final kind in [ProfileKind.full, ProfileKind.deactivated]) {
    for (final principal in [false, true]) {
      for (final busy in [false, true]) {
        testWidgets('delete menu: $kind / principal=$principal / busy=$busy', (
          tester,
        ) async {
          final account = _account(kind: kind, principal: principal);
          Account? deleted;
          await tester.pumpWidget(
            _card(
              account,
              profileMutationBusy: busy,
              onDeleteProfile: (value) async {
                deleted = value;
              },
            ),
          );
          await tester.tap(find.byTooltip('Más acciones'));
          await tester.pumpAndSettle();
          final item = find.widgetWithText(
            PopupMenuItem<String>,
            'Eliminar perfil',
          );
          final enabled = !principal && !busy;
          expect(tester.widget<PopupMenuItem<String>>(item).enabled, enabled);
          await tester.tap(find.text('Eliminar perfil'));
          await tester.pumpAndSettle();
          expect(deleted, enabled ? same(account) : isNull);
        });
      }
    }
  }

  for (final method in AccountAuthMethod.values) {
    for (final outcome in ['success', 'cancel', 'failure', 'unmount']) {
      testWidgets(
        'linked creation: $method / $outcome publishes only on success',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(900, 600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final fixture = _Fixture([], creation: true);
          if (outcome == 'success') fixture.quotaGate = Completer<void>();
          addTearDown(fixture.close);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: MaterialApp(
                theme: _theme(),
                home: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () => showCreateProfileFlow(context, ref),
                      child: const Text('Abrir alta'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Abrir alta'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextFormField).first, 'team');
          await tester.tap(find.text('Crear y vincular'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(fixture.creationPorts!.events, isEmpty);
          await tester.tap(
            find.text(
              method == AccountAuthMethod.browser
                  ? 'Continuar en el navegador'
                  : 'Usar código de dispositivo',
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(fixture.store.accounts, isEmpty);
          expect(
            fixture.container.read(accountsControllerProvider).accounts,
            isEmpty,
          );
          expect(
            fixture.container.read(accountsControllerProvider).isBusy,
            isTrue,
          );
          expect(
            await fixture.container
                .read(accountsControllerProvider.notifier)
                .load(),
            isFalse,
          );
          expect(fixture.creationPorts!.methods, [method]);
          if (outcome == 'unmount') {
            await tester.pumpWidget(const SizedBox.shrink());
          } else if (outcome == 'cancel') {
            await tester.ensureVisible(find.text('Cancelar').last);
            await tester.tap(find.text('Cancelar').last);
          } else {
            fixture.creationPorts!.completion.complete(outcome == 'success');
          }
          await tester.pumpAndSettle();
          expect(fixture.store.accounts.length, outcome == 'success' ? 1 : 0);
          expect(
            fixture.container.read(accountsControllerProvider).accounts.length,
            outcome == 'success' ? 1 : 0,
          );
          expect(
            fixture.creationPorts!.events,
            outcome == 'success'
                ? ['prepare', 'start', 'close', 'publish']
                : ['prepare', 'start', 'cancel', 'close', 'discard'],
          );
          expect(
            find.text('Nuevo perfil'),
            outcome == 'success' || outcome == 'unmount'
                ? findsNothing
                : findsOneWidget,
          );
          expect(
            fixture.container.read(accountsControllerProvider).isBusy,
            isFalse,
          );
          if (outcome == 'success') {
            final pending = fixture.container.read(accountsControllerProvider);
            expect(pending.authRefreshingProfileIds, isNotEmpty);
            expect(find.byType(AlertDialog), findsNothing);
            await tester.pump(const Duration(seconds: 31));
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              fixture.container.read(accountsControllerProvider).isBusy,
              isFalse,
            );
            fixture.quotaGate!.complete();
            await tester.pumpAndSettle();
            expect(
              fixture.container
                  .read(accountsControllerProvider)
                  .authRefreshingProfileIds,
              isEmpty,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'relink closes immediately and exposes slow quotas with a local retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = _account(id: 'Cuenta');
      final fixture = _Fixture([account, _account(id: 'Otra')], creation: true);
      addTearDown(fixture.close);
      fixture.quotaGate = Completer<void>();
      final controller = fixture.container.read(
        accountsControllerProvider.notifier,
      );
      await controller.load();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            theme: _theme(),
            home: Scaffold(
              body: const AccountsView(),
              floatingActionButton: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDeviceAuthDialog(
                    context,
                    account,
                    method: AccountAuthMethod.browser,
                    start: (_) async => fixture.creationPorts!,
                    startBrowser: (_) async => fixture.creationPorts!,
                    complete: (account, success) async {
                      await controller.completeDeviceAuth(account, success);
                    },
                  ),
                  child: const Text('Probar vínculo'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Probar vínculo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      fixture.creationPorts!.completion.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Acceso confirmado. Actualizando cuotas en segundo plano…'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 31));
      expect(
        fixture.container.read(accountsControllerProvider).isBusy,
        isFalse,
      );
      final cards = tester.widgetList<AccountCard>(find.byType(AccountCard));
      expect(
        cards
            .firstWhere((card) => card.account.profile.id == 'Cuenta')
            .profileMutationBusy,
        isTrue,
      );
      expect(
        cards
            .firstWhere((card) => card.account.profile.id == 'Otra')
            .accountBusy,
        isFalse,
      );
      fixture.quotaFailure = StateError('provider unavailable');
      fixture.quotaGate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('El acceso está confirmado, pero'),
        findsOneWidget,
      );
      expect(find.text('Reintentar cuotas'), findsOneWidget);
      fixture.quotaFailure = null;
      await tester.tap(find.text('Reintentar cuotas'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar cuotas'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('status chips filter cards with matching counts and colors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture([
      _account(id: 'available'),
      _account(id: 'exhausted', weeklyUsed: 100),
      _account(id: 'access', state: AccountUsageState.authRequired),
      _account(id: 'disabled', kind: ProfileKind.deactivated),
      _account(id: 'unlinked', hasAuthFile: false),
      _account(id: 'unchecked', unchecked: true),
      _account(id: 'uncertain', unknownQuota: true),
      _account(id: 'offline', failed: true),
      _account(id: 'error', failed: true, networkFailure: false),
      _account(id: 'missing', state: AccountUsageState.toolMissing),
    ]);
    addTearDown(fixture.close);
    await fixture.container.read(accountsControllerProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(
          theme: _theme(),
          home: const Scaffold(body: AccountsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Listos'), findsNothing);
    expect(find.text('Atención'), findsNothing);
    for (final entry in {
      'Disponibles': ('available', 'Disponible'),
      'Cuota agotada': ('exhausted', 'Cuota agotada'),
      'Requieren acceso': ('access', 'Requiere acceso'),
      'Desactivadas': ('disabled', 'Desactivada'),
      'Sin vincular': ('unlinked', 'Sin vincular'),
      'Sin consultar': ('unchecked', 'Sin consultar'),
      'Cuota sin confirmar': ('uncertain', 'Cuota sin confirmar'),
      'Sin conexión': ('offline', 'Sin conexión'),
      'Error de consulta': ('error', 'Error de consulta'),
      'No disponibles': ('missing', 'No disponible'),
    }.entries) {
      final chip = find.widgetWithText(ChoiceChip, entry.key);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(AccountCard), findsOneWidget);
      expect(
        tester.widget<AccountCard>(find.byType(AccountCard)).account.profile.id,
        entry.value.$1,
      );
      final badge = find.descendant(
        of: find.byType(AccountCard),
        matching: find.text(entry.value.$2),
      );
      expect(badge, findsOneWidget);
      final color = tester.widget<Text>(badge).style!.color;
      final chipText = find.descendant(
        of: chip,
        matching: find.text(entry.key),
      );
      expect(tester.widget<Text>(chipText).style!.color, color);
      if (entry.value.$1 == 'access') {
        expect(color, _theme().colorScheme.tertiary);
      }
      if (entry.value.$1 == 'exhausted') {
        expect(color, _theme().colorScheme.error);
      }
      final summaryLabel = entry.value.$1 == 'error'
          ? 'error de consulta'
          : entry.value.$2.toLowerCase();
      expect(find.text('1 $summaryLabel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('account status uses sentence case for errors and success', (
    tester,
  ) async {
    for (final entry in {
      _account(): 'Disponible',
      _account(failed: true): 'Sin conexión',
      _account(hasAuthFile: false, failed: true): 'Sin vincular',
      _account(partial: true): 'Disponible',
    }.entries) {
      await tester.pumpWidget(_card(entry.key));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text(entry.value.toUpperCase()), findsNothing);
    }
  });

  testWidgets(
    'weekly exhaustion blocks only its matching quota, even compact',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(460, 450));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = _account(weeklyUsed: 100, extraLimit: true);
      for (final compact in [false, true]) {
        await tester.pumpWidget(_card(account, compact: compact));
        await tester.pumpAndSettle();
        expect(find.text('Bloqueada por límite semanal'), findsOneWidget);
        expect(find.text('Cuota agotada'), findsOneWidget);

        expect(_progress(tester, 'codex', 'primary'), 1);
        expect(_progress(tester, 'codex', 'secondary'), 0);
        expect(find.text('100% restante'), findsOneWidget);
        expect(account.isReady, isFalse);
        expect(_progress(tester, 'independent', 'primary'), 1);
        expect(find.text('2 resets disponibles'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('five-hour exhaustion preserves weekly quota, even compact', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(460, 450));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = _account(shortUsed: 100, extraLimit: true);
    for (final compact in [false, true]) {
      await tester.pumpWidget(_card(account, compact: compact));
      await tester.pumpAndSettle();
      expect(find.text('Bloqueada por límite de 5 horas'), findsOneWidget);
      expect(find.text('80% restante'), findsOneWidget);
      expect(find.text('80% disponible'), findsNothing);
      expect(find.text('Cuota agotada'), findsOneWidget);
      expect(account.isReady, isFalse);
      expect(_progress(tester, 'codex', 'primary'), 0);
      expect(_progress(tester, 'codex', 'secondary'), 0.8);
      expect(_progress(tester, 'independent', 'primary'), 1);
      expect(
        find.byKey(const ValueKey('quota-reset-codex-secondary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('profile configuration label follows the reported kind', (
    tester,
  ) async {
    for (final entry in {
      ProfileKind.shared: 'Configuración compartida',
      ProfileKind.full: 'Configuración propia',
      ProfileKind.isolated: 'Configuración propia',
      ProfileKind.cli: 'Perfil de herramienta',
    }.entries) {
      final account = _account(kind: entry.key);
      await tester.pumpWidget(_card(account));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(accountProfileConfigurationLabel(account.profile), entry.value);
      expect(find.text('Cuenta independiente'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('unknown, zero, expired and historical resets remain distinct', (
    tester,
  ) async {
    final cases = <Account, String>{
      _account(credits: null): 'Resets: sin información',
      _account(credits: 0): 'Sin resets',
      _account(credits: 1): '1 reset disponible',
      _account(credits: 3, expiredCredits: true): 'Último registro: 3 resets',
      _account(credits: 2, failed: true): 'Último registro: 2 resets',
      _account(credits: 2, partial: true): 'Último registro: 2 resets',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(_card(entry.key));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('reset-credits-account'))),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          entry.key.resetCredits == null
              ? 'Vencimiento no informado'
              : 'Próximo vencimiento:',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Los resets son distintos', findRichText: true),
        findsNothing,
      );
      await mouse.removePointer();
      await tester.pumpAndSettle();
      if (entry.key.currentCheck?.state == AccountUsageState.error) {
        expect(find.text('100% disponible'), findsNothing);
        expect(find.text('100% registrado'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  for (final size in [const Size(1280, 800), const Size(900, 600)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('accounts layout, filters and keyboard at $size x $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = _Fixture([
          _account(id: 'main', principal: true),
          _account(id: 'Trabajo', weeklyUsed: 100, kind: ProfileKind.shared),
          _account(id: 'Personal', credits: 0),
          _account(id: 'Investigación', failed: true),
          _account(id: 'Equipo', credits: null, kind: ProfileKind.shared),
          _account(id: 'Reserva', weeklyUsed: 60),
          _account(id: 'Desarrollo', kind: ProfileKind.shared),
          _account(id: 'Consultas', credits: 1),
          _account(id: 'Respaldo', kind: ProfileKind.shared),
        ]);
        addTearDown(fixture.close);
        await fixture.container
            .read(accountsControllerProvider.notifier)
            .load();
        final capture = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              theme: _theme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: capture,
                child: const Scaffold(body: AccountsView()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (size.width == 1280 && scale == 1) {
          final firstCard = tester
              .getTopLeft(find.byType(AccountCard).first)
              .dy;
          expect(
            firstCard,
            lessThan(210),
            reason: 'Header must leave space for cards',
          );
          await _capture(tester, capture, 'accounts-desktop');
          expect(find.byType(AccountCard), findsNWidgets(9));
          // The expanded status filters add a row; the last cards remain
          // accessible through the page scroll.
          await tester.ensureVisible(find.byType(AccountCard).last);
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(find.byType(AccountCard).last)
                .overlaps(const Rect.fromLTWH(0, 0, 1280, 800)),
            isTrue,
          );
          for (final card in find.byType(AccountCard).evaluate()) {
            expect(
              tester.getSize(find.byWidget(card.widget)).height,
              lessThanOrEqualTo(235),
            );
            for (final scroll
                in find
                    .descendant(
                      of: find.byWidget(card.widget),
                      matching: find.byType(Scrollable),
                    )
                    .evaluate()) {
              final position =
                  (scroll as StatefulElement).state as ScrollableState;
              expect(
                position.position.maxScrollExtent,
                0,
                reason:
                    'Essential data must fit: ${(card.widget as AccountCard).account.profile.id}',
              );
            }
          }
        }
        if (size.width == 900 && scale == 1) {
          await _capture(tester, capture, 'accounts-900');
        }
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'Disponibles'),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Disponibles'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<AccountCard>(find.byType(AccountCard))
              .every((card) => card.account.status == AccountStatus.available),
          isTrue,
        );
        final search = find.byType(TextFormField).first;
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.tap(search);
        await tester.enterText(search, 'principal');
        await tester.pumpAndSettle();
        expect(find.byType(AccountCard), findsOneWidget);
        expect(find.text('Perfil principal'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }

  for (final brightness in Brightness.values) {
    for (final compact in [false, true]) {
      testWidgets(
        'cards follow text size at 900x600: $brightness / compact=$compact',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(900, 600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final systemScale in [1.0, 1.3]) {
            double previousHeight = 0;
            for (final fontScale in [.8, .9, 1.2]) {
              final fixture = _Fixture(
                [_account(principal: true, extraLimit: true, weeklyUsed: 100)],
                fontScale: fontScale,
                compact: compact,
              );
              addTearDown(fixture.close);
              await fixture.container
                  .read(accountsControllerProvider.notifier)
                  .load();
              final theme = _theme(
                fontScale: fontScale,
                brightness: brightness,
              );
              final capture = GlobalKey();
              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: fixture.container,
                  child: MaterialApp(
                    theme: theme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(systemScale)),
                      child: child!,
                    ),
                    home: RepaintBoundary(
                      key: capture,
                      child: const Scaffold(body: AccountsView()),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final card = find.byType(AccountCard);
              final height = tester.getSize(card).height;
              expect(height, greaterThan(previousHeight));
              previousHeight = height;
              final title = find.text('Perfil principal');
              expect(
                tester.widget<Text>(title).style!.fontSize,
                theme.textTheme.titleLarge!.fontSize,
              );
              expect(find.text('Bloqueada por límite semanal'), findsOneWidget);
              expect(
                find.descendant(of: card, matching: find.text('Cuota agotada')),
                findsOneWidget,
              );
              expect(find.text('2 resets disponibles'), findsOneWidget);
              for (final scroll
                  in find
                      .descendant(of: card, matching: find.byType(Scrollable))
                      .evaluate()) {
                final state =
                    (scroll as StatefulElement).state as ScrollableState;
                expect(
                  state.position.maxScrollExtent,
                  0,
                  reason: 'Quotas must fit at $fontScale / system $systemScale',
                );
              }
              expect(tester.takeException(), isNull);
              if (!compact && systemScale == 1 && fontScale != .9) {
                await _capture(
                  tester,
                  capture,
                  'accounts-${brightness.name}-${(fontScale * 100).round()}',
                );
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await fixture.close();
            }
          }
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    for (final fontScale in [.8, 1.2]) {
      testWidgets(
        'account form adapts and preserves edits: $brightness / $fontScale',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(900, 600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final fixture = _Fixture([_account(principal: true)]);
          addTearDown(fixture.close);
          await fixture.container
              .read(accountsControllerProvider.notifier)
              .load();
          final capture = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: _theme(fontScale: fontScale, brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.3)),
                child: RepaintBoundary(key: capture, child: child!),
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showEditAccountDialog(
                      context,
                      fixture.container.read(
                        accountsControllerProvider.notifier,
                      ),
                      () => fixture.container.read(accountsControllerProvider),
                      fixture.store.accounts.first,
                    ),
                    child: const Text('Editar'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Editar'));
          await tester.pumpAndSettle();
          final name = find.widgetWithText(
            TextFormField,
            'Nombre en Nini Hub *',
          );
          final owner = find.widgetWithText(
            TextFormField,
            'Propietario (opcional)',
          );
          if (fontScale == .8) {
            expect(
              tester.getTopLeft(name).dy,
              closeTo(tester.getTopLeft(owner).dy, .1),
            );
          } else {
            expect(
              tester.getTopLeft(owner).dy,
              greaterThan(tester.getBottomRight(name).dy),
            );
          }
          await tester.ensureVisible(name);
          await tester.enterText(name, '');
          await tester.tap(find.text('Guardar cambios'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(
                  find.descendant(of: name, matching: find.byType(TextField)),
                )
                .focusNode!
                .hasFocus,
            isTrue,
          );
          expect(fixture.store.saves, 0);
          await tester.enterText(name, 'Mi cuenta de trabajo');
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(
                  find.descendant(of: owner, matching: find.byType(TextField)),
                )
                .focusNode!
                .hasFocus,
            isTrue,
          );
          await tester.ensureVisible(owner);
          await tester.enterText(owner, 'Ana');
          await tester.tap(find.text('Suscripción'));
          await tester.pumpAndSettle();
          final amount = find.widgetWithText(
            TextFormField,
            'Precio por renovación',
          );
          await tester.enterText(amount, '20.50');
          await _capture(
            tester,
            capture,
            'edit-subscription-${brightness.name}-${(fontScale * 100).round()}',
          );
          await tester.tap(find.text('Pagos compartidos'));
          await tester.pumpAndSettle();
          expect(
            find.text('¿Compartes el costo de esta cuenta?'),
            findsOneWidget,
          );
          await _capture(
            tester,
            capture,
            'edit-shares-empty-${brightness.name}-${(fontScale * 100).round()}',
          );
          await tester.tap(find.text('Agregar persona'));
          await tester.pumpAndSettle();
          final person = find.widgetWithText(TextFormField, 'Persona');
          expect(
            tester
                .widget<TextField>(
                  find.descendant(of: person, matching: find.byType(TextField)),
                )
                .focusNode!
                .hasFocus,
            isTrue,
          );
          await tester.enterText(person, 'Ana');
          final expected = find.widgetWithText(
            TextFormField,
            'Aporte acordado',
          );
          final paid = find.widgetWithText(TextFormField, 'Importe pagado');
          await tester.ensureVisible(expected);
          await tester.enterText(expected, '10.25');
          await tester.ensureVisible(paid);
          await tester.enterText(paid, '5');
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: expected,
                    matching: find.byType(TextField),
                  ),
                )
                .decoration!
                .suffixText,
            'USD',
          );
          await _capture(
            tester,
            capture,
            'edit-shares-${brightness.name}-${(fontScale * 100).round()}',
          );
          await tester.tap(find.text('Cuenta'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(name).controller!.text,
            'Mi cuenta de trabajo',
          );
          expect(tester.widget<TextFormField>(owner).controller!.text, 'Ana');
          await tester.binding.setSurfaceSize(const Size(1280, 800));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(name).controller!.text,
            'Mi cuenta de trabajo',
          );
          await tester.binding.setSurfaceSize(const Size(900, 600));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            capture,
            'edit-account-${brightness.name}-${(fontScale * 100).round()}',
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Guardar cambios'));
          await tester.pumpAndSettle();
          expect(find.text('Datos de la cuenta'), findsNothing);
          expect(fixture.store.saves, 1);
          expect(fixture.store.details!.metadata.accountDisplayName, 'Ana');
          expect(fixture.store.details!.metadata.expectedAmountMinor, 2050);
          expect(
            fixture.store.details!.costShares.single.expectedAmountMinor,
            1025,
          );
          expect(fixture.store.details!.costShares.single.paidAmountMinor, 500);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('account form reveals invalid hidden values and saves once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture([_account(principal: true)]);
    addTearDown(fixture.close);
    final controller = fixture.container.read(
      accountsControllerProvider.notifier,
    );
    await controller.load();
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        builder: (context, child) =>
            RepaintBoundary(key: capture, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEditAccountDialog(
                context,
                controller,
                () => fixture.container.read(accountsControllerProvider),
                fixture.store.accounts.first,
              ),
              child: const Text('Editar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Perfil principal'), findsOneWidget);
    await _capture(tester, capture, 'account-edit');
    await tester.tap(find.text('Suscripción'));
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextFormField, 'Precio por renovación');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '1.2.3');
    await tester.tap(find.text('Cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Precio por renovación:'), findsOneWidget);
    expect(fixture.store.saves, 0);
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '20.50');
    await tester.tap(find.text('Pagos compartidos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar persona'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Persona'),
      'Ana',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Aporte acordado'),
      '10.25',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Importe pagado'),
      '10.25',
    );
    await tester.ensureVisible(find.text('Agregar persona'));
    await tester.tap(find.text('Agregar persona'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Persona').last,
      'Luis',
    );
    final secondAmount = find
        .widgetWithText(TextFormField, 'Aporte acordado')
        .last;
    await tester.ensureVisible(secondAmount);
    await tester.enterText(secondAmount, '1.2.3');
    await tester.tap(find.text('Cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Luis:'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: secondAmount, matching: find.byType(TextField)),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
    expect(
      tester.getRect(secondAmount).overlaps(tester.getRect(find.byType(Form))),
      isTrue,
    );
    expect(fixture.store.saves, 0);
    await tester.ensureVisible(find.byTooltip('Quitar persona').last);
    await tester.tap(find.byTooltip('Quitar persona').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Persona'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Persona'))
          .controller!
          .text,
      'Ana',
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fixture.store.saves, 1);
    expect(fixture.store.details?.metadata.expectedAmountMinor, 2050);
    expect(fixture.store.details?.costShares.single.personName, 'Ana');
    expect(find.text('Datos de la cuenta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('create dialog stays usable at 900x600 with text $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture([]);
      addTearDown(fixture.close);
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: capture, child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreateProfileDialog(
                  context,
                  create: (_) async => null,
                  readError: () => null,
                ),
                child: const Text('Crear'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(
        find.text('1. Configura   →   2. Vincula   →   3. Cuenta creada'),
        findsOneWidget,
      );
      expect(find.textContaining('multi-cli'), findsNothing);
      if (scale == 1) await _capture(tester, capture, 'profile-create');
      await tester.tap(find.text('Crear y vincular'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Usa entre 1 y 48 caracteres'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('semantic colors meet contrast on light and dark surfaces', () {
    for (final accent in ['cyan', 'mint', 'amber']) {
      for (final theme in [AppTheme.dark(accent), AppTheme.light(accent)]) {
        final scheme = theme.colorScheme;
        for (final background in [
          scheme.surface,
          scheme.surfaceContainer,
          scheme.surfaceContainerHighest,
        ]) {
          for (final foreground in [
            scheme.onSurface,
            scheme.onSurfaceVariant,
            scheme.primary,
            scheme.error,
            scheme.tertiary,
          ]) {
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
        expect(
          _contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(scheme.onTertiary, scheme.tertiary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(scheme.onError, scheme.error),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

ThemeData _theme({
  double fontScale = .9,
  Brightness brightness = Brightness.dark,
}) {
  final theme = brightness == Brightness.dark
      ? AppTheme.dark('mint', fontScale: fontScale)
      : AppTheme.light('mint', fontScale: fontScale);
  if (!Platform.environment.containsKey('NINI_UI_REVIEW_FONT')) return theme;
  TextStyle? font(TextStyle? style) => style?.copyWith(fontFamily: 'Review');
  ButtonStyle? button(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStatePropertyAll(font(style.textStyle?.resolve({}))),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Review'),
    filledButtonTheme: FilledButtonThemeData(
      style: button(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(theme.textButtonTheme.style),
    ),
    tabBarTheme: theme.tabBarTheme.copyWith(
      labelStyle: font(theme.tabBarTheme.labelStyle),
      unselectedLabelStyle: font(theme.tabBarTheme.unselectedLabelStyle),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      titleTextStyle: font(theme.listTileTheme.titleTextStyle),
      subtitleTextStyle: font(theme.listTileTheme.subtitleTextStyle),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: font(theme.dialogTheme.titleTextStyle),
      contentTextStyle: font(theme.dialogTheme.contentTextStyle),
    ),
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['NINI_UI_REVIEW_DIR'];
  if (directory == null) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  await tester.pump();
}

double? _progress(WidgetTester tester, String limit, String type) => tester
    .widget<LinearProgressIndicator>(
      find.byKey(ValueKey('quota-progress-$limit-$type')),
    )
    .value;

Widget _card(
  Account account, {
  bool compact = false,
  bool profileMutationBusy = false,
  Future<void> Function(Account)? onDeleteProfile,
}) => MaterialApp(
  theme: _theme(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 450,
        height: (compact ? 142 : 154) + account.visibleWindows.length * 32.0,
        child: AccountCard(
          account: account,
          quotaNow: _now,
          refreshing: false,
          compact: compact,
          accountBusy: false,
          profileMutationBusy: profileMutationBusy,
          onEditAccount: () async {},
          onHeartbeat: (_) async {},
          onRefresh: (_) async {},
          onDeviceAuth: (_) async {},
          onRenameProfile: (_) async {},
          onDeleteProfile: onDeleteProfile ?? (_) async {},
          onLaunchAgent: (_) {},
        ),
      ),
    ),
  ),
);

Account _account({
  String id = 'account',
  double shortUsed = 0,
  double weeklyUsed = 20,
  int? credits = 2,
  bool extraLimit = false,
  bool expiredCredits = false,
  bool failed = false,
  bool networkFailure = true,
  bool partial = false,
  bool principal = false,
  AccountUsageState? state,
  bool hasAuthFile = true,
  bool unchecked = false,
  bool unknownQuota = false,
  ProfileKind kind = ProfileKind.full,
}) {
  final check = AccountUsageCheck(
    state: AccountUsageState.success,
    startedAt: _now,
    planType: 'Plus',
    accountEmail: '${id.toLowerCase()}@example.com',
  );
  final windows = [
    AccountQuotaWindow(
      limitId: 'codex',
      windowType: 'primary',
      usedPercent: shortUsed,
      windowDurationMinutes: 300,
      resetsAt: _now.add(const Duration(hours: 3)),
    ),
    AccountQuotaWindow(
      limitId: 'codex',
      windowType: 'secondary',
      usedPercent: weeklyUsed,
      windowDurationMinutes: 10080,
      resetsAt: _now.add(const Duration(days: 3)),
    ),
    if (extraLimit)
      AccountQuotaWindow(
        limitId: 'independent',
        windowType: 'primary',
        usedPercent: 0,
        windowDurationMinutes: 300,
        resetsAt: _now.add(const Duration(hours: 4)),
      ),
  ];
  return Account(
    profile: Profile(
      id: id,
      toolKey: 'codex',
      profileName: principal ? 'main' : id,
      displayName: principal ? 'main' : id,
      profileHome: '/synthetic/$id',
      commandName: 'codex-$id',
      source: principal ? ProfileSource.defaultProfile : ProfileSource.multiCli,
      kind: principal ? ProfileKind.base : kind,
      hasAuthFile: hasAuthFile,
      isAvailable: true,
      isFavorite: false,
    ),
    metadata: null,
    costShares: const [],
    currentCheck: unchecked
        ? null
        : state != null
        ? AccountUsageCheck(state: state, startedAt: _now)
        : failed
        ? AccountUsageCheck(
            state: AccountUsageState.error,
            startedAt: _now.add(const Duration(minutes: 1)),
            errorCode: networkFailure ? 'NETWORK_ERROR' : 'CODEX_RPC_ERROR',
          )
        : partial
        ? AccountUsageCheck(
            state: AccountUsageState.partial,
            startedAt: _now,
            errorCode: 'PARTIAL_METADATA',
          )
        : check,
    currentWindows: failed || unknownQuota ? [] : windows,
    lastSuccessfulCheck: check,
    lastSuccessfulWindows: windows,
    resetCredits: credits == null
        ? null
        : AccountResetCredits(
            availableCount: credits,
            nextExpiresAt: _now.add(Duration(days: expiredCredits ? -1 : 5)),
          ),
  );
}

class _Fixture {
  _Fixture(
    List<Account> accounts, {
    double fontScale = .9,
    bool compact = false,
    bool creation = false,
  }) : store = _Store(accounts) {
    final unused = creation
        ? (creationPorts = _CreationPorts(store))
        : _UnusedPorts();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        settingsCardLayoutProvider.overrideWithValue((
          fontScale: fontScale,
          compactCards: compact,
        )),
        accountsQuotaClockProvider.overrideWith((ref) => Stream.value(_now)),
        accountsControllerProvider.overrideWith(
          () => AccountsController(
            createLinkedAccount: creation
                ? CreateLinkedAccount(drafts: creationPorts!, gateway: unused)
                : null,
            loadAccounts: LoadAccounts(repository: store),
            updateAccount: UpdateAccount(
              accountRepository: store,
              profileRepository: unused,
            ),
            startDeviceAuth: StartAccountDeviceAuth(
              gateway: unused,
              activity: unused,
            ),
            completeDeviceAuth: CompleteAccountDeviceAuth(
              activity: unused,
              authenticationStore: unused,
              discovery: unused,
              accountRepository: store,
              monitorHeartbeatProfiles: (_) {},
              refreshUsage: (_) async {
                if (quotaGate != null) await quotaGate!.future;
                if (quotaFailure != null) throw quotaFailure!;
              },
              synchronizeUsageProjections: () async {},
            ),
          ),
        ),
      ],
    );
  }
  final database = AppDatabase(NativeDatabase.memory());
  final _Store store;
  _CreationPorts? creationPorts;
  Completer<void>? quotaGate;
  Object? quotaFailure;
  late final ProviderContainer container;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    container.dispose();
    await database.close();
  }
}

class _Store implements AccountRepository {
  _Store(this.accounts);
  final List<Account> accounts;
  int saves = 0;
  AccountDetails? details;
  @override
  Future<List<Account>> loadAll() async => accounts;
  @override
  Future<Account?> findById(String profileId) async =>
      accounts.where((a) => a.profile.id == profileId).firstOrNull;
  @override
  Future<void> saveDetails(AccountDetails value) async {
    saves++;
    details = value;
  }
}

class _UnusedPorts
    implements
        ProfileRepository,
        AccountDeviceAuthGateway,
        AccountDeviceAuthActivityRecorder,
        AccountAuthenticationStore,
        ProfileDiscovery {
  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected external effect: ${invocation.memberName}');
}

class _CreationPorts extends _UnusedPorts
    implements ProfileDraftStore, ProfileDraft, AccountDeviceAuthSession {
  _CreationPorts(this.store);
  final _Store store;
  final methods = <AccountAuthMethod>[];
  final events = <String>[];
  final completion = Completer<bool>();
  @override
  Profile get profile => _account(id: 'team').profile;
  @override
  Future<ProfileDraft> prepare({
    required String toolKey,
    required ProfileName name,
    required String displayName,
    required ProfileSetupMode setupMode,
  }) async {
    events.add('prepare');
    return this;
  }

  @override
  Future<Profile> publish() async {
    events.add('publish');
    store.accounts.add(_account(id: 'team'));
    return profile;
  }

  @override
  Future<void> discard() async {
    events.add('discard');
  }

  @override
  Future<List<Profile>> discover() async =>
      store.accounts.map((a) => a.profile).toList();
  @override
  Future<void> recordStarted(Profile profile) async {}
  @override
  Future<void> recordCompleted(
    Profile profile, {
    required bool success,
  }) async {}
  @override
  Future<void> markAuthenticated(String profileId) async {}
  @override
  Future<AccountDeviceAuthSession> start(
    Profile profile, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  }) async {
    methods.add(method);
    events.add('start');
    return this;
  }

  @override
  Future<bool> waitForCompletion() => completion.future;
  @override
  Future<void> cancel() async {
    events.add('cancel');
    if (!completion.isCompleted) completion.complete(false);
  }

  @override
  Future<void> close() async {
    events.add('close');
  }

  @override
  String get verificationUrl => 'https://example.com';
  @override
  String get userCode => 'TEST';
}
