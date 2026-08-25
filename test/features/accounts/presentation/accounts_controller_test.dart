import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/application/account_device_auth.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';
import 'package:nini_hub/features/accounts/domain/account_repository.dart';
import 'package:nini_hub/features/accounts/presentation/controllers/accounts_controller.dart';
import 'package:nini_hub/features/accounts/presentation/state/accounts_state.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  test(
    'loads an immutable snapshot, preserves local query, and rejects overlap',
    () async {
      final gate = Completer<List<Account>>();
      fixture.accounts.loadGate = gate;

      final firstLoad = fixture.controller.load();
      final overlappingLoad = fixture.controller.load();
      fixture.controller.setSearch('ALPHA@EXAMPLE.COM');

      expect(fixture.state.isLoading, isTrue);
      expect(await overlappingLoad, isFalse);
      gate.complete([
        _account(id: 'beta', displayName: 'Beta'),
        _account(
          id: 'alpha',
          displayName: 'Alpha',
          state: AccountUsageState.success,
          email: 'alpha@example.com',
        ),
      ]);
      expect(await firstLoad, isTrue);

      expect(fixture.state.isInitialized, isTrue);
      expect(fixture.state.selectedProfileId, 'beta');
      expect(_visibleIds(fixture.state), ['alpha']);
      expect(
        () => fixture.state.accounts.add(_account(id: 'forbidden')),
        throwsUnsupportedError,
      );
    },
  );

  test('filters never clear selection and explicit removal does', () async {
    fixture.accounts.values = [
      _account(
        id: 'alpha',
        displayName: 'Alpha',
        state: AccountUsageState.success,
      ),
      _account(id: 'beta', displayName: 'Beta'),
      _account(
        id: 'delta',
        displayName: 'Delta',
        toolKey: 'claude-cli',
        hasAuthFile: false,
      ),
      _account(id: 'epsilon', displayName: 'Epsilon', toolKey: 'claude-cli'),
    ];
    expect(await fixture.controller.load(), isTrue);

    fixture.controller.selectAccount('beta');
    fixture.controller.setStatusFilter(AccountStatusFilter.ready);
    expect(_visibleIds(fixture.state), ['alpha', 'epsilon']);
    expect(fixture.state.selectedProfileId, 'beta');
    expect(fixture.state.selectedAccount?.profile.id, 'beta');

    fixture.controller.setStatusFilter(AccountStatusFilter.unlinked);
    expect(_visibleIds(fixture.state), ['delta']);
    expect(fixture.state.selectedProfileId, 'beta');

    fixture.accounts.values = [fixture.accounts.values.first];
    expect(await fixture.controller.load(removedProfileId: 'other'), isTrue);
    expect(fixture.state.selectedProfileId, 'beta');
    expect(fixture.state.selectedAccount?.profile.id, 'alpha');

    expect(await fixture.controller.load(removedProfileId: 'beta'), isTrue);
    expect(fixture.state.selectedProfileId, 'alpha');
    expect(fixture.state.query.status, AccountStatusFilter.unlinked);
  });

  test(
    'update replaces only the account snapshot and keeps view choices',
    () async {
      final original = _account(id: 'account', displayName: 'Original');
      final updated = _account(
        id: 'account',
        displayName: 'Renamed',
        state: AccountUsageState.success,
      );
      fixture.accounts.values = [original];
      expect(await fixture.controller.load(), isTrue);
      fixture.controller.setSearch('renamed');
      fixture.controller.setSort(AccountSortMode.availability);
      fixture.accounts.afterSaveValues = [updated];

      final result = await fixture.controller.update(
        _command(displayName: '  Renamed  '),
      );

      expect(result, same(updated));
      expect(fixture.state.accounts.single, same(updated));
      expect(fixture.state.selectedProfileId, 'account');
      expect(fixture.state.query.search, 'renamed');
      expect(fixture.state.query.sort, AccountSortMode.availability);
      expect(fixture.profiles.saved, ['account:Renamed:true']);
      expect(fixture.accounts.savedDetails?.profileId, 'account');
      expect(fixture.state.operation, isNull);
    },
  );

  test(
    'update is single-flight and retains local changes while awaiting',
    () async {
      fixture.accounts.values = [_account()];
      expect(await fixture.controller.load(), isTrue);
      final gate = Completer<void>();
      fixture.accounts.saveGate = gate;

      final update = fixture.controller.update(_command());
      await Future<void>.delayed(Duration.zero);
      fixture.controller.setSearch('team');

      expect(fixture.state.operation, AccountsOperation.update);
      expect(fixture.state.operationProfileId, 'account');
      expect(await fixture.controller.load(), isFalse);
      expect(await fixture.controller.update(_command()), isNull);
      gate.complete();
      expect(await update, isNotNull);
      expect(fixture.accounts.saveCalls, 1);
      expect(fixture.state.query.search, 'team');
      expect(fixture.state.operation, isNull);
    },
  );

  test('retains stale snapshot and explains typed partial failures', () async {
    final original = _account(displayName: 'Original');
    fixture.accounts.values = [original];
    expect(await fixture.controller.load(), isTrue);

    final detailsCause = StateError('details failed');
    fixture.accounts.nextSaveFailure = detailsCause;
    expect(await fixture.controller.update(_command()), isNull);
    expect(fixture.state.accounts.single, same(original));
    expect(
      fixture.state.failure,
      isA<AccountUpdateAppliedFailure>()
          .having(
            (failure) => failure.progress,
            'progress',
            AccountUpdateProgress.displaySaved,
          )
          .having((failure) => failure.cause, 'cause', same(detailsCause)),
    );
    expect(
      fixture.state.errorMessage,
      'El nombre y favorito se guardaron, pero no se pudieron guardar los '
      'datos de la cuenta.',
    );

    fixture.controller.clearFailure();
    expect(fixture.state.failure, isNull);
    final reloadCause = StateError('reload failed');
    fixture.accounts.nextLoadFailure = reloadCause;
    expect(await fixture.controller.update(_command()), isNull);
    expect(fixture.state.accounts.single, same(original));
    expect(
      fixture.state.failure,
      isA<AccountUpdateAppliedFailure>()
          .having(
            (failure) => failure.progress,
            'progress',
            AccountUpdateProgress.detailsSaved,
          )
          .having((failure) => failure.cause, 'cause', same(reloadCause)),
    );
    expect(
      fixture.state.errorMessage,
      'La cuenta se guardó, pero no se pudo actualizar la lista.',
    );
  });

  test(
    'translates missing and unexpected failures without losing state',
    () async {
      final original = _account();
      fixture.accounts.values = [original];
      expect(await fixture.controller.load(), isTrue);

      fixture.accounts.values = const [];
      expect(await fixture.controller.update(_command()), isNull);
      expect(fixture.state.accounts.single, same(original));
      expect(fixture.state.failure, isA<AccountNotFoundFailure>());
      expect(fixture.state.errorMessage, 'La cuenta ya no está disponible.');

      fixture.controller.clearFailure();
      final loadCause = StateError('database failed');
      fixture.accounts.nextLoadFailure = loadCause;
      expect(await fixture.controller.load(), isFalse);
      expect(fixture.state.accounts.single, same(original));
      expect(fixture.state.failure, same(loadCause));
      expect(fixture.state.errorMessage, 'No se pudieron cargar las cuentas.');
      expect(fixture.state.operation, isNull);
    },
  );

  test(
    'owns Device Auth start and completion without holding the wait',
    () async {
      final account = _account(hasAuthFile: false);
      fixture.accounts.values = [account];
      expect(await fixture.controller.load(), isTrue);

      final session = await fixture.controller.startDeviceAuth(account);

      expect(session, same(fixture.deviceAuthSession));
      expect(fixture.state.operation, isNull);
      expect(fixture.state.operationProfileId, isNull);

      expect(
        await fixture.controller.completeDeviceAuth(account, true),
        isTrue,
      );
      expect(fixture.authenticationStore.profileIds, ['account']);
      expect(fixture.state.accounts.single.profile.hasAuthFile, isTrue);
      expect(fixture.accounts.loadCalls, 2);
      expect(fixture.refreshedProfileIds, ['account']);
      expect(fixture.projectionSyncs, 1);
      expect(fixture.state.operation, isNull);
    },
  );
}

