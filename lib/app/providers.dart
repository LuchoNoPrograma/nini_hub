import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/accounts/application/account_device_auth.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/data/codex_account_device_auth_gateway.dart';
import 'package:nini_hub/features/accounts/data/drift_account_authentication_store.dart';
import 'package:nini_hub/features/accounts/data/drift_account_repository.dart';
import 'package:nini_hub/features/accounts/data/process_account_device_auth_activity_recorder.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/presentation/controllers/accounts_controller.dart';
import 'package:nini_hub/features/accounts/presentation/state/accounts_state.dart';
import 'package:nini_hub/features/activity/application/activity_history.dart';
import 'package:nini_hub/features/activity/data/drift_activity_repository.dart';
import 'package:nini_hub/features/activity/presentation/controllers/activity_controller.dart';
import 'package:nini_hub/features/activity/presentation/state/activity_state.dart';
import 'package:nini_hub/features/heartbeat/application/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/data/codex_heartbeat_quota_probe.dart';
import 'package:nini_hub/features/heartbeat/data/dart_heartbeat_runtime.dart';
import 'package:nini_hub/features/heartbeat/data/dart_heartbeat_scheduler.dart';
import 'package:nini_hub/features/heartbeat/data/drift_heartbeat_repository.dart';
import 'package:nini_hub/features/heartbeat/data/heartbeat_usage_keep_alive_scheduler.dart';
import 'package:nini_hub/features/heartbeat/data/process_heartbeat_activity_recorder.dart';
import 'package:nini_hub/features/heartbeat/data/process_heartbeat_command_gateway.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:nini_hub/features/heartbeat/presentation/controllers/heartbeat_controller.dart';
import 'package:nini_hub/features/heartbeat/presentation/state/heartbeat_state.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/data/drift_agent_profile_repository.dart';
import 'package:nini_hub/features/profiles/data/drift_profile_repository.dart';
import 'package:nini_hub/features/profiles/data/nini_agents_profile_lifecycle.dart';
import 'package:nini_hub/features/profiles/data/profile_discovery_service.dart';
import 'package:nini_hub/features/profiles/presentation/controllers/profiles_controller.dart';
import 'package:nini_hub/features/profiles/presentation/state/profiles_state.dart';
import 'package:nini_hub/features/settings/application/settings.dart';
import 'package:nini_hub/features/settings/data/desktop_settings_runtime.dart';
import 'package:nini_hub/features/settings/data/drift_settings_repository.dart';
import 'package:nini_hub/features/settings/presentation/controllers/settings_controller.dart';
import 'package:nini_hub/features/settings/presentation/state/settings_state.dart';
import 'package:nini_hub/features/usage/application/usage_calendar.dart';
import 'package:nini_hub/features/usage/application/usage_refresh.dart';
import 'package:nini_hub/features/usage/data/codex_usage_provider.dart';
import 'package:nini_hub/features/usage/data/drift_usage_calendar_repository.dart';
import 'package:nini_hub/features/usage/data/drift_usage_snapshot_repository.dart';
import 'package:nini_hub/features/usage/data/process_usage_activity_recorder.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/features/usage/presentation/controllers/usage_controller.dart';
import 'package:nini_hub/features/usage/presentation/controllers/usage_refresh_coordinator.dart';
import 'package:nini_hub/features/usage/presentation/state/usage_state.dart';
import 'package:nini_hub/features/workspaces/application/launch_agent.dart';
import 'package:nini_hub/features/workspaces/application/workspace_history.dart';
import 'package:nini_hub/features/workspaces/data/desktop_workspace_runtime.dart';
import 'package:nini_hub/features/workspaces/data/drift_workspace_repository.dart';
import 'package:nini_hub/features/workspaces/data/drift_workspace_selection_store.dart';
import 'package:nini_hub/features/workspaces/data/nini_agents_agent_launcher.dart';
import 'package:nini_hub/features/workspaces/presentation/controllers/workspace_controller.dart';
import 'package:nini_hub/features/workspaces/presentation/state/workspace_state.dart';
import 'package:nini_hub/providers/codex/codex_client_runtime.dart';

