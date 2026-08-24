import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/theme/app_theme.dart';
import 'package:multi_cli_ai/features/accounts/domain/account.dart';
import 'package:multi_cli_ai/features/accounts/domain/account_device_auth.dart';
import 'package:multi_cli_ai/features/accounts/presentation/account_dialogs.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';

void main() {
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
}

final class _ControlledSession implements AccountDeviceAuthSession {
  final Completer<bool> completion = Completer<bool>();
  int cancelCalls = 0;
  int closeCalls = 0;

  @override
  String get userCode => 'ABCD-EFGH';

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

Account _account() => Account(
  profile: const Profile(
    id: 'account',
    toolKey: 'codex',
    profileName: 'account',
    commandName: 'codex-account',
    displayName: 'Account',
    profileHome: '/profiles/account',
    source: ProfileSource.multiCli,
    kind: ProfileKind.full,
    hasAuthFile: false,
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
