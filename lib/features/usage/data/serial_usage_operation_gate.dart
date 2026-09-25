import 'dart:async';
import 'dart:collection';

import 'package:nini_hub/features/usage/domain/usage_ports.dart';

final class SerialUsageOperationGate implements UsageOperationGate {
  SerialUsageOperationGate({int Function()? concurrency})
    : _concurrency = concurrency ?? _defaultConcurrency;

  final int Function() _concurrency;
  final Map<String, Future<void>> _tails = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;

  static int _defaultConcurrency() => 3;

  @override
  Future<T> run<T>(String profileId, Future<T> Function() operation) async {
    final previous = _tails[profileId];
    final released = Completer<void>();
    _tails[profileId] = released.future;
    var acquired = false;
    try {
      if (previous != null) await previous;
      await _acquire();
      acquired = true;
      return await operation();
    } finally {
      if (acquired) _release();
      if (identical(_tails[profileId], released.future)) {
        _tails.remove(profileId);
      }
      released.complete();
    }
  }

  Future<void> _acquire() {
    if (_running < _concurrency().clamp(1, 6)) {
      _running++;
      return Future.value();
    }
    final ready = Completer<void>();
    _waiting.add(ready);
    return ready.future;
  }

  void _release() {
    _running--;
    while (_waiting.isNotEmpty && _running < _concurrency().clamp(1, 6)) {
      _running++;
      _waiting.removeFirst().complete();
    }
  }
}