typedef WorkspaceDirectoryPicker =
    Future<String?> Function(String? initialDirectory);

final databaseProvider = Provider<AppDatabase>((ref) {
  throw StateError(
    'databaseProvider must receive the database prepared by DatabaseBootstrap.',
  );
});

final processRunnerProvider = Provider<ProcessRunner>(
  (ref) => ProcessRunner(ref.watch(databaseProvider)),
);

final niniAgentsClientProvider = Provider<NiniAgentsReadClient>(
  (ref) => NiniAgentsReadClient(ref.watch(processRunnerProvider)),
);

final codexClientRuntimeProvider = Provider<CodexClientRuntime>(
  (ref) => CodexClientRuntime(),
);

final accountDeviceAuthGatewayProvider = Provider<AccountDeviceAuthGateway>(
  (ref) => CodexAccountDeviceAuthGateway(ref.watch(codexClientRuntimeProvider)),
);

final heartbeatRepositoryProvider = Provider<DriftHeartbeatRepository>(
  (ref) => DriftHeartbeatRepository(ref.watch(databaseProvider)),
);

final Provider<DartHeartbeatScheduler> heartbeatSchedulerProvider =
    Provider<DartHeartbeatScheduler>((ref) {
      final scheduler = DartHeartbeatScheduler(
        onScheduledProbe: (profileId) =>
            ref.read(heartbeatScheduledProbeProvider)(profileId),
      );
      ref.onDispose(scheduler.dispose);
      return scheduler;
    });

final heartbeatExecuteProvider = Provider<ExecuteHeartbeat>((ref) {
  final runner = ref.watch(processRunnerProvider);
  return ExecuteHeartbeat(
    policy: const HeartbeatPolicy(),
    repository: ref.watch(heartbeatRepositoryProvider),
    command: ProcessHeartbeatCommandGateway(runner),
    probe: ref.watch(heartbeatQuotaProbeProvider),
    scheduler: ref.watch(heartbeatSchedulerProvider),
    clock: const SystemHeartbeatClock(),
    delay: const DartHeartbeatDelay(),
    activity: ProcessHeartbeatActivityRecorder(runner),
  );
});

final heartbeatQuotaProbeProvider = Provider<CodexHeartbeatQuotaProbe>(
  (ref) => CodexHeartbeatQuotaProbe(),
);

final heartbeatObserveUsageProvider = Provider<ObserveHeartbeatUsage>((ref) {
  final repository = ref.watch(heartbeatRepositoryProvider);
  return ObserveHeartbeatUsage(
    policy: const HeartbeatPolicy(),
    repository: repository,
    history: repository,
    scheduler: ref.watch(heartbeatSchedulerProvider),
    clock: const SystemHeartbeatClock(),
    activity: ProcessHeartbeatActivityRecorder(
      ref.watch(processRunnerProvider),
    ),
    execute: ref.watch(heartbeatExecuteProvider),
  );
});

final heartbeatProbeProvider = Provider<ProbeHeartbeat>(
  (ref) => ProbeHeartbeat(
    discovery: ref.watch(profileDiscoveryProvider),
    probe: ref.watch(heartbeatQuotaProbeProvider),
    scheduler: ref.watch(heartbeatSchedulerProvider),
    observe: ref.watch(heartbeatObserveUsageProvider),
  ),
);

final Provider<HeartbeatScheduledProbe> heartbeatScheduledProbeProvider =
    Provider<HeartbeatScheduledProbe>(
      (ref) => (profileId) async {
        await ref
            .read(heartbeatSchedulerProvider)
            .enqueueOperation<HeartbeatRunResult>(
              profileId: profileId,
              operation: () => ref.read(heartbeatProbeProvider)(profileId),
            );
      },
    );

