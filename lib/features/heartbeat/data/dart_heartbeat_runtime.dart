import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';

final class SystemHeartbeatClock implements HeartbeatClock {
  const SystemHeartbeatClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class DartHeartbeatDelay implements HeartbeatDelay {
  const DartHeartbeatDelay();

  @override
  Future<void> wait(Duration duration) => Future<void>.delayed(duration);
}
