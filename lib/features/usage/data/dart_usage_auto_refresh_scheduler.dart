import 'dart:async';

typedef UsageRefreshTimerFactory = Timer Function(Duration, void Function());

/// One session timer; its short local wake-up also recovers wall-clock jumps.
final class DartUsageAutoRefreshScheduler {
  DartUsageAutoRefreshScheduler({
    required this.check,
    required this.nextAt,
    DateTime Function()? now,
    UsageRefreshTimerFactory? timerFactory,
  }) : now = now ?? DateTime.now,
       timerFactory = timerFactory ?? Timer.new;

  final Future<void> Function() check;
  final DateTime? Function() nextAt;
  final DateTime Function() now;
  final UsageRefreshTimerFactory timerFactory;
  Timer? _timer;
  bool _disposed = false;
  bool _running = false;

  void start() => reschedule();

  void reschedule() {
    if (_disposed || _running) return;
    _timer?.cancel();
    final deadline = nextAt();
    final remaining = deadline?.difference(now().toUtc());
    final delay = remaining == null || remaining > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : remaining.isNegative
        ? Duration.zero
        : remaining;
    _timer = timerFactory(delay, () => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_disposed || _running) return;
    _running = true;
    try {
      await check();
    } finally {
      _running = false;
      reschedule();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