final runHeartbeatUseCaseProvider = Provider<RunHeartbeat>(
  (ref) => RunHeartbeat(
    discovery: ref.watch(profileDiscoveryProvider),
    repository: ref.watch(heartbeatRepositoryProvider),
    scheduler: ref.watch(heartbeatSchedulerProvider),
    execute: ref.watch(heartbeatExecuteProvider),
  ),
);

final heartbeatRunnerProvider = Provider<HeartbeatRunner>((ref) {
  return ({required profileId, expectedWindowMinutes}) async {
    final scheduler = ref.read(heartbeatSchedulerProvider);
    if (!scheduler.enabled) {
      return const HeartbeatRunResult(
        outcome: HeartbeatOutcome.skipped,
        message: 'El inicio de ventanas está desactivado.',
      );
    }
    return await scheduler.enqueueOperation<HeartbeatRunResult>(
          profileId: profileId,
          operation: () => ref.read(runHeartbeatUseCaseProvider)(
            profileId: profileId,
            expectedWindowMinutes: expectedWindowMinutes,
          ),
        ) ??
        const HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'Ya hay un heartbeat en curso para esta cuenta.',
        );
  };
});

final heartbeatUsageKeepAliveProvider = Provider<UsageKeepAliveScheduler>(
  (ref) => HeartbeatUsageKeepAliveScheduler(
    scheduler: ref.watch(heartbeatSchedulerProvider),
    runner: ref.watch(processRunnerProvider),
    observe: ({required profile, required snapshot}) async {
      await ref.read(heartbeatObserveUsageProvider)(
        profile: profile,
        snapshot: snapshot,
      );
    },
  ),
);

final NotifierProvider<HeartbeatController, HeartbeatPresentationState>
heartbeatControllerProvider =
    NotifierProvider<HeartbeatController, HeartbeatPresentationState>(
      () => HeartbeatController.composed(
        (ref) => HeartbeatControllerDependencies(
          runHeartbeat: ref.watch(heartbeatRunnerProvider),
        ),
      ),
    );

typedef HeartbeatPostRunRefresh = Future<void> Function(String profileId);

final heartbeatPostRunRefreshProvider = Provider<HeartbeatPostRunRefresh>(
  (ref) =>
      (profileId) =>
          ref.read(usageRefreshCoordinatorProvider).refreshOne(profileId),
);

final profileDiscoveryProvider = Provider<ProfileDiscoveryService>(
  (ref) => ProfileDiscoveryService(
    ref.watch(databaseProvider),
    ref.watch(niniAgentsClientProvider),
  ),
);

final NotifierProvider<ProfilesController, ProfilesState>
profilesControllerProvider =
    NotifierProvider<ProfilesController, ProfilesState>(
      () => ProfilesController.composed((ref) {
        final database = ref.watch(databaseProvider);
        final repository = DriftProfileRepository(database);
        final discovery = ref.watch(profileDiscoveryProvider);
        final lifecycle = NiniAgentsProfileLifecycle(
          database,
          ref.watch(niniAgentsClientProvider),
          discovery,
        );
        return ProfilesControllerDependencies(
          discoverProfiles: DiscoverProfiles(discovery: discovery),
          createProfile: CreateProfile(
            repository: repository,
            discovery: discovery,
            lifecycle: lifecycle,
          ),
          renameProfile: RenameProfile(
            repository: repository,
            discovery: discovery,
            lifecycle: lifecycle,
          ),
          deleteProfile: DeleteProfile(
            repository: repository,
            discovery: discovery,
            lifecycle: lifecycle,
          ),
          updateProfileDisplay: UpdateProfileDisplay(repository: repository),
        );
      }),
    );

