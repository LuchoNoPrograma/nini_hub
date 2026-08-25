import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';
import 'package:nini_hub/features/accounts/domain/account_repository.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

void main() {
  test('snapshot preserves search, status, and selection lookup semantics', () {
    final snapshot = AccountSnapshot([
      _account(
        id: 'alpha',
        displayName: 'Alpha',
        status: AccountUsageState.success,
        email: 'alpha@example.com',
      ),
      _account(id: 'beta', displayName: 'Beta'),
      _account(
        id: 'gamma',
        displayName: 'Gamma',
        status: AccountUsageState.error,
      ),
      _account(
        id: 'delta',
        displayName: 'Delta',
        toolKey: 'claude-cli',
        hasAuthFile: false,
      ),
      _account(id: 'epsilon', displayName: 'Epsilon', toolKey: 'claude-cli'),
    ]);

    expect(_ids(snapshot.visible(const AccountQuery())), [
      'alpha',
      'beta',
      'delta',
      'epsilon',
      'gamma',
    ]);
    expect(
      _ids(snapshot.visible(const AccountQuery(search: 'ALPHA@EXAMPLE.COM'))),
      ['alpha'],
    );
    expect(
      _ids(
        snapshot.visible(const AccountQuery(status: AccountStatusFilter.ready)),
      ),
      ['alpha', 'epsilon'],
    );
    expect(
      _ids(
        snapshot.visible(
          const AccountQuery(status: AccountStatusFilter.attention),
        ),
      ),
      ['gamma'],
    );
    expect(
      _ids(
        snapshot.visible(
          const AccountQuery(status: AccountStatusFilter.unlinked),
        ),
      ),
      ['delta'],
    );
    expect(snapshot.findById('beta')?.profile.id, 'beta');
    expect(
      () => snapshot.accounts.add(_account(id: 'x', displayName: 'X')),
      throwsUnsupportedError,
    );
  });

  test('snapshot preserves optional-value sort order and tie breakers', () {
    final base = DateTime.utc(2026, 8, 22);
    final snapshot = AccountSnapshot([
      _account(
        id: 'zeta',
        displayName: 'Zeta',
        usedPercent: 80,
        renewalOn: base.add(const Duration(days: 3)),
        resetAt: base.add(const Duration(hours: 4)),
      ),
      _account(
        id: 'alpha',
        displayName: 'Alpha',
        usedPercent: 10,
        resetAt: base.add(const Duration(hours: 2)),
      ),
      _account(
        id: 'mu',
        displayName: 'Mu',
        renewalOn: base.add(const Duration(days: 1)),
      ),
    ]);

    expect(
      _ids(
        snapshot.visible(
          const AccountQuery(sort: AccountSortMode.availability),
        ),
      ),
      ['alpha', 'zeta', 'mu'],
    );
    expect(
      _ids(snapshot.visible(const AccountQuery(sort: AccountSortMode.renewal))),
      ['mu', 'zeta', 'alpha'],
    );
    expect(
      _ids(snapshot.visible(const AccountQuery(sort: AccountSortMode.reset))),
      ['alpha', 'zeta', 'mu'],
    );
  });

  test('load returns the repository order in an immutable snapshot', () async {
    final events = <String>[];
    final stored = [_account(id: 'zeta', displayName: 'Zeta')];
    final repository = _MemoryAccountRepository(events: events, loaded: stored);

    final snapshot = await LoadAccounts(repository: repository)();

    expect(events, ['account.load']);
    expect(snapshot.accounts, stored);
    expect(() => snapshot.accounts.clear(), throwsUnsupportedError);
  });

  test('update validates existence before the first write', () async {
    final fixture = _Fixture(hasStoredAccount: false);

    await expectLater(
      fixture.update(_command()),
      throwsA(
        isA<AccountNotFoundFailure>().having(
          (failure) => failure.profileId,
          'profileId',
          'profile-id',
        ),
      ),
    );
    expect(fixture.events, ['account.find:profile-id']);
  });

  test(
    'update normalizes and preserves display, details, then load order',
    () async {
      final updated = _account(id: 'profile-id', displayName: 'Renamed');
      final fixture = _Fixture(loaded: [updated]);

      final result = await fixture.update(_command(displayName: '  Renamed  '));

      expect(fixture.events, [
        'account.find:profile-id',
        'profile.save:profile-id:Renamed:true',
        'account.save:profile-id',
        'account.load',
      ]);
      expect(result.account, same(updated));
      expect(result.snapshot.findById('profile-id'), same(updated));
      expect(
        fixture.accounts.saved?.metadata.accountEmail,
        'owner@example.com',
      );
      expect(fixture.accounts.saved?.metadata.currencyCode, 'BOB');
      expect(fixture.accounts.saved?.costShares, hasLength(1));
      expect(fixture.accounts.saved?.costShares.single.personName, 'Bea');
    },
  );

  test('display failure remains unapplied and stops details', () async {
    final cause = StateError('display failed');
    final fixture = _Fixture(profileSaveError: cause);

    await expectLater(fixture.update(_command()), throwsA(same(cause)));
    expect(fixture.events, [
      'account.find:profile-id',
      'profile.save:profile-id:profile-id:true',
    ]);
  });

  test('details failure reports that display data was already saved', () async {
    final cause = StateError('details failed');
    final fixture = _Fixture(accountSaveError: cause);

    await expectLater(
      fixture.update(_command()),
      throwsA(
        isA<AccountUpdateAppliedFailure>()
            .having(
              (failure) => failure.progress,
              'progress',
              AccountUpdateProgress.displaySaved,
            )
            .having((failure) => failure.cause, 'cause', same(cause)),
      ),
    );
    expect(fixture.events, [
      'account.find:profile-id',
      'profile.save:profile-id:profile-id:true',
      'account.save:profile-id',
    ]);
  });

  test(
    'reload failure reports that account details were already saved',
    () async {
      final cause = StateError('load failed');
      final fixture = _Fixture(accountLoadError: cause);

      await expectLater(
        fixture.update(_command()),
        throwsA(
          isA<AccountUpdateAppliedFailure>()
              .having(
                (failure) => failure.progress,
                'progress',
                AccountUpdateProgress.detailsSaved,
              )
              .having((failure) => failure.cause, 'cause', same(cause)),
        ),
      );
      expect(fixture.events.last, 'account.load');
    },
  );

  test(
    'missing post-save account is a typed details-applied failure',
    () async {
      final fixture = _Fixture(loaded: const []);

      await expectLater(
        fixture.update(_command()),
        throwsA(
          isA<AccountUpdateAppliedFailure>()
              .having(
                (failure) => failure.progress,
                'progress',
                AccountUpdateProgress.detailsSaved,
              )
              .having(
                (failure) => failure.cause,
                'cause',
                isA<AccountUpdateResultNotFoundFailure>(),
              ),
        ),
      );
    },
  );
}

