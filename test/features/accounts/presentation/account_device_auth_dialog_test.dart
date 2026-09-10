import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/presentation/account_dialogs.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('DeviceCodeMono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    await loader.load();
  });
  for (final fails in [false, true]) {
    testWidgets('adjacent copy preserves ambiguous characters, failure=$fails', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const code = 'O0-I1l-B8-S5';
      final session = _ControlledSession(code: code);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (fails) throw PlatformException(code: 'unavailable');
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showDeviceAuthDialog(
                    context,
                    _account(),
                    method: AccountAuthMethod.deviceCode,
                    start: (_) async => session,
                    complete: (_, _) async {},
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final text = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == code,
        ),
      );
      expect(text.style!.fontFamily, 'DeviceCodeMono');
      final copy = find.byTooltip('Copiar código');
      expect(copy, findsOneWidget);
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();
      expect(copied, fails ? isEmpty : [code]);
      expect(
        find.text(
          fails
              ? 'No se pudo copiar. Selecciona el texto y vuelve a intentarlo.'
              : 'Código copiado.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      session.completion.complete(true);
      await tester.pumpAndSettle();
    });
  }

  for (final method in AccountAuthMethod.values) {
    testWidgets(
      'preselected $method opens authentication without asking again',
      (tester) async {
        final session = _ControlledSession();
        final started = <AccountAuthMethod>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    showDeviceAuthDialog(
                      context,
                      _account(),
                      method: method,
                      start: (_) async {
                        started.add(AccountAuthMethod.deviceCode);
                        return session;
                      },
                      startBrowser: (_) async {
                        started.add(AccountAuthMethod.browser);
                        return session;
                      },
                      complete: (_, _) async {},
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Abrir'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(started, [method]);
        expect(find.text('Vincular con ChatGPT'), findsNothing);
        expect(
          find.text('Copiar código'),
          method == AccountAuthMethod.deviceCode
              ? findsOneWidget
              : findsNothing,
        );
        session.completion.complete(true);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'browser choice starts only browser auth and hides device instructions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = _ControlledSession();
      var browsers = 0;
      var devices = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showDeviceAuthDialog(
                    context,
                    _account(),
                    start: (_) async {
                      devices++;
                      return session;
                    },
                    startBrowser: (_) async {
                      browsers++;
                      return session;
                    },
                    complete: (_, _) async {},
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(browsers, 0);
      expect(devices, 0);
      await tester.tap(find.text('Continuar en el navegador'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(browsers, 1);
      expect(devices, 0);
      expect(find.text('Copiar código'), findsNothing);
      expect(find.byTooltip('Copiar código'), findsNothing);
      expect(find.textContaining('habilita el acceso'), findsNothing);
      expect(tester.takeException(), isNull);
      session.completion.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('shows the domain session and closes after confirmed access', (
    tester,
  ) async {
    final session = _ControlledSession();
    final completed = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                showDeviceAuthDialog(
                  context,
                  _account(),
                  start: (_) async => session,
                  complete: (_, success) async => completed.add(success),
                ),
              ),
              child: const Text('Vincular'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Vincular'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Vincular Account'), findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.text('https://example.com/device'), findsOneWidget);

    session.completion.complete(true);
    await tester.pumpAndSettle();

    expect(completed, [true]);
    expect(find.text('Vincular Account'), findsNothing);
  });

  testWidgets(
    'confirmed access with a local save failure can be closed without cancelling auth',
    (tester) async {
      final session = _ControlledSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDeviceAuthDialog(
                  context,
                  _account(),
                  start: (_) async => session,
                  complete: (_, _) async => throw StateError('save failed'),
                ),
                child: const Text('Vincular'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Vincular'));
      await tester.pump();
      session.completion.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Cerrar'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel delegates to the owned session and closes the dialog', (
    tester,
  ) async {
    final session = _ControlledSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                showDeviceAuthDialog(
                  context,
                  _account(),
                  start: (_) async => session,
                  complete: (_, _) async {},
                ),
              ),
              child: const Text('Vincular'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Vincular'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(session.cancelCalls, 1);
    expect(find.text('Vincular Account'), findsNothing);
  });

  testWidgets('names a new Device Auth flow as relinking when auth exists', (
    tester,
  ) async {
    final session = _ControlledSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark('cyan'),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                showDeviceAuthDialog(
                  context,
                  _account(hasAuthFile: true),
                  start: (_) async => session,
                  complete: (_, _) async {},
                ),
              ),
              child: const Text('Revincular'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Revincular'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Revincular Account'), findsOneWidget);
    expect(find.text('Vincular Account'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(session.cancelCalls, 1);
  });
}

final class _ControlledSession implements AccountDeviceAuthSession {
  _ControlledSession({this.code = 'ABCD-EFGH'});

  final String code;
  final Completer<bool> completion = Completer<bool>();
  int cancelCalls = 0;
  int closeCalls = 0;

  @override
  String get userCode => code;

  @override
  String get verificationUrl => 'https://example.com/device';

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  Future<bool> waitForCompletion() => completion.future;
}

Account _account({bool hasAuthFile = false}) => Account(
  profile: Profile(
    id: 'account',
    toolKey: 'codex',
    profileName: 'account',
    commandName: 'codex-account',
    displayName: 'Account',
    profileHome: '/profiles/account',
    source: ProfileSource.multiCli,
    kind: ProfileKind.full,
    hasAuthFile: hasAuthFile,
    isAvailable: true,
    isFavorite: false,
  ),
  metadata: null,
  costShares: const [],
  currentCheck: null,
  currentWindows: const [],
  lastSuccessfulCheck: null,
  lastSuccessfulWindows: const [],
  resetCredits: null,
);
