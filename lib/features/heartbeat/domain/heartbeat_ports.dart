import 'package:multi_cli_ai/features/heartbeat/domain/heartbeat.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';

abstract interface class HeartbeatStateRepository {
  Future<HeartbeatState> load(String profileId);

  Future<void> save({required String profileId, required HeartbeatState state});
}

abstract interface class HeartbeatHistoryRepository {
  Future<HeartbeatObservation?> loadLatestBefore({
    required String profileId,
    required DateTime before,
    required int expectedWindowMinutes,
  });
}

abstract interface class HeartbeatCommandGateway {
  Future<HeartbeatCommandResult> execute({
    required Profile profile,
    required String prompt,
  });
}

abstract interface class HeartbeatQuotaProbe {
  Future<UsageSnapshot> probe(Profile profile);
}

abstract interface class HeartbeatScheduler {
  bool get enabled;

  bool isRetained(String profileId);

  bool acquire(String profileId);

  void release(String profileId);

  void schedule({required Profile profile, required DateTime at});

  void cancel(String profileId);
}

abstract interface class HeartbeatActivityRecorder {
  Future<void> record({
    required Profile profile,
    required HeartbeatActivityKind kind,
    required String message,
  });
}

abstract interface class HeartbeatClock {
  DateTime nowUtc();
}

abstract interface class HeartbeatDelay {
  Future<void> wait(Duration duration);
}