final NotifierProvider<AccountsController, AccountsState>
accountsControllerProvider =
    NotifierProvider<AccountsController, AccountsState>(
      () => AccountsController.composed((ref) {
        final database = ref.watch(databaseProvider);
        final accountRepository = DriftAccountRepository(database);
        final activity = ProcessAccountDeviceAuthActivityRecorder(
          ref.watch(processRunnerProvider),
        );
        final refreshAfterAuth = RefreshProfileUsage(
          provider: CodexUsageProvider.current(
            () => ref.read(codexClientRuntimeProvider).current,
          ),
          repository: DriftUsageSnapshotRepository(database),
          activity: ProcessUsageActivityRecorder(
            ref.watch(processRunnerProvider),
          ),
        );
        return AccountsControllerDependencies(
          loadAccounts: LoadAccounts(repository: accountRepository),
          updateAccount: UpdateAccount(
            accountRepository: accountRepository,
            profileRepository: DriftProfileRepository(database),
          ),
          startDeviceAuth: StartAccountDeviceAuth(
            gateway: ref.watch(accountDeviceAuthGatewayProvider),
            activity: activity,
          ),
          completeDeviceAuth: CompleteAccountDeviceAuth(
            activity: activity,
            authenticationStore: DriftAccountAuthenticationStore(database),
            discovery: ref.watch(profileDiscoveryProvider),
            accountRepository: accountRepository,
            monitorHeartbeatProfiles: (profiles) {
              ref.read(heartbeatSchedulerProvider).monitorProfiles(profiles);
            },
            refreshUsage: refreshAfterAuth.call,
            synchronizeUsageProjections: () =>
                ref.read(usageRefreshCoordinatorProvider).synchronizeCore(),
          ),
        );
      }),
    );

final NotifierProvider<ActivityController, ActivityState>
activityControllerProvider =
    NotifierProvider<ActivityController, ActivityState>(
      () => ActivityController.composed((ref) {
        final repository = DriftActivityRepository(ref.watch(databaseProvider));
        return ActivityControllerDependencies(
          loadActivityHistory: LoadActivityHistory(repository: repository),
          clearActivityHistory: ClearActivityHistory(repository: repository),
        );
      }),
    );

final NotifierProvider<UsageController, UsageState> usageControllerProvider =
    NotifierProvider<UsageController, UsageState>(
      () => UsageController.composed((ref) {
        final database = ref.watch(databaseProvider);
        final refreshProfile = RefreshProfileUsage(
          provider: CodexUsageProvider.current(
            () => ref.read(codexClientRuntimeProvider).current,
          ),
          repository: DriftUsageSnapshotRepository(database),
          activity: ProcessUsageActivityRecorder(
            ref.watch(processRunnerProvider),
          ),
          keepAlive: ref.watch(heartbeatUsageKeepAliveProvider),
        );
        final discovery = ref.watch(profileDiscoveryProvider);
        return UsageControllerDependencies(
          refreshUsage: RefreshUsage(
            discovery: discovery,
            refreshProfile: refreshProfile,
          ),
          refreshAllUsage: RefreshAllUsage(
            discovery: discovery,
            refreshProfile: refreshProfile,
          ),
          loadUsageCalendar: LoadUsageCalendar(
            repository: DriftUsageCalendarRepository(database),
          ),
          refreshConcurrency: () =>
              ref.read(settingsControllerProvider).preferences.concurrency,
        );
      }),
    );

final usageRefreshCoordinatorProvider = Provider<UsageRefreshCoordinator>(
  (ref) => UsageRefreshCoordinator(
    controller: ref.watch(usageControllerProvider.notifier),
    readState: () => ref.read(usageControllerProvider),
    reloadActivity: () async {
      final loaded = await ref.read(activityControllerProvider.notifier).load();
      if (loaded) return;
      final activity = ref.read(activityControllerProvider);
      if (activity.isBusy) return;
      throw activity.failure ?? StateError('No se pudo cargar el historial.');
    },
    reloadAccounts: () async {
      final loaded = await ref.read(accountsControllerProvider.notifier).load();
      if (loaded) return;
      throw ref.read(accountsControllerProvider).failure ??
          StateError('No se pudieron cargar las cuentas.');
    },
  ),
);

