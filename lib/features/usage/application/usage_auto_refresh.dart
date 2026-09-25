import 'dart:collection';

import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_failure.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/features/usage/domain/usage_reset_refresh_policy.dart';

/// Owns deadlines independently of the visible page and of heartbeat settings.
final class UsageAutoRefresh {
  UsageAutoRefresh({
    required this.profiles,
    required this.gate,
    required this.refresh,
    required this.now,
    required this.isBlocked,
    required this.publish,
    required this.synchronize,
    required this.onFailure,
    this.concurrency = 3,
  });

  final ProfileRepository profiles;
  final UsageOperationGate gate;
  final Future<UsageSnapshot> Function(Profile) refresh;
  final DateTime Function() now;
  final bool Function() isBlocked;
  final void Function(String, UsageSnapshot) publish;
  final Future<void> Function() synchronize;
  final Future<void> Function(String?, Object) onFailure;
  final int concurrency;
  final Map<String, _TrackedUsage> _tracked = {};
  final Map<String, UsageSnapshot> _earlySnapshots = {};
  bool _disposed = false;
  bool _checking = false;
  DateTime? _deferredUntil;
  bool _needsSynchronization = false;
  int _mutationEpoch = 0;
  final Map<String, int> _readEpochs = {};

  /// Even a mutation that finishes before the network read invalidates it.
  void invalidatePendingReads() => _mutationEpoch++;

  bool hasObservedSnapshot(String profileId, UsageSnapshot snapshot) {
    final latest = _tracked[profileId]?.snapshot ?? _earlySnapshots[profileId];
    return latest != null &&
        latest.startedAt == snapshot.startedAt &&
        latest.completedAt == snapshot.completedAt;
  }

  UsageSnapshot? recentSnapshot(String profileId) {
    final snapshot = _tracked[profileId]?.snapshot;
    if (snapshot == null ||
        snapshot.windows.isEmpty ||
        (snapshot.status != UsageRefreshStatus.success &&
            snapshot.status != UsageRefreshStatus.partial) ||
        (snapshot.status != UsageRefreshStatus.success &&
            !snapshot.rateLimitsReadSucceeded)) {
      return null;
    }
    final age = now().toUtc().difference(snapshot.completedAt);
    return !age.isNegative && age <= const Duration(seconds: 30)
        ? snapshot
        : null;
  }

  DateTime? get nextAt {
    if (_disposed) return null;
    DateTime? result;
    for (final value in _tracked.values) {
      final at = value.nextAt;
      if (at != null && (result == null || at.isBefore(result))) result = at;
    }
    if (result != null &&
        _deferredUntil != null &&
        result.isBefore(_deferredUntil!)) {
      return _deferredUntil;
    }
    return result;
  }

  void replaceAccounts(Iterable<Account> accounts) {
    if (_disposed) return;
    final ids = <String>{};
    for (final account in accounts) {
      final profile = account.profile;
      ids.add(profile.id);
      final existing = _tracked[profile.id];
      final becameEligible =
          existing != null && !eligible(existing.profile) && eligible(profile);
      final entry = existing != null && sameIdentity(existing.profile, profile)
          ? existing
          : _TrackedUsage(profile);
      entry.profile = profile;
      _tracked[profile.id] = entry;
      final check = account.currentCheck ?? account.visibleCheck;
      final visible = account.visibleCheck;
      if (check != null) {
        // Persisted error reads retain the last known quota as a retry target.
        entry.observe(
          UsageSnapshot(
            status: UsageRefreshStatus.values.byName(check.state.name),
            startedAt: check.startedAt,
            completedAt: check.completedAt ?? check.startedAt,
            errorCode: check.errorCode,
            errorMessage: check.errorMessage,
            rateLimitsReadSucceeded: account.currentWindows.isNotEmpty,
            windows: account.visibleWindows.map(
              (window) => UsageQuotaWindow(
                limitId: window.limitId,
                windowType: window.windowType,
                windowDurationMinutes: window.windowDurationMinutes,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                reachedType: window.reachedType,
              ),
            ),
          ),
          quotaObservedAt: visible?.completedAt ?? visible?.startedAt,
          fromStorage: true,
        );
      }
      final early = _earlySnapshots.remove(profile.id);
      if (early != null) entry.observe(early);
      if (becameEligible) entry.paused = false;
    }
    _tracked.removeWhere((id, _) => !ids.contains(id));
    _earlySnapshots.removeWhere((id, _) => !ids.contains(id));
  }