final class _Fixture {
  _Fixture({
    bool hasStoredAccount = true,
    Account? found,
    List<Account>? loaded,
    Object? accountSaveError,
    Object? accountLoadError,
    Object? profileSaveError,
  }) : events = [],
       accounts = _MemoryAccountRepository(
         events: [],
         found: hasStoredAccount ? found ?? _account() : null,
         loaded: loaded ?? [_account()],
         saveError: accountSaveError,
         loadError: accountLoadError,
       ),
       profiles = _MemoryProfileRepository(
         events: [],
         saveError: profileSaveError,
       ) {
    accounts.events = events;
    profiles.events = events;
  }

  final List<String> events;
  final _MemoryAccountRepository accounts;
  final _MemoryProfileRepository profiles;

  Future<UpdateAccountResult> update(UpdateAccountCommand command) =>
      UpdateAccount(accountRepository: accounts, profileRepository: profiles)(
        command,
      );
}

final class _MemoryAccountRepository implements AccountRepository {
  _MemoryAccountRepository({
    required this.events,
    required this.loaded,
    this.found,
    this.saveError,
    this.loadError,
  });

  List<String> events;
  Account? found;
  final List<Account> loaded;
  final Object? saveError;
  final Object? loadError;
  AccountDetails? saved;

  @override
  Future<Account?> findById(String profileId) async {
    events.add('account.find:$profileId');
    return found;
  }

