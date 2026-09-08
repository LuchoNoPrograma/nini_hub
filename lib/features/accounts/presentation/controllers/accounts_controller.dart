import 'dart:async';

import 'package:nini_hub/features/accounts/application/create_linked_account.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
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
    this.createLinkedAccount,
  });

  final LoadAccounts loadAccounts;
  final UpdateAccount updateAccount;
  final StartAccountDeviceAuth startDeviceAuth;
  final CompleteAccountDeviceAuth completeDeviceAuth;
  final CreateLinkedAccount? createLinkedAccount;
}

final class AccountsController extends Notifier<AccountsState> {
  factory AccountsController({
    required LoadAccounts loadAccounts,
    required UpdateAccount updateAccount,
    required StartAccountDeviceAuth startDeviceAuth,
    required CompleteAccountDeviceAuth completeDeviceAuth,
    CreateLinkedAccount? createLinkedAccount,
  }) => AccountsController.composed(
    (_) => AccountsControllerDependencies(
      loadAccounts: loadAccounts,
      updateAccount: updateAccount,
      startDeviceAuth: startDeviceAuth,
      completeDeviceAuth: completeDeviceAuth,
      createLinkedAccount: createLinkedAccount,
    ),
  );

  AccountsController.composed(this._buildDependencies);

  final AccountsControllerDependenciesBuilder _buildDependencies;
  late AccountsControllerDependencies _dependencies;
  int _generation = 0;
  int _snapshotRevision = 0;

  @override
  AccountsState build() {
    _generation++;
    ref.onDispose(() => _generation++);
    _dependencies = _buildDependencies(ref);
    return AccountsState();
  }

  Future<Profile?> createLinkedAccount(
    CreateProfileCommand command, {
    required AccountAuthMethod method,
    required AccountAuthenticationInteraction authenticate,
  }) async {
    if (!_begin(AccountsOperation.create)) return null;
    final generation = _generation;
    try {
      final create = _dependencies.createLinkedAccount;
      if (create == null) {
        throw StateError('Account creation is not configured');
      }
      final profile = await create(
        command,
        method: method,
        authenticate: authenticate,
      );
      if (_generation != generation) return null;
      if (profile == null) {
        _completeOperation();
        return null;
      }
      try {
        final existing = await _dependencies.loadAccounts();
        if (_generation != generation) return null;
        final account = existing.findById(profile.id);
        if (account == null) throw AccountNotFoundFailure(profile.id);
        final snapshot = await _dependencies.completeDeviceAuth.confirm(
          account,
          success: true,
        );
        if (_generation != generation) return null;
        _publishSnapshot(snapshot!, selectedProfileId: profile.id);
        unawaited(refreshAuthUsage(snapshot.findById(profile.id)!));
      } catch (error) {
        throw AccountCreationPublicationFailure(profile, error);
      }
      return profile;
    } catch (error) {
      if (_generation == generation) _completeFailure(error);
      return null;
    }
  }

  Future<bool> load({String? removedProfileId}) async {
    if (!_begin(AccountsOperation.load)) return false;
    final generation = _generation;
    try {
      final snapshot = await _dependencies.loadAccounts();
      if (_generation != generation) return false;
      var selectedProfileId = state.selectedProfileId;
      if (selectedProfileId == removedProfileId) selectedProfileId = null;
      selectedProfileId ??= snapshot.accounts.isEmpty
          ? null
          : snapshot.accounts.first.profile.id;
      state = state.copyWith(
        operation: null,
        operationProfileId: null,
        snapshot: snapshot,
        isInitialized: true,
        query: state.query,
        selectedProfileId: selectedProfileId,
      );
      return true;
    } catch (error) {
      if (_generation == generation) _completeFailure(error);
      return false;
    }
  }

  Future<Account?> update(UpdateAccountCommand command) async {
    if (!_begin(AccountsOperation.update, profileId: command.profileId)) {
      return null;
    }
    final generation = _generation;
    try {
      final result = await _dependencies.updateAccount(command);
      if (_generation != generation) return null;
      final selectedProfileId =
          state.selectedProfileId ??
          (result.snapshot.accounts.isEmpty
              ? null
              : result.snapshot.accounts.first.profile.id);
      state = state.copyWith(
        operation: null,
        operationProfileId: null,
        snapshot: result.snapshot,
        isInitialized: true,
        query: state.query,
        selectedProfileId: selectedProfileId,
      );
      return result.account;
    } catch (error) {
      if (_generation == generation) _completeFailure(error);
      return null;
    }
  }

