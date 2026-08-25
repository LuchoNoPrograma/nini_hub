import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AccountsQuotaNow = DateTime Function();

final accountsQuotaNowProvider = Provider<AccountsQuotaNow>(
  (ref) => DateTime.now,
);

final accountsQuotaClockProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final now = ref.watch(accountsQuotaNowProvider);
  return _quotaClock(now);
});

Stream<DateTime> _quotaClock(AccountsQuotaNow now) async* {
  yield now();
  yield* Stream<DateTime>.periodic(const Duration(minutes: 1), (_) => now());
}
