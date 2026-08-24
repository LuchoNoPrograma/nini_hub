import 'package:multi_cli_ai/features/profiles/domain/profile.dart';

abstract interface class AccountDeviceAuthSession {
  String get verificationUrl;

  String get userCode;

  Future<bool> waitForCompletion();

  Future<void> cancel();

  Future<void> close();
}

abstract interface class AccountDeviceAuthGateway {
  Future<AccountDeviceAuthSession> start(Profile profile);
}

abstract interface class AccountDeviceAuthActivityRecorder {
  Future<void> recordStarted(Profile profile);

  Future<void> recordCompleted(Profile profile, {required bool success});
}
