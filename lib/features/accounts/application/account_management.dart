import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';
import 'package:nini_hub/features/accounts/domain/account_repository.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

enum AccountStatusFilter { all, ready, attention, unlinked }

enum AccountSortMode { name, availability, renewal, reset }

final class AccountQuery {
  const AccountQuery({
    this.search = '',
    this.status = AccountStatusFilter.all,
    this.sort = AccountSortMode.name,
  });

  final String search;
  final AccountStatusFilter status;
  final AccountSortMode sort;
}

final class AccountSnapshot {
  AccountSnapshot(Iterable<Account> accounts)
    : accounts = List.unmodifiable(accounts);

  final List<Account> accounts;

  Account? findById(String profileId) {
    for (final account in accounts) {
      if (account.profile.id == profileId) return account;
    }
    return null;
  }

  List<Account> visible(AccountQuery query) {
    final search = query.search.trim().toLowerCase();
    final visible = accounts.where((account) {
      final matchesSearch =
          search.isEmpty ||
          account.profile.displayName.toLowerCase().contains(search) ||
          account.profile.profileName.toLowerCase().contains(search) ||
          account.displayEmail.toLowerCase().contains(search);
      final matchesStatus = switch (query.status) {
        AccountStatusFilter.ready => account.isReady,
        AccountStatusFilter.attention => account.needsAttention,
        AccountStatusFilter.unlinked => account.isUnlinked,
        AccountStatusFilter.all => true,
      };
      return matchesSearch && matchesStatus;
    }).toList();
    visible.sort((left, right) => _compare(left, right, query.sort));
    return List.unmodifiable(visible);
  }

  static int _compare(Account left, Account right, AccountSortMode sort) {
    final bySelectedField = switch (sort) {
      AccountSortMode.name => 0,
      AccountSortMode.availability => _compareOptionalValuesDescending(
        left.lowestAvailablePercent,
        right.lowestAvailablePercent,
      ),
      AccountSortMode.renewal => _compareOptionalDates(
        left.metadata?.nextRenewalOn,
        right.metadata?.nextRenewalOn,
      ),
      AccountSortMode.reset => _compareOptionalDates(
        left.nextResetAt,
        right.nextResetAt,
      ),
    };
    if (bySelectedField != 0) return bySelectedField;

    final byName = left.profile.displayName.toLowerCase().compareTo(
      right.profile.displayName.toLowerCase(),
    );
    return byName != 0 ? byName : left.profile.id.compareTo(right.profile.id);
  }

  static int _compareOptionalDates(DateTime? left, DateTime? right) {
    if (left == null) return right == null ? 0 : 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  static int _compareOptionalValuesDescending(double? left, double? right) {
    if (left == null) return right == null ? 0 : 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }
}

final class LoadAccounts {
  const LoadAccounts({required this.repository});

  final AccountRepository repository;

  Future<AccountSnapshot> call() async =>
      AccountSnapshot(await repository.loadAll());
}

final class UpdateAccountCommand {
  UpdateAccountCommand({
    required this.profileId,
    required this.displayName,
    required this.isFavorite,
    required this.metadata,
    required Iterable<AccountCostShare> costShares,
  }) : costShares = List.unmodifiable(costShares);

  final String profileId;
  final String displayName;
  final bool isFavorite;
  final AccountMetadata metadata;
  final List<AccountCostShare> costShares;
}

final class UpdateAccountResult {
  const UpdateAccountResult({required this.account, required this.snapshot});

  final Account account;
  final AccountSnapshot snapshot;
}

final class UpdateAccount {
  const UpdateAccount({
    required this.accountRepository,
    required this.profileRepository,
  });

  final AccountRepository accountRepository;
  final ProfileRepository profileRepository;

  Future<UpdateAccountResult> call(UpdateAccountCommand command) async {
    final current = await accountRepository.findById(command.profileId);
    if (current == null) {
      throw AccountNotFoundFailure(command.profileId);
    }
    final displayName = current.profile.normalizedDisplayName(
      command.displayName,
    );
    final details = AccountDetails(
      profileId: command.profileId,
      metadata: command.metadata,
      costShares: command.costShares,
    ).normalizedForSave();

    await profileRepository.saveDisplayData(
      profileId: command.profileId,
      displayName: displayName,
      isFavorite: command.isFavorite,
    );

    try {
      await accountRepository.saveDetails(details);
    } catch (error) {
      throw AccountUpdateAppliedFailure(
        profileId: command.profileId,
        progress: AccountUpdateProgress.displaySaved,
        cause: error,
      );
    }

    try {
      final snapshot = AccountSnapshot(await accountRepository.loadAll());
      final updated = snapshot.findById(command.profileId);
      if (updated == null) {
        throw AccountUpdateResultNotFoundFailure(command.profileId);
      }
      return UpdateAccountResult(account: updated, snapshot: snapshot);
    } catch (error) {
      throw AccountUpdateAppliedFailure(
        profileId: command.profileId,
        progress: AccountUpdateProgress.detailsSaved,
        cause: error,
      );
    }
  }
}
