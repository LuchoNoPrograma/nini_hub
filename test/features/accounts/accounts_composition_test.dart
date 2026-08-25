import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';

void main() {
  test(
    'real composition stays idle until load and persists an account update',
    () async {
      final counter = _SelectCounter();
      final database = AppDatabase(
        NativeDatabase.memory().interceptWith(counter),
      );
      final now = DateTime.utc(2026, 8, 22);
      await database
          .into(database.cliProfiles)
          .insert(
            CliProfile(
              id: 'account',
              toolKey: 'codex',
              profileName: 'team',
              commandName: 'codex-team',
              displayName: 'Original',
              profileHome: '/profiles/team',
              profileSource: 'multicli',
              profileType: 'full',
              hasAuthFile: true,
              isAvailable: true,
              isFavorite: false,
              createdAt: now,
              lastDiscoveredAt: now,
            ),
          );
      counter.selects = 0;
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final controller = container.read(accountsControllerProvider.notifier);

      expect(container.read(accountsControllerProvider).isInitialized, isFalse);
      expect(counter.selects, 0);
      expect(await controller.load(), isTrue);
      expect(container.read(accountsControllerProvider).accounts, hasLength(1));
      expect(
        container
            .read(accountsControllerProvider)
            .accounts
            .single
            .profile
            .displayName,
        'Original',
      );

      final updated = await controller.update(
        UpdateAccountCommand(
          profileId: 'account',
          displayName: '  Equipo  ',
          isFavorite: true,
          metadata: AccountEditableMetadata(
            accountDisplayName: ' Owner ',
            planName: ' Team ',
            notes: ' Notes ',
            purchasedOn: null,
            nextRenewalOn: null,
            billingInterval: 'monthly',
            expectedAmountMinor: 2500,
            currencyCode: ' bob ',
            autoRenew: true,
            subscriptionStatus: 'active',
            purchasedFrom: ' Web ',
            paymentMethodLabel: ' Card ',
          ),
          costShares: const [
            AccountCostShare(
              id: 'share',
              personName: ' Bea ',
              expectedAmountMinor: 1200,
              paidAmountMinor: 600,
              currencyCode: ' bob ',
              paymentStatus: 'partial',
              paidOn: null,
              notes: ' Half ',
            ),
          ],
        ),
      );

      expect(updated?.profile.displayName, 'Equipo');
      expect(updated?.profile.isFavorite, isTrue);
      expect(updated?.metadata?.accountEmail, isEmpty);
      expect(updated?.metadata?.currencyCode, 'BOB');
      expect(updated?.costShares.single.personName, 'Bea');
      expect(container.read(accountsControllerProvider).errorMessage, isNull);

      final storedProfile = await database
          .select(database.cliProfiles)
          .getSingle();
      final storedMetadata = await database
          .select(database.profileMetadatas)
          .getSingle();
      final storedShare = await database
          .select(database.costShares)
          .getSingle();
      expect(storedProfile.displayName, 'Equipo');
      expect(storedProfile.isFavorite, isTrue);
      expect(storedMetadata.accountEmail, isEmpty);
      expect(storedMetadata.currencyCode, 'BOB');
      expect(storedShare.personName, 'Bea');
      expect(storedShare.currencyCode, 'BOB');
    },
  );

  test(
    'dashboard bootstrap activates exactly one account projection',
    () async {
      final counter = _SelectCounter();
      final database = AppDatabase(
        NativeDatabase.memory().interceptWith(counter),
      );
      final now = DateTime.utc(2026, 8, 22);
      await database
          .into(database.cliProfiles)
          .insert(
            CliProfile(
              id: 'account',
              toolKey: 'codex',
              profileName: 'team',
              commandName: 'codex-team',
              displayName: 'Team',
              profileHome: '/profiles/team',
              profileSource: 'multicli',
              profileType: 'full',
              hasAuthFile: true,
              isAvailable: true,
              isFavorite: false,
              createdAt: now,
              lastDiscoveredAt: now,
            ),
          );
      counter
        ..selects = 0
        ..statements.clear();
      final scheduledHeartbeats = <String>[];
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          profileDiscoveryProvider.overrideWithValue(
            _StaticProfileDiscovery(database),
          ),
          heartbeatScheduledProbeProvider.overrideWithValue(
            (profileId) async => scheduledHeartbeats.add(profileId),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      expect(await container.read(settingsBootstrapProvider.future), isTrue);
      await container.read(appStartupProvider.future);
      await _waitForBootstrap(container);

      final accountsState = container.read(accountsControllerProvider);
      expect(accountsState.isInitialized, isTrue);
      expect(accountsState.accounts.single.profile.id, 'account');
      await container.read(heartbeatSchedulerProvider).waitUntilIdle();
      expect(scheduledHeartbeats, ['account']);
      expect(
        counter.statements.where(
          (statement) => statement.toLowerCase().contains('cost_shares'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'composition records Device Auth before using the configured gateway',
    () async {
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
              hasAuthFile: false,
              isAvailable: true,
              isFavorite: false,
              createdAt: now,
              lastDiscoveredAt: now,
            ),
          );
      final gateway = _RecordingDeviceAuthGateway();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          accountDeviceAuthGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });
      final controller = container.read(accountsControllerProvider.notifier);
      expect(await controller.load(), isTrue);
      final account = container
          .read(accountsControllerProvider)
          .accounts
          .single;

      final session = await controller.startDeviceAuth(account);

      expect(session, same(gateway.session));
      expect(gateway.profileIds, ['account']);
      final log = await database.select(database.commandLogs).getSingle();
      expect(log.command, 'codex app-server account/login/start');
      expect(log.status, 'success');
    },
  );

  test(
    'confirmed Device Auth persists auth and replaces the Accounts snapshot',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 8, 24);
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
              hasAuthFile: false,
              isAvailable: false,
              isFavorite: false,
              createdAt: now,
              lastDiscoveredAt: now,
            ),
          );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          profileDiscoveryProvider.overrideWithValue(
            _StaticProfileDiscovery(database),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });
      final controller = container.read(accountsControllerProvider.notifier);
      expect(await controller.load(), isTrue);
      final account = container
          .read(accountsControllerProvider)
          .accounts
          .single;
      expect(account.profile.hasAuthFile, isFalse);

      expect(await controller.completeDeviceAuth(account, true), isTrue);

      final stored = await database.select(database.cliProfiles).getSingle();
      expect(stored.hasAuthFile, isTrue);
      expect(
        container
            .read(accountsControllerProvider)
            .accounts
            .single
            .profile
            .hasAuthFile,
        isTrue,
      );
    },
  );
}

final class _RecordingDeviceAuthGateway implements AccountDeviceAuthGateway {
  final _CompositionDeviceAuthSession session = _CompositionDeviceAuthSession();
  final List<String> profileIds = [];

  @override
  Future<AccountDeviceAuthSession> start(Profile profile) async {
    profileIds.add(profile.id);
    return session;
  }
}

final class _CompositionDeviceAuthSession implements AccountDeviceAuthSession {
  @override
  String get userCode => 'ABCD-EFGH';

  @override
  String get verificationUrl => 'https://example.com/device';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> waitForCompletion() async => true;
}

final class _SelectCounter extends QueryInterceptor {
  int selects = 0;
  final List<String> statements = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

final class _StaticProfileDiscovery extends ProfileDiscoveryService {
  _StaticProfileDiscovery(super.database) : super.test();

  @override
  Future<List<CliProfile>> discoverProfiles() =>
      database.select(database.cliProfiles).get();
}

Future<void> _waitForBootstrap(ProviderContainer container) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (container.read(accountsControllerProvider).isInitialized) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Dashboard and Accounts did not finish bootstrap.');
}
