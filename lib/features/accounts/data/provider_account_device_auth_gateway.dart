import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';

/// Routes each profile to the sign-in flow of its own tool.
final class ProviderAccountDeviceAuthGateway
    implements AccountDeviceAuthGateway {
  const ProviderAccountDeviceAuthGateway(this.gateways);

  final Map<String, AccountDeviceAuthGateway> gateways;

  @override
  Future<AccountDeviceAuthSession> start(
    Profile profile, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  }) {
    final gateway = gateways[profile.toolKey];
    if (gateway == null) {
      throw UnsupportedProfileToolFailure(profile.toolKey);
    }
    return gateway.start(profile, method: method);
  }
}
