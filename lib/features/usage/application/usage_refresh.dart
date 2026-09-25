import 'dart:collection';

import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_failure.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';

typedef UsageRefreshProgressCallback =
    void Function(String profileId, UsageSnapshot snapshot);
typedef UsageBatchTargetsCallback = void Function(List<String> profileIds);
typedef UsageBatchProfileCallback = void Function(String profileId);
typedef UsageBatchFailureCallback =
    void Function(String profileId, Object error);

final class UsageBatchResult {
  UsageBatchResult(Map<String, UsageSnapshot> byProfile)
    : byProfile = Map.unmodifiable(byProfile);

  final Map<String, UsageSnapshot> byProfile;
}

final class RefreshProfileUsage {
  const RefreshProfileUsage({
    required this.provider,
    required this.repository,
    required this.activity,
    this.keepAlive,
    this.operationGate,
    this.onPersisted,
    this.canPersist,
    this.completedWhileWaiting,
    this.now = DateTime.now,
  });

  final UsageProvider provider;
  final UsageSnapshotRepository repository;
  final UsageActivityRecorder activity;
  final UsageKeepAliveScheduler? keepAlive;
  final UsageOperationGate? operationGate;
  final void Function(String profileId, UsageSnapshot snapshot)? onPersisted;
  final Future<bool> Function(Profile profile)? canPersist;
  final UsageSnapshot? Function(String profileId)? completedWhileWaiting;
  final DateTime Function() now;

  Future<UsageSnapshot> call(Profile profile) {
    final requestedAt = now().toUtc();
    Future<UsageSnapshot> read() {
      _validate(profile);
      final recent = completedWhileWaiting?.call(profile.id);
      if (recent != null && !recent.completedAt.isBefore(requestedAt)) {
        return Future.value(recent);
      }
      return _refresh(profile);
    }

    return operationGate?.run(profile.id, read) ?? read();
  }

  Future<UsageSnapshot> _refresh(Profile profile) async {
    _validate(profile);
    final snapshot = await provider.refresh(profile);
    if (canPersist != null && !await canPersist!(profile)) {
      throw UsageProfileUnavailableFailure(
        profileId: profile.id,
        reason: UsageProfileUnavailableReason.unavailable,
      );
    }
    await repository.saveSnapshot(profileId: profile.id, snapshot: snapshot);
    onPersisted?.call(profile.id, snapshot);

    try {
      await activity.recordRefresh(profile: profile, snapshot: snapshot);
    } catch (error) {
      throw UsageRefreshAppliedFailure(
        profileId: profile.id,
        progress: UsageRefreshProgress.snapshotPersisted,
        snapshot: snapshot,
        cause: error,
      );
    }

    try {
      keepAlive?.scheduleIfEligible(profile: profile, snapshot: snapshot);
    } catch (error) {
      throw UsageRefreshAppliedFailure(
        profileId: profile.id,
        progress: UsageRefreshProgress.activityRecorded,
        snapshot: snapshot,
        cause: error,
      );
    }
    return snapshot;
  }

  static void _validate(Profile profile) {
    if (!profile.isAvailable) {
      throw UsageProfileUnavailableFailure(
        profileId: profile.id,
        reason: profile.isDeactivated
            ? UsageProfileUnavailableReason.deactivated
            : UsageProfileUnavailableReason.unavailable,
      );
    }
    final profileProvider = profileProviderOrNull(profile.toolKey);
    if (profileProvider?.supportsUsage != true) {
      throw UsageUnsupportedProviderFailure(
        profileId: profile.id,
        toolKey: profile.toolKey,
      );
    }
  }
}

final class RefreshUsage {
  const RefreshUsage({required this.discovery, required this.refreshProfile});

  final ProfileDiscovery discovery;
  final RefreshProfileUsage refreshProfile;

  Future<UsageSnapshot> call(String profileId) async {
    final profiles = await discovery.discover();
    Profile? selected;
    for (final profile in profiles) {
      if (profile.id == profileId) {
        selected = profile;
        break;
      }
    }
    if (selected == null) throw UsageProfileNotFoundFailure(profileId);
    return refreshProfile(selected);
  }
}

final class RefreshAllUsage {
  const RefreshAllUsage({
    required this.discovery,
    required this.refreshProfile,
  });

  final ProfileDiscovery discovery;
  final RefreshProfileUsage refreshProfile;

  Future<UsageBatchResult> call({
    int concurrency = 3,
    UsageBatchTargetsCallback? onTargets,
    UsageBatchProfileCallback? onStarted,
    UsageRefreshProgressCallback? onProgress,
    UsageBatchFailureCallback? onFailure,
  }) async {
    final profiles = await discovery.discover();
    final targets = profiles.where((profile) {
      final provider = profileProviderOrNull(profile.toolKey);
      return profile.isAvailable && provider?.supportsUsage == true;
    }).toList();
    onTargets?.call(List.unmodifiable(targets.map((profile) => profile.id)));
    if (targets.isEmpty) return UsageBatchResult(const {});

    final queue = Queue<Profile>.from(targets);
    final completed = <String, UsageSnapshot>{};
    final workerCount = concurrency.clamp(1, 6).clamp(1, queue.length);
    Object? firstFailure;
    String? failedProfileId;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final profile = queue.removeFirst();
        onStarted?.call(profile.id);
        try {
          final snapshot = await refreshProfile(profile);
          completed[profile.id] = snapshot;
          onProgress?.call(profile.id, snapshot);
        } catch (error) {
          onFailure?.call(profile.id, error);
          firstFailure ??= error;
          failedProfileId ??= profile.id;
        }
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
    final failure = firstFailure;
    if (failure != null) {
      throw UsageBatchFailure(
        failedProfileId: failedProfileId!,
        completedByProfile: completed,
        cause: failure,
      );
    }
    return UsageBatchResult(completed);
  }
}
