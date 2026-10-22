import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/features/usage/domain/usage_failure.dart';

/// Routes each profile to the usage source of its own tool.
final class ToolUsageProvider implements UsageProvider {
  const ToolUsageProvider(this.providers);

  final Map<String, UsageProvider> providers;

  @override
  Future<UsageSnapshot> refresh(Profile profile) {
    final provider = providers[profile.toolKey];
    if (provider == null) {
      throw UsageUnsupportedProviderFailure(
        profileId: profile.id,
        toolKey: profile.toolKey,
      );
    }
    return provider.refresh(profile);
  }
}
