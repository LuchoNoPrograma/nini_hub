import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/usage/data/usage_mapper.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_ports.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_client.dart';

final class CodexUsageProvider implements UsageProvider {
  CodexUsageProvider(CodexAppServerClient client) : _client = (() => client);

  CodexUsageProvider.current(this._client);

  final CodexAppServerClient Function() _client;

  @override
  Future<UsageSnapshot> refresh(Profile profile) async =>
      UsageMapper.fromCodex(await _client().refresh(profile.profileHome));
}