  @override
  Future<List<Account>> loadAll() async {
    events.add('account.load');
    final error = loadError;
    if (error != null) throw error;
    return loaded;
  }

  @override
  Future<void> saveDetails(AccountDetails details) async {
    events.add('account.save:${details.profileId}');
    saved = details;
    final error = saveError;
    if (error != null) throw error;
  }
}

final class _MemoryProfileRepository implements ProfileRepository {
  _MemoryProfileRepository({required this.events, this.saveError});

  List<String> events;
  final Object? saveError;

  @override
  Future<Profile?> findById(String profileId) async => null;

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {
    events.add('profile.save:$profileId:$displayName:$isFavorite');
    final error = saveError;
    if (error != null) throw error;
  }
}

UpdateAccountCommand _command({String displayName = '   '}) =>
    UpdateAccountCommand(
      profileId: 'profile-id',
      displayName: displayName,
      isFavorite: true,
      metadata: _metadata(
        accountEmail: ' owner@example.com ',
        currencyCode: ' bob ',
      ),
      costShares: const [
        AccountCostShare(
          id: 'blank',
          personName: '   ',
          expectedAmountMinor: 0,
          paidAmountMinor: 0,
          currencyCode: 'usd',
          paymentStatus: 'pending',
          paidOn: null,
          notes: '',
        ),
        AccountCostShare(
          id: 'bea',
          personName: ' Bea ',
          expectedAmountMinor: 500,
          paidAmountMinor: 250,
          currencyCode: ' bob ',
          paymentStatus: 'partial',
          paidOn: null,
          notes: ' Half ',
        ),
      ],
    );

List<String> _ids(List<Account> accounts) =>
    accounts.map((account) => account.profile.id).toList();

Account _account({
  String id = 'profile-id',
  String displayName = 'Team',
  String toolKey = 'codex',
  AccountUsageState? status,
  String? email,
  bool hasAuthFile = true,
  double? usedPercent,
  DateTime? renewalOn,
  DateTime? resetAt,
}) {
  final now = DateTime.utc(2026, 8, 22);
  final check = status == null && usedPercent == null
      ? null
      : AccountUsageCheck(
          state: status ?? AccountUsageState.success,
          startedAt: now,
          accountEmail: email,
        );
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
    metadata: renewalOn == null
        ? null
        : _metadata(accountEmail: '', nextRenewalOn: renewalOn),
    costShares: const [],
    currentCheck: check,
    currentWindows: usedPercent == null
        ? const []
        : [
            AccountQuotaWindow(
              limitId: id,
              windowType: 'primary',
              usedPercent: usedPercent,
              resetsAt: resetAt,
            ),
          ],
    lastSuccessfulCheck: check?.state == AccountUsageState.success
        ? check
        : null,
    lastSuccessfulWindows: const [],
    resetCredits: null,
  );
}

AccountMetadata _metadata({
  required String accountEmail,
  String currencyCode = 'USD',
  DateTime? nextRenewalOn,
}) => AccountMetadata(
  accountEmail: accountEmail,
  accountDisplayName: '',
  planName: '',
  notes: '',
  purchasedOn: null,
  nextRenewalOn: nextRenewalOn,
  billingInterval: 'monthly',
  expectedAmountMinor: 0,
  currencyCode: currencyCode,
  autoRenew: true,
  subscriptionStatus: 'active',
  purchasedFrom: '',
  paymentMethodLabel: '',
);