final NotifierProvider<SettingsController, SettingsState>
settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
      () => SettingsController.composed((ref) {
        final repository = DriftSettingsRepository(ref.watch(databaseProvider));
        final runtime = DesktopSettingsRuntime(
          discovery: ref.watch(profileDiscoveryProvider),
          requestTimeoutSetter: ref
              .read(codexClientRuntimeProvider)
              .setRequestTimeoutSeconds,
          weeklyKeepAliveEnabledSetter: (enabled) {
            ref.read(heartbeatSchedulerProvider).enabled = enabled;
          },
          monitorWeeklyProfiles: (profiles) {
            ref
                .read(heartbeatSchedulerProvider)
                .monitorProfileIds(profiles.map((profile) => profile.id));
          },
          onProfilesRefreshed: () async {
            final loaded = await ref
                .read(accountsControllerProvider.notifier)
                .load();
            if (loaded) return;
            throw ref.read(accountsControllerProvider).failure ??
                StateError('No se pudieron cargar las cuentas.');
          },
        );
        return SettingsControllerDependencies(
          loadSettings: LoadSettings(repository: repository, runtime: runtime),
          saveSettings: SaveSettings(repository: repository, runtime: runtime),
        );
      }),
    );

final settingsBootstrapProvider = FutureProvider<bool>((ref) async {
  final controller = ref.read(settingsControllerProvider.notifier);
  await Future<void>.delayed(Duration.zero);
  return controller.load();
});

final settingsCardLayoutProvider =
    Provider<({double fontScale, bool compactCards})>((ref) {
      return ref.watch(
        settingsControllerProvider.select(
          (state) => (
            fontScale: state.preferences.fontScale,
            compactCards: state.preferences.compactCards,
          ),
        ),
      );
    });

final workspaceDirectoryPickerProvider = Provider<WorkspaceDirectoryPicker>(
  (ref) =>
      (initialDirectory) => getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: 'Usar workspace',
        canCreateDirectories: true,
      ),
);

final workspaceFallbackDirectoryProvider = Provider<String>(
  (ref) => DesktopWorkspaceRuntime.userHomeDirectory(),
);

final workspaceControllerProvider =
    NotifierProvider<WorkspaceController, WorkspaceState>(
      () => WorkspaceController.composed((ref) {
        final database = ref.watch(databaseProvider);
        final repository = DriftWorkspaceRepository(database);
        final selectionStore = DriftWorkspaceSelectionStore(database);
        final runner = ref.watch(processRunnerProvider);
        return WorkspaceControllerDependencies(
          loadWorkspaceHistory: LoadWorkspaceHistory(
            repository: repository,
            selectionStore: selectionStore,
          ),
          addWorkspace: AddWorkspace(
            repository: repository,
            selectionStore: selectionStore,
          ),
          selectWorkspace: SelectWorkspace(
            repository: repository,
            selectionStore: selectionStore,
          ),
          renameWorkspace: RenameWorkspace(repository: repository),
          forgetWorkspace: ForgetWorkspace(
            repository: repository,
            selectionStore: selectionStore,
          ),
          launchAgent: LaunchAgent(
            profileRepository: DriftAgentProfileRepository(database),
            workspaceRepository: repository,
            selectionStore: selectionStore,
            launcher: NiniAgentsAgentLauncher(
              database,
              runner,
              keepTerminalOpenAfterExit: () => ref
                  .read(settingsControllerProvider)
                  .preferences
                  .keepTerminalOpenAfterExit,
            ),
          ),
        );
      }),
    );

final appStartupProvider = FutureProvider<void>((ref) async {
  await Future<void>.delayed(Duration.zero);
  final profiles = await ref.watch(profileDiscoveryProvider).discoverProfiles();
  await ref.watch(usageRefreshCoordinatorProvider).synchronizeCore();
  ref
      .read(heartbeatSchedulerProvider)
      .monitorProfileIds(
        profiles
            .where(
              (profile) =>
                  profile.toolKey == 'codex' &&
                  profile.isAvailable &&
                  profile.hasAuthFile,
            )
            .map((profile) => profile.id),
      );
  final accountsState = ref.read(accountsControllerProvider);
  if (accountsState.isInitialized || accountsState.isBusy) return;
  unawaited(ref.read(accountsControllerProvider.notifier).load());
});
