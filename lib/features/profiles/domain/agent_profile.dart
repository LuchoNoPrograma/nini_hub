import 'package:multi_cli_ai/features/profiles/domain/profile_provider.dart';

final class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.toolKey,
    required this.profileName,
    required this.displayName,
    required this.profileHome,
    required this.profileSource,
    required this.hasAuthFile,
    required this.isAvailable,
  });

  final String id;
  final String toolKey;
  final String profileName;
  final String displayName;
  final String profileHome;
  final String profileSource;
  final bool hasAuthFile;
  final bool isAvailable;

  bool get canLaunch {
    final provider = profileProviderOrNull(toolKey);
    return provider != null &&
        isAvailable &&
        (hasAuthFile || !provider.supportsDeviceAuth);
  }
}