  Future<AccountDeviceAuthSession?> startDeviceAuth(
    Account account, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  }) async {
    if (!_begin(
      AccountsOperation.deviceAuthStart,
      profileId: account.profile.id,
    )) {
      return null;
    }
    final generation = _generation;
    try {
      final session = await _dependencies.startDeviceAuth(
        account,
        method: method,
      );
      if (_generation != generation) {
        await session.close();
        return null;
      }
      _completeOperation();
      return session;
    } catch (error) {
      if (_generation == generation) _completeFailure(error);
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
    final generation = _generation;
    try {
      final snapshot = await _dependencies.completeDeviceAuth.confirm(
        account,
        success: success,
      );
      if (_generation != generation) return false;
      if (snapshot == null) {
        _completeOperation();
        return true;
      }
      _publishSnapshot(snapshot);
      unawaited(refreshAuthUsage(snapshot.findById(account.profile.id)!));
      return true;
    } catch (error) {
      if (_generation == generation) _completeFailure(error);
      return false;
    }
  }

  /// Quota reads are tracked separately from authentication and never keep the
  /// login dialog or unrelated account operations waiting.
  Future<bool> refreshAuthUsage(Account account) async {
    final id = account.profile.id;
    if (state.authRefreshingProfileIds.contains(id) || state.isBusy) {
      return false;
    }
    final generation = _generation;
    final revision = ++_snapshotRevision;
    final failures = {...state.authRefreshFailures}..remove(id);
    state = state.copyWith(
      authRefreshingProfileIds: {...state.authRefreshingProfileIds, id},
      authRefreshFailures: failures,
    );
    try {
      final snapshot = await _dependencies.completeDeviceAuth.refreshConfirmed(
        account,
      );
      if (_generation != generation) return false;
      // A later load/edit/creation owns its snapshot, even if this request
      // finishes last. Keep local selection, filters and other progress intact.
      if (_snapshotRevision == revision && !state.isBusy) {
        state = state.copyWith(snapshot: snapshot);
      }
      return true;
    } catch (_) {
      if (_generation == generation) {
        state = state.copyWith(
          authRefreshFailures: {
            ...state.authRefreshFailures,
            id: 'El acceso está confirmado, pero no se pudieron actualizar las cuotas.',
          },
        );
      }
      return false;
    } finally {
      if (_generation == generation) {
        state = state.copyWith(
          authRefreshingProfileIds: {...state.authRefreshingProfileIds}
            ..remove(id),
        );
      }
    }
  }

  void _publishSnapshot(AccountSnapshot snapshot, {String? selectedProfileId}) {
    state = state.copyWith(
      snapshot: snapshot,
      isInitialized: true,
      selectedProfileId:
          selectedProfileId ??
          state.selectedProfileId ??
          (snapshot.accounts.isEmpty
              ? null
              : snapshot.accounts.first.profile.id),
      operation: null,
      operationProfileId: null,
    );
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
    if (state.isBusy ||
        (profileId != null &&
            state.authRefreshingProfileIds.contains(profileId))) {
      return false;
    }
    _snapshotRevision++;
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
    AccountCreationCleanupFailure() =>
      'No se completó el alta y no se pudo limpiar el perfil provisional. '
          'Revisa el perfil antes de volver a intentarlo.',
    AccountCreationPublicationFailure() =>
      'La cuenta se vinculó, pero no se pudo actualizar la lista. '
          'El perfil se conservó; vuelve a cargar las cuentas.',
    ProfileMutationAppliedFailure() =>
      'El motor no confirmó la creación. Revisa los perfiles antes de reintentar.',
    ProfileMutationRejectedFailure(
      reason: ProfileMutationRejectionReason.alreadyExists,
    ) =>
      'Ya existe un perfil con ese identificador.',
    ProfileMutationRejectedFailure() =>
      'El motor rechazó la preparación del perfil. No se completó el alta.',
    UnsupportedProfileToolFailure() =>
      'Esta herramienta todavía no permite vincular una cuenta desde Nini Hub.',
    InvalidProfileNameFailure() => 'El identificador del perfil no es válido.',
    _ when operation == AccountsOperation.create =>
      'No se pudo vincular la cuenta. Se descartó el perfil provisional; puedes reintentar.',
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
