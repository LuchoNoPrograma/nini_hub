import 'package:nini_hub/features/profiles/domain/profile.dart';

enum AccountAuthMethod { browser, deviceCode }

abstract interface class AccountDeviceAuthSession {
  String get verificationUrl;

  String get userCode;

  Future<bool> waitForCompletion();

  Future<void> cancel();

  Future<void> close();
}

/// A session whose provider opens the sign-in page itself and may answer with
/// an authorization code that the user pastes back into the app.
abstract interface class AccountAuthorizationCodeSession
    implements AccountDeviceAuthSession {
  Future<void> submitAuthorizationCode(String code);
}

abstract interface class AccountDeviceAuthGateway {
  Future<AccountDeviceAuthSession> start(
    Profile profile, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  });
}

abstract interface class AccountDeviceAuthActivityRecorder {
  Future<void> recordStarted(Profile profile);

  Future<void> recordCompleted(Profile profile, {required bool success});
}

abstract interface class AccountAuthenticationStore {
  Future<void> markAuthenticated(String profileId);
}
