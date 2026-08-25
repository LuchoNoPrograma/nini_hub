import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/features/accounts/application/account_device_auth.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';
import 'package:nini_hub/features/accounts/presentation/state/accounts_state.dart';

typedef AccountsControllerDependenciesBuilder =
    AccountsControllerDependencies Function(Ref<AccountsState> ref);

final class AccountsControllerDependencies {
  const AccountsControllerDependencies({
    required this.loadAccounts,
    required this.updateAccount,
    required this.startDeviceAuth,
    required this.completeDeviceAuth,
  });

  final LoadAccounts loadAccounts;
  final UpdateAccount updateAccount;
  final StartAccountDeviceAuth startDeviceAuth;
  final CompleteAccountDeviceAuth completeDeviceAuth;
}

final class AccountsController extends Notifier<AccountsState> {
  factory AccountsController({
    required LoadAccounts loadAccounts,
    required UpdateAccount updateAccount,
    required StartAccountDeviceAuth startDeviceAuth,
    required CompleteAccountDeviceAuth completeDeviceAuth,
  }) => AccountsController.composed(
    (_) => AccountsControllerDependencies(
      loadAccounts: loadAccounts,
      updateAccount: updateAccount,
      startDeviceAuth: startDeviceAuth,
      completeDeviceAuth: completeDeviceAuth,
    ),
  );

  AccountsController.composed(this._buildDependencies);

  final AccountsControllerDependenciesBuilder _buildDependencies;
  late AccountsControllerDependencies _dependencies;

  @override
  AccountsState build() {
    _dependencies = _buildDependencies(ref);
    return AccountsState();
  }

  Future<bool> load({String? removedProfileId}) async {
    if (!_begin(AccountsOperation.load)) return false;
    try {
      final snapshot = await _dependencies.loadAccounts();
      var selectedProfileId = state.selectedProfileId;
      if (selectedProfileId == removedProfileId) selectedProfileId = null;
      selectedProfileId ??= snapshot.accounts.isEmpty
          ? null
          : snapshot.accounts.first.profile.id;
      state = AccountsState(
        snapshot: snapshot,
        isInitialized: true,
        query: state.query,
        selectedProfileId: selectedProfileId,
      );
      return true;
    } catch (error) {
      _completeFailure(error);
      return false;
    }
  }

  Future<Account?> update(UpdateAccountCommand command) async {
    if (!_begin(AccountsOperation.update, profileId: command.profileId)) {
      return null;
    }
    try {
      final result = await _dependencies.updateAccount(command);
      final selectedProfileId =
          state.selectedProfileId ??
          (result.snapshot.accounts.isEmpty
              ? null
              : result.snapshot.accounts.first.profile.id);
      state = AccountsState(
        snapshot: result.snapshot,
        isInitialized: true,
        query: state.query,
        selectedProfileId: selectedProfileId,
      );
      return result.account;
    } catch (error) {
      _completeFailure(error);
      return null;
    }
  }

  Future<AccountDeviceAuthSession?> startDeviceAuth(Account account) async {
    if (!_begin(
      AccountsOperation.deviceAuthStart,
      profileId: account.profile.id,
    )) {
      return null;
    }
    try {
      final session = await _dependencies.startDeviceAuth(account);
      _completeOperation();
      return session;
    } catch (error) {
      _completeFailure(error);
      return null;
    }
  }

  Future<bool> completeDeviceAuth(Account account, bool success) async {
    if (!_begin(
      AccountsOperation.deviceAuthComplete,
      profileId: account.profile.id,
    )) {
      return false;
    }
    try {
      final snapshot = await _dependencies.completeDeviceAuth(
        account,
        success: success,
      );
      if (snapshot == null) {
        _completeOperation();
        return true;
      }
      final selectedProfileId =
          state.selectedProfileId ??
          (snapshot.accounts.isEmpty
              ? null
              : snapshot.accounts.first.profile.id);
      state = AccountsState(
        snapshot: snapshot,
        isInitialized: true,
        query: state.query,
        selectedProfileId: selectedProfileId,
      );
      return true;
    } catch (error) {
      _completeFailure(error);
      return false;
    }
  }

  void setSearch(String search) {
    state = state.copyWith(
      query: AccountQuery(
        search: search,
        status: state.query.status,
        sort: state.query.sort,
      ),
    );
  }

  void setStatusFilter(AccountStatusFilter status) {
    state = state.copyWith(
      query: AccountQuery(
        search: state.query.search,
        status: status,
        sort: state.query.sort,
      ),
    );
  }

  void setSort(AccountSortMode sort) {
    state = state.copyWith(
      query: AccountQuery(
        search: state.query.search,
        status: state.query.status,
        sort: sort,
      ),
    );
  }

  void selectAccount(String profileId) {
    state = state.copyWith(selectedProfileId: profileId);
  }

  void clearFailure() {
    if (state.failure == null && state.errorMessage == null) return;
    state = state.copyWith(failure: null, errorMessage: null);
  }

  bool _begin(AccountsOperation operation, {String? profileId}) {
    if (state.isBusy) return false;
    state = state.copyWith(
      operation: operation,
      operationProfileId: profileId,
      failure: null,
      errorMessage: null,
    );
    return true;
  }

  void _completeOperation() {
    state = state.copyWith(operation: null, operationProfileId: null);
  }

  void _completeFailure(Object error) {
    final operation = state.operation;
    state = state.copyWith(
      operation: null,
      operationProfileId: null,
      failure: error,
      errorMessage: _failureMessage(error, operation),
    );
  }

  static String _failureMessage(
    Object error,
    AccountsOperation? operation,
  ) => switch (error) {
    AccountNotFoundFailure() => 'La cuenta ya no está disponible.',
    AccountUpdateAppliedFailure(progress: AccountUpdateProgress.displaySaved) =>
      'El nombre y favorito se guardaron, pero no se pudieron guardar los '
          'datos de la cuenta.',
    AccountUpdateAppliedFailure(progress: AccountUpdateProgress.detailsSaved) =>
      'La cuenta se guardó, pero no se pudo actualizar la lista.',
    AccountUpdateResultNotFoundFailure() =>
      'La cuenta se guardó, pero no apareció al actualizar la lista.',
    _ when operation == AccountsOperation.load =>
      'No se pudieron cargar las cuentas.',
    _ when operation == AccountsOperation.deviceAuthStart =>
      'No se pudo iniciar la vinculación de la cuenta.',
    _ when operation == AccountsOperation.deviceAuthComplete =>
      'No se pudo completar la vinculación de la cuenta.',
    _ => 'No se pudieron guardar los datos de la cuenta.',
  };
}