final class _Fixture {
  _Fixture()
    : accounts = _MemoryAccountRepository(),
      profiles = _MemoryProfileRepository(),
      deviceAuthSession = _FakeDeviceAuthSession() {
    final activity = _FakeDeviceAuthActivity();
    authenticationStore = _MemoryAccountAuthenticationStore(accounts);
    provider = NotifierProvider<AccountsController, AccountsState>(
      () => AccountsController(
        loadAccounts: LoadAccounts(repository: accounts),
        updateAccount: UpdateAccount(
          accountRepository: accounts,
          profileRepository: profiles,
        ),
        startDeviceAuth: StartAccountDeviceAuth(
          gateway: _FakeDeviceAuthGateway(deviceAuthSession),
          activity: activity,
        ),
        completeDeviceAuth: CompleteAccountDeviceAuth(
          activity: activity,
          authenticationStore: authenticationStore,
          discovery: _MemoryProfileDiscovery(() => accounts.values),
          accountRepository: accounts,
          monitorHeartbeatProfiles: (_) {},
          refreshUsage: (profile) async {
            refreshedProfileIds.add(profile.id);
          },
          synchronizeUsageProjections: () async => projectionSyncs++,
        ),
      ),
    );
    container = ProviderContainer();
    controller = container.read(provider.notifier);
  }

