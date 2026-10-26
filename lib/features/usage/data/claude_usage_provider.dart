import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/providers/claude/claude_usage_client.dart';

final class ClaudeUsageProvider implements UsageProvider {
  const ClaudeUsageProvider(this.client);

  final ClaudeUsageClient client;

  @override
  Future<UsageSnapshot> refresh(Profile profile) => client.refresh(profile);
}
