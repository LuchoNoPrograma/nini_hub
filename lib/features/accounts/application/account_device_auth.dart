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

  Future<AccountDeviceAuthSession> call(Account account) async {
    await activity.recordStarted(account.profile);
    try {
      return await gateway.start(account.profile);
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

  Future<AccountSnapshot?> call(
    Account account, {
    required bool success,
  }) async {
    await activity.recordCompleted(account.profile, success: success);
    var progress = AccountDeviceAuthProgress.completionRecorded;
    try {
      if (success) {
        await authenticationStore.markAuthenticated(account.profile.id);
        progress = AccountDeviceAuthProgress.authenticationPersisted;
      }
      final profiles = await discovery.discover();
      monitorHeartbeatProfiles(
        profiles.where(
          (profile) =>
              profile.toolKey == 'codex' &&
              profile.isAvailable &&
              profile.hasAuthFile,
        ),
      );
      progress = AccountDeviceAuthProgress.profilesSynchronized;
      if (!success) return null;

      Profile? linked;
      for (final profile in profiles) {
        if (profile.id == account.profile.id) {
          linked = profile;
          break;
        }
      }
      if (linked != null && linked.isAvailable) {
        await refreshUsage(linked);
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
}