  final _MemoryAccountRepository accounts;
  final _MemoryProfileRepository profiles;
  final _FakeDeviceAuthSession deviceAuthSession;
  late final _MemoryAccountAuthenticationStore authenticationStore;
  final List<String> refreshedProfileIds = [];
  int projectionSyncs = 0;
  late final NotifierProvider<AccountsController, AccountsState> provider;
  late final ProviderContainer container;
  late final AccountsController controller;

  AccountsState get state => container.read(provider);

  void dispose() => container.dispose();
}

final class _FakeDeviceAuthGateway implements AccountDeviceAuthGateway {
  const _FakeDeviceAuthGateway(this.session);

  final AccountDeviceAuthSession session;

  @override
  Future<AccountDeviceAuthSession> start(Profile profile) async => session;
}

final class _FakeDeviceAuthSession implements AccountDeviceAuthSession {
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

final class _FakeDeviceAuthActivity
    implements AccountDeviceAuthActivityRecorder {
  @override
  Future<void> recordStarted(Profile profile) async {}

  @override
  Future<void> recordCompleted(
    Profile profile, {
    required bool success,
  }) async {}
}

final class _MemoryProfileDiscovery implements ProfileDiscovery {
  const _MemoryProfileDiscovery(this.accounts);

  final List<Account> Function() accounts;

  @override
  Future<List<Profile>> discover() async =>
      accounts().map((account) => account.profile).toList();
}

final class _MemoryAccountRepository implements AccountRepository {
  List<Account> values = [];
  List<Account>? afterSaveValues;
  Completer<List<Account>>? loadGate;
  Completer<void>? saveGate;
  Object? nextLoadFailure;
  Object? nextSaveFailure;
  AccountDetails? savedDetails;
  int saveCalls = 0;
  int loadCalls = 0;

  @override
  Future<List<Account>> loadAll() async {
    loadCalls++;
    final failure = nextLoadFailure;
    nextLoadFailure = null;
    if (failure != null) throw failure;
    final gate = loadGate;
    loadGate = null;
    return gate == null ? List.unmodifiable(values) : gate.future;
  }

