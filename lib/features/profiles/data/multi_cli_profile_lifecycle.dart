import 'package:multi_cli_ai/features/profiles/data/multi_cli_gateway.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_ports.dart';

final class MultiCliProfileLifecycle implements ProfileLifecycle {
  const MultiCliProfileLifecycle(this._gateway);

  final MultiCliGateway _gateway;

  @override
  Future<void> create({
    required String toolKey,
    required ProfileName profileName,
    required ProfileSetupMode setupMode,
    required bool seedFromBase,
  }) async {
    await _gateway.createProfile(
      toolKey: toolKey,
      profileName: profileName,
      setupMode: setupMode,
      seedFromBase: seedFromBase,
    );
  }

  @override
  Future<void> rename({
    required Profile profile,
    required ProfileName profileName,
  }) async {
    await _gateway.renameProfile(profile, profileName);
  }

  @override
  Future<void> delete(Profile profile) async {
    await _gateway.deleteProfile(profile);
  }
}
