import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';

enum AccountsOperation {
  create,
  load,
  update,
  deviceAuthStart,
  deviceAuthComplete,
}

final class AccountsState {
  AccountsState({
    AccountSnapshot? snapshot,
    this.isInitialized = false,
    this.query = const AccountQuery(),
    this.selectedProfileId,
    this.operation,
    this.operationProfileId,
    this.errorMessage,
    this.failure,
    Iterable<String> authRefreshingProfileIds = const [],
    Map<String, String> authRefreshFailures = const {},
  }) : authRefreshingProfileIds = Set.unmodifiable(authRefreshingProfileIds),
       authRefreshFailures = Map.unmodifiable(authRefreshFailures),
       snapshot = snapshot ?? AccountSnapshot(const []);

  static const _unset = Object();

  final AccountSnapshot snapshot;
  final bool isInitialized;
  final AccountQuery query;
  final String? selectedProfileId;
  final AccountsOperation? operation;
  final String? operationProfileId;
  final String? errorMessage;
  final Object? failure;
  final Set<String> authRefreshingProfileIds;
  final Map<String, String> authRefreshFailures;

  List<Account> get accounts => snapshot.accounts;

  List<Account> get visibleAccounts => snapshot.visible(query);

  Account? get selectedAccount {
    final selectedId = selectedProfileId;
    if (selectedId != null) {
      final selected = snapshot.findById(selectedId);
      if (selected != null) return selected;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  bool get isBusy => operation != null;

  bool get isLoading => operation == AccountsOperation.load;

  bool get isUpdating => operation == AccountsOperation.update;

  AccountsState copyWith({
    AccountSnapshot? snapshot,
    bool? isInitialized,
    AccountQuery? query,
    Object? selectedProfileId = _unset,
    Object? operation = _unset,
    Object? operationProfileId = _unset,
    Object? errorMessage = _unset,
    Object? failure = _unset,
    Iterable<String>? authRefreshingProfileIds,
    Map<String, String>? authRefreshFailures,
  }) => AccountsState(
    snapshot: snapshot ?? this.snapshot,
    isInitialized: isInitialized ?? this.isInitialized,
    query: query ?? this.query,
    selectedProfileId: identical(selectedProfileId, _unset)
        ? this.selectedProfileId
        : selectedProfileId as String?,
    operation: identical(operation, _unset)
        ? this.operation
        : operation as AccountsOperation?,
    operationProfileId: identical(operationProfileId, _unset)
        ? this.operationProfileId
        : operationProfileId as String?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    failure: identical(failure, _unset) ? this.failure : failure,
    authRefreshingProfileIds:
        authRefreshingProfileIds ?? this.authRefreshingProfileIds,
    authRefreshFailures: authRefreshFailures ?? this.authRefreshFailures,
  );
}