  @override
  Future<Account?> findById(String profileId) async {
    for (final account in values) {
      if (account.profile.id == profileId) return account;
    }
    return null;
  }

  @override
  Future<void> saveDetails(AccountDetails details) async {
    saveCalls++;
    final gate = saveGate;
    saveGate = null;
    if (gate != null) await gate.future;
    final failure = nextSaveFailure;
    nextSaveFailure = null;
    if (failure != null) throw failure;
    savedDetails = details;
    final replacement = afterSaveValues;
    afterSaveValues = null;
    if (replacement != null) values = replacement;
  }
}

final class _MemoryAccountAuthenticationStore
    implements AccountAuthenticationStore {
  _MemoryAccountAuthenticationStore(this.accounts);

  final _MemoryAccountRepository accounts;
  final List<String> profileIds = [];

  @override
  Future<void> markAuthenticated(String profileId) async {
    profileIds.add(profileId);
    final index = accounts.values.indexWhere(
      (account) => account.profile.id == profileId,
    );
    if (index < 0) throw AccountNotFoundFailure(profileId);
    accounts.values[index] = _withAuthentication(accounts.values[index]);
  }
}

final class _MemoryProfileRepository implements ProfileRepository {
  final List<String> saved = [];

  @override
  Future<Profile?> findById(String profileId) async => null;

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {
    saved.add('$profileId:$displayName:$isFavorite');
  }
}

UpdateAccountCommand _command({String displayName = 'Account'}) =>
    UpdateAccountCommand(
      profileId: 'account',
      displayName: displayName,
      isFavorite: true,
      metadata: _editableMetadata(),
      costShares: const [],
    );

AccountEditableMetadata _editableMetadata() => const AccountEditableMetadata(
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
);

Account _account({
  String id = 'account',
  String displayName = 'Account',
  String toolKey = 'codex',
  bool hasAuthFile = true,
  AccountUsageState? state,
  String? email,
  double? usedPercent,
}) {
  final check = state == null
      ? null
      : AccountUsageCheck(
          state: state,
          startedAt: DateTime.utc(2026, 8, 22),
          accountEmail: email,
        );
  final windows = usedPercent == null
      ? const <AccountQuotaWindow>[]
      : [
          AccountQuotaWindow(
            limitId: '$id-limit',
            windowType: 'primary',
            usedPercent: usedPercent,
          ),
        ];
  return Account(
    profile: Profile(
      id: id,
      toolKey: toolKey,
      profileName: id,
      commandName: '$toolKey-$id',
      displayName: displayName,
      profileHome: '/profiles/$id',
      source: ProfileSource.multiCli,
      kind: ProfileKind.full,
      hasAuthFile: hasAuthFile,
      isAvailable: true,
      isFavorite: false,
    ),
    metadata: null,
    costShares: const [],
    currentCheck: check,
    currentWindows: windows,
    lastSuccessfulCheck: state == AccountUsageState.success ? check : null,
    lastSuccessfulWindows: windows,
    resetCredits: null,
  );
}

Account _withAuthentication(Account account) => Account(
  profile: Profile(
    id: account.profile.id,
    toolKey: account.profile.toolKey,
    profileName: account.profile.profileName,
    commandName: account.profile.commandName,
    displayName: account.profile.displayName,
    profileHome: account.profile.profileHome,
    source: account.profile.source,
    kind: account.profile.kind,
    hasAuthFile: true,
    isAvailable: account.profile.isAvailable,
    isFavorite: account.profile.isFavorite,
  ),
  metadata: account.metadata,
  costShares: account.costShares,
  currentCheck: account.currentCheck,
  currentWindows: account.currentWindows,
  lastSuccessfulCheck: account.lastSuccessfulCheck,
  lastSuccessfulWindows: account.lastSuccessfulWindows,
  resetCredits: account.resetCredits,
);

List<String> _visibleIds(AccountsState state) =>
    state.visibleAccounts.map((account) => account.profile.id).toList();
