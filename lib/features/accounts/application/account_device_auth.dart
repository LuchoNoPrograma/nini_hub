import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';
import 'package:nini_hub/features/accounts/domain/account_repository.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

typedef AccountHeartbeatProfileMonitor =
    void Function(Iterable<Profile> profiles);
typedef AccountUsageRefresher = Future<void> Function(Profile profile);
typedef AccountUsageProjectionSynchronizer = Future<void> Function();

final class StartAccountDeviceAuth {
  const StartAccountDeviceAuth({required this.gateway, required this.activity});

  final AccountDeviceAuthGateway gateway;
  final AccountDeviceAuthActivityRecorder activity;

  Future<AccountDeviceAuthSession> call(
    Account account, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  }) async {
    await activity.recordStarted(account.profile);
    try {
      return await gateway.start(account.profile, method: method);
    } catch (error) {
      throw AccountDeviceAuthAppliedFailure(
        profileId: account.profile.id,
        progress: AccountDeviceAuthProgress.startRecorded,
        cause: error,
      );
    }
  }
}

final class CompleteAccountDeviceAuth {
  const CompleteAccountDeviceAuth({
    required this.activity,
    required this.authenticationStore,
    required this.discovery,
    required this.accountRepository,
    required this.monitorHeartbeatProfiles,
    required this.refreshUsage,
    required this.synchronizeUsageProjections,
  });

  final AccountDeviceAuthActivityRecorder activity;
  final AccountAuthenticationStore authenticationStore;
  final ProfileDiscovery discovery;
  final AccountRepository accountRepository;
  final AccountHeartbeatProfileMonitor monitorHeartbeatProfiles;
  final AccountUsageRefresher refreshUsage;
  final AccountUsageProjectionSynchronizer synchronizeUsageProjections;

  /// Convenience entry point for callers that need the fully refreshed snapshot.
  Future<AccountSnapshot?> call(
    Account account, {
    required bool success,
  }) async {
    final confirmed = await confirm(account, success: success);
    if (confirmed == null) return null;
    final linked = confirmed.findById(account.profile.id);
    if (linked == null) throw AccountNotFoundFailure(account.profile.id);
    return refreshConfirmed(linked);
  }

  /// Persists the confirmed login without waiting for external quota queries.
  /// The profile already exists: creation published it, and relinking updates
  /// only its authentication flag. Neither path needs another full discovery.
  Future<AccountSnapshot?> confirm(
    Account account, {
    required bool success,
  }) async {
    await activity.recordCompleted(account.profile, success: success);
    var progress = AccountDeviceAuthProgress.completionRecorded;
    try {
      if (!success) {
        final profiles = await discovery.discover();
        _monitor(profiles);
        return null;
      }
      await authenticationStore.markAuthenticated(account.profile.id);
      progress = AccountDeviceAuthProgress.authenticationPersisted;
      final snapshot = AccountSnapshot(await accountRepository.loadAll());
      if (snapshot.findById(account.profile.id) == null) {
        throw AccountNotFoundFailure(account.profile.id);
      }
      _monitor(snapshot.accounts.map((item) => item.profile));
      return snapshot;
    } catch (error) {
      throw AccountDeviceAuthAppliedFailure(
        profileId: account.profile.id,
        progress: progress,
        cause: error,
      );
    }
  }

  Future<AccountSnapshot> refreshConfirmed(Account account) async {
    var progress = AccountDeviceAuthProgress.profilesSynchronized;
    try {
      if (account.profile.isAvailable) {
        await refreshUsage(account.profile);
        progress = AccountDeviceAuthProgress.usageRefreshed;
        await synchronizeUsageProjections();
      }
      return AccountSnapshot(await accountRepository.loadAll());
    } catch (error) {
      throw AccountDeviceAuthAppliedFailure(
        profileId: account.profile.id,
        progress: progress,
        cause: error,
      );
    }
  }

  void _monitor(Iterable<Profile> profiles) => monitorHeartbeatProfiles(
    profiles.where(
      (profile) =>
          profile.toolKey == 'codex' &&
          profile.isAvailable &&
          profile.hasAuthFile,
    ),
  );
}