  void observe(String profileId, UsageSnapshot snapshot) {
    if (_disposed) return;
    final entry = _tracked[profileId];
    if (entry == null) {
      final previous = _earlySnapshots[profileId];
      if (previous == null || snapshot.startedAt.isAfter(previous.startedAt)) {
        _earlySnapshots[profileId] = snapshot;
      }
      return;
    }
    entry.observe(snapshot);
  }

  /// Called again after the external read, before storing any automatic result.
  Future<bool> canPersist(Profile profile) async {
    if (_disposed || isBlocked() || _readEpochs[profile.id] != _mutationEpoch) {
      return false;
    }
    final entry = _tracked[profile.id];
    if (entry == null || !sameIdentity(entry.profile, profile)) return false;
    final current = await profiles.findById(profile.id);
    return !_disposed &&
        !isBlocked() &&
        _readEpochs[profile.id] == _mutationEpoch &&
        current != null &&
        eligible(current) &&
        sameIdentity(current, profile);
  }

  Future<void> refreshDue() async {
    if (_disposed || _checking) return;
    if (isBlocked()) {
      _deferredUntil = now().toUtc().add(const Duration(seconds: 30));
      return;
    }
    _deferredUntil = null;
    _checking = true;
    try {
      final due = _tracked.entries
          .where((entry) => _due(entry.value))
          .map((entry) => entry.key)
          .toList();
      final queue = Queue<String>.from(due);
      Future<void> worker() async {
        while (!_disposed && queue.isNotEmpty) {
          final id = queue.removeFirst();
          await gate.run(id, () async {
            final entry = _tracked[id];
            // A manual read or heartbeat may have resolved it while we waited.
            if (_disposed || isBlocked() || entry == null || !_due(entry)) {
              return;
            }
            try {
              final profile = await profiles.findById(id);
              if (profile == null ||
                  !eligible(profile) ||
                  !sameIdentity(entry.profile, profile)) {
                entry.paused = true;
                return;
              }
              _readEpochs[id] = _mutationEpoch;
              final snapshot = await refresh(profile);
              if (_disposed || !identical(_tracked[id], entry)) return;
              observe(id, snapshot);
              publish(id, snapshot);
              _needsSynchronization = true;
            } catch (error) {
              if (_disposed || !identical(_tracked[id], entry)) return;
              if (error case UsageRefreshAppliedFailure(:final snapshot)) {
                observe(id, snapshot);
                publish(id, snapshot);
                _needsSynchronization = true;
              } else {
                entry.failedAt(now().toUtc());
              }
              await _report(id, error);
            } finally {
              _readEpochs.remove(id);
            }
          });
        }
      }

      await Future.wait(
        List.generate(
          concurrency.clamp(1, 6).clamp(1, due.length.clamp(1, 6)),
          (_) => worker(),
        ),
      );
      if (!_disposed && _needsSynchronization && !isBlocked()) {
        try {
          await synchronize();
          _needsSynchronization = false;
        } catch (error) {
          // Publication failure retries local synchronization, not the network.
          await _report(null, error);
        }
      }
    } finally {
      _checking = false;
      _deferredUntil = _tracked.values.any(_due)
          ? now().toUtc().add(const Duration(seconds: 30))
          : null;
    }
  }

  bool _due(_TrackedUsage entry) =>
      entry.nextAt != null && !entry.nextAt!.isAfter(now().toUtc());

  Future<void> _report(String? id, Object error) async {
    try {
      await onFailure(id, error);
    } catch (_) {
      /* Best-effort activity. */
    }
  }

  void dispose() {
    _disposed = true;
    _tracked.clear();
    _earlySnapshots.clear();
    _readEpochs.clear();
  }

