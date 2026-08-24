import 'package:multi_cli_ai/features/accounts/domain/account.dart';

abstract interface class AccountRepository {
  Future<List<Account>> loadAll();

  Future<Account?> findById(String profileId);

  Future<void> saveDetails(AccountDetails details);
}
