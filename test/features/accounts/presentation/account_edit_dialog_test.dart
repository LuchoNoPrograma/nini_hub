import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/presentation/account_dialogs.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

void main() {
  testWidgets('recognized account email is visible but cannot be edited', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
    final controller = container.read(accountsControllerProvider.notifier);
    final account = _account();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(
              showEditAccountDialog(
                context,
                controller,
                () => container.read(accountsControllerProvider),
                account,
              ),
            ),
            child: const Text('Editar'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    final email = find.byKey(const ValueKey('account-observed-email'));
    expect(tester.widget<SelectableText>(email).data, 'observed@example.com');
    expect(
      find.ancestor(of: email, matching: find.byType(TextFormField)),
      findsNothing,
    );
    expect(find.text('stale@example.com'), findsNothing);
    expect(
      find.text(
        'Información de consulta; se actualiza al consultar la cuenta.',
      ),
      findsOneWidget,
    );
  });
}

Account _account() => Account(
  profile: const Profile(
    id: 'principal',
    toolKey: 'codex',
    profileName: 'principal',
    commandName: 'codex',
    displayName: 'Codex principal',
    profileHome: '/profiles/.codex',
    source: ProfileSource.defaultProfile,
    kind: ProfileKind.base,
    hasAuthFile: true,
    isAvailable: true,
    isFavorite: false,
  ),
  metadata: const AccountMetadata(
    accountEmail: 'stale@example.com',
    accountDisplayName: '',
    planName: '',
    notes: '',
    purchasedOn: null,
    nextRenewalOn: null,
    billingInterval: 'monthly',
    expectedAmountMinor: 0,
    currencyCode: 'USD',
    autoRenew: true,
    subscriptionStatus: 'active',
    purchasedFrom: '',
    paymentMethodLabel: '',
  ),
  costShares: const [],
  currentCheck: AccountUsageCheck(
    state: AccountUsageState.success,
    startedAt: DateTime.utc(2026, 8, 24),
    accountEmail: 'observed@example.com',
  ),
  currentWindows: const [],
  lastSuccessfulCheck: null,
  lastSuccessfulWindows: const [],
  resetCredits: null,
);
