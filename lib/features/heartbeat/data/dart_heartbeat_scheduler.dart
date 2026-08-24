import 'dart:async';
import 'dart:collection';

import 'package:multi_cli_ai/features/heartbeat/data/dart_heartbeat_runtime.dart';
import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';

typedef HeartbeatScheduledProbe = Future<void> Function(String profileId);
typedef HeartbeatBackgroundFailureHandler =
    FutureOr<void> Function(Object error, StackTrace stackTrace);
typedef HeartbeatTimerFactory =
    Timer Function(Duration duration, void Function() callback);

final class DartHeartbeatScheduler implements HeartbeatScheduler {
  DartHeartbeatScheduler({
    required this.onScheduledProbe,
    HeartbeatClock? clock,
    HeartbeatTimerFactory? timerFactory,
  }) : _clock = clock ?? const SystemHeartbeatClock(),
       _timerFactory = timerFactory ?? _createTimer;

  final HeartbeatScheduledProbe onScheduledProbe;
  final HeartbeatClock _clock;
  final HeartbeatTimerFactory _timerFactory;
  final Queue<_QueuedHeartbeatOperation> _operationQueue = Queue();
  final Queue<String> _probeQueue = Queue();
  final Set<String> _queuedOperationProfiles = <String>{};
  final Set<String> _queuedProbeProfiles = <String>{};
  final Set<String> _retainedProfiles = <String>{};
  final Set<String> _initialProbeQueued = <String>{};
  final Set<String> _leases = <String>{};
  final Map<String, Timer> _probeTimers = <String, Timer>{};
  final Map<String, DateTime> _probeDeadlines = <String, DateTime>{};

  Future<void>? _operationDrainFuture;
  Future<void>? _probeDrainFuture;
  bool _enabled = true;
  bool _profilesConstrained = false;