  static bool eligible(Profile profile) =>
      profile.isAvailable &&
      !profile.isDeactivated &&
      profile.hasAuthFile &&
      profileProviderOrNull(profile.toolKey)?.supportsUsage == true;

  static bool sameIdentity(Profile a, Profile b) =>
      a.id == b.id &&
      a.profileHome == b.profileHome &&
      a.toolKey == b.toolKey &&
      a.profileName == b.profileName &&
      a.source == b.source;
}

final class _TrackedUsage {
  _TrackedUsage(this.profile);
  Profile profile;
  List<UsageQuotaWindow> windows = [];
  DateTime? startedAt;
  DateTime? checkedAt;
  DateTime? quotaObservedAt;
  DateTime? retryAt;
  int failures = 0;
  bool paused = false;
  UsageSnapshot? snapshot;

  DateTime? get nextAt {
    if (paused || !UsageAutoRefresh.eligible(profile)) {
      return null;
    }
    if (quotaObservedAt == null) return retryAt;
    final natural = UsageResetRefreshPolicy.nextAt(
      windows,
      observedAt: quotaObservedAt!,
    );
    if (natural == null) return retryAt;
    if (retryAt == null) return natural;
    // A failed read before the reset deserves an earlier recovery attempt.
    // Once the reset has passed, back off instead of polling continuously.
    if (checkedAt != null && natural.isAfter(checkedAt!)) {
      return retryAt!.isBefore(natural) ? retryAt : natural;
    }
    return retryAt!.isAfter(natural) ? retryAt : natural;
  }

  void observe(
    UsageSnapshot snapshot, {
    DateTime? quotaObservedAt,
    bool fromStorage = false,
  }) {
    if (startedAt != null && !snapshot.startedAt.isAfter(startedAt!)) return;
    startedAt = snapshot.startedAt;
    checkedAt = snapshot.completedAt;
    this.snapshot = fromStorage ? null : snapshot;
    paused = UsageResetRefreshPolicy.pauses(snapshot.status);
    if (snapshot.windows.isNotEmpty &&
        (snapshot.status == UsageRefreshStatus.success ||
            snapshot.rateLimitsReadSucceeded)) {
      windows = snapshot.windows;
      this.quotaObservedAt = quotaObservedAt ?? snapshot.completedAt;
    } else if (snapshot.windows.isNotEmpty) {
      final merged = {
        for (final window in windows)
          '${window.limitId}/${window.windowType}': window,
      };
      for (final window in snapshot.windows) {
        merged['${window.limitId}/${window.windowType}'] = window;
      }
      windows = merged.values.toList();
      this.quotaObservedAt = quotaObservedAt ?? snapshot.completedAt;
    }
    final natural = this.quotaObservedAt == null
        ? null
        : UsageResetRefreshPolicy.nextAt(
            windows,
            observedAt: this.quotaObservedAt!,
          );
    final incomplete =
        snapshot.status == UsageRefreshStatus.timeout ||
        snapshot.status == UsageRefreshStatus.error ||
        ((snapshot.status == UsageRefreshStatus.success ||
                snapshot.status == UsageRefreshStatus.partial) &&
            (!snapshot.rateLimitsReadSucceeded || snapshot.windows.isEmpty));
    if (incomplete ||
        (natural != null && !natural.isAfter(snapshot.completedAt))) {
      final networkFailure =
          snapshot.status == UsageRefreshStatus.timeout ||
          snapshot.errorCode?.toUpperCase() == 'NETWORK_ERROR' ||
          (snapshot.errorMessage?.toLowerCase().contains(
                'workspace routing discovery failed',
              ) ??
              false);
      failedAt(snapshot.completedAt, networkFailure: networkFailure);
    } else {
      failures = 0;
      retryAt = null;
    }
  }

  void failedAt(DateTime at, {bool networkFailure = false}) {
    failures++;
    retryAt = at.add(
      networkFailure
          ? UsageResetRefreshPolicy.networkRetryDelay(failures)
          : UsageResetRefreshPolicy.retryDelay(failures),
    );
  }
}