  @override
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) return;

    for (final timer in _probeTimers.values) {
      timer.cancel();
    }
    _probeTimers.clear();
    _probeDeadlines.clear();
    _probeQueue.clear();
    _queuedProbeProfiles.clear();
    _initialProbeQueued.clear();
    while (_operationQueue.isNotEmpty) {
      final operation = _operationQueue.removeFirst();
      _queuedOperationProfiles.remove(operation.profileId);
      operation.cancel();
    }
  }

  DateTime? nextProbeAt(String profileId) => _probeDeadlines[profileId];

  void monitorProfiles(Iterable<Profile> profiles) =>
      monitorProfileIds(profiles.map((profile) => profile.id));

  void monitorProfileIds(Iterable<String> profileIds) {
    final ids = profileIds.toSet();
    retainProfiles(ids);
    _initialProbeQueued.retainAll(ids);
    if (!enabled) return;
    for (final profileId in ids) {
      if (_initialProbeQueued.add(profileId)) {
        _enqueueScheduledProbe(profileId);
      }
    }
  }

  void retainProfiles(Iterable<String> profileIds) {
    final retained = profileIds.toSet();
    _profilesConstrained = true;
    _retainedProfiles
      ..clear()
      ..addAll(retained);
    for (final profileId in _probeTimers.keys.toList(growable: false)) {
      if (!retained.contains(profileId)) cancel(profileId);
    }
  }

  Future<T?> enqueueOperation<T>({
    required String profileId,
    required Future<T> Function() operation,
  }) {
    if (!enabled || !_queuedOperationProfiles.add(profileId)) {
      return Future<T?>.value();
    }
    final queued = _QueuedHeartbeatOperationValue<T>(
      profileId: profileId,
      operation: operation,
    );
    _operationQueue.add(queued);
    _operationDrainFuture ??= _drainOperations();
    return queued.future;
  }

  bool enqueueBackgroundOperation({
    required String profileId,
    required Future<void> Function() operation,
    HeartbeatBackgroundFailureHandler? onError,
  }) {
    if (!enabled || !_queuedOperationProfiles.add(profileId)) return false;
    _operationQueue.add(
      _QueuedHeartbeatBackgroundOperation(
        profileId: profileId,
        operation: operation,
        onError: onError,
      ),
    );
    _operationDrainFuture ??= _drainOperations();
    return true;
  }

  @override
  bool isRetained(String profileId) => _retainedProfiles.contains(profileId);

  @override
  bool acquire(String profileId) => enabled && _leases.add(profileId);

  @override
  void release(String profileId) => _leases.remove(profileId);

  @override
  void schedule({required Profile profile, required DateTime at}) {
    if (!enabled) return;
    cancel(profile.id);
    final deadline = at.toUtc();
    final delay = deadline.difference(_clock.nowUtc().toUtc());
    late final Timer timer;
    timer = _timerFactory(delay.isNegative ? Duration.zero : delay, () {
      if (!identical(_probeTimers[profile.id], timer)) return;
      _probeTimers.remove(profile.id);
      _probeDeadlines.remove(profile.id);
      _enqueueScheduledProbe(profile.id);
    });
    _probeTimers[profile.id] = timer;
    _probeDeadlines[profile.id] = deadline;
  }

  @override
  void cancel(String profileId) {
    _probeTimers.remove(profileId)?.cancel();
    _probeDeadlines.remove(profileId);
  }

  Future<void> waitUntilIdle() async {
    while (_operationDrainFuture != null || _probeDrainFuture != null) {
      final pending = _probeDrainFuture ?? _operationDrainFuture;
      if (pending != null) await pending;
    }
  }

  void dispose() => enabled = false;

  Future<void> _drainOperations() async {
    try {
      while (_operationQueue.isNotEmpty) {
        final operation = _operationQueue.removeFirst();
        try {
          await operation.execute();
        } finally {
          _queuedOperationProfiles.remove(operation.profileId);
        }
      }
    } finally {
      _operationDrainFuture = null;
      if (_operationQueue.isNotEmpty) {
        _operationDrainFuture = _drainOperations();
      }
    }
  }

  void _enqueueScheduledProbe(String profileId) {
    if (!enabled || !_queuedProbeProfiles.add(profileId)) return;
    _probeQueue.add(profileId);
    _probeDrainFuture ??= _drainScheduledProbes();
  }

  Future<void> _drainScheduledProbes() async {
    try {
      while (enabled && _probeQueue.isNotEmpty) {
        final profileId = _probeQueue.removeFirst();
        try {
          if (!_profilesConstrained || _retainedProfiles.contains(profileId)) {
            await onScheduledProbe(profileId);
          }
        } catch (_) {
          // Background failures are handled by the scheduled probe use case.
        } finally {
          _queuedProbeProfiles.remove(profileId);
        }
      }
    } finally {
      _probeDrainFuture = null;
      if (enabled && _probeQueue.isNotEmpty) {
        _probeDrainFuture = _drainScheduledProbes();
      }
    }
  }

  static Timer _createTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}

abstract interface class _QueuedHeartbeatOperation {
  String get profileId;

  Future<void> execute();

  void cancel();
}

final class _QueuedHeartbeatOperationValue<T>
    implements _QueuedHeartbeatOperation {
  _QueuedHeartbeatOperationValue({
    required this.profileId,
    required this._operation,
  });

  @override
  final String profileId;
  final Future<T> Function() _operation;
  final Completer<T?> _completer = Completer<T?>();

  Future<T?> get future => _completer.future;

  @override
  Future<void> execute() async {
    try {
      final result = await _operation();
      if (!_completer.isCompleted) _completer.complete(result);
    } catch (error, stackTrace) {
      if (!_completer.isCompleted) {
        _completer.completeError(error, stackTrace);
      }
    }
  }

  @override
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

final class _QueuedHeartbeatBackgroundOperation
    implements _QueuedHeartbeatOperation {
  const _QueuedHeartbeatBackgroundOperation({
    required this.profileId,
    required this._operation,
    required this._onError,
  });

  @override
  final String profileId;
  final Future<void> Function() _operation;
  final HeartbeatBackgroundFailureHandler? _onError;

  @override
  Future<void> execute() async {
    try {
      await _operation();
    } catch (error, stackTrace) {
      try {
        await _onError?.call(error, stackTrace);
      } catch (_) {
        // Detached work must never leave an unhandled queue failure.
      }
    }
  }

  @override
  void cancel() {}
}
