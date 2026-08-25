import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/data/usage_mapper.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';

typedef CodexHeartbeatClientFactory =
    CodexAppServerClient Function(Duration timeout);

final class CodexHeartbeatQuotaProbe implements HeartbeatQuotaProbe {
  CodexHeartbeatQuotaProbe({CodexHeartbeatClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _createClient;

  static const timeout = Duration(seconds: 30);

  final CodexHeartbeatClientFactory _clientFactory;

  @override
  Future<UsageSnapshot> probe(Profile profile) async =>
      UsageMapper.fromCodex(await _clientFactory(timeout).refresh(profile));

  static CodexAppServerClient _createClient(Duration timeout) =>
      CodexAppServerClient(timeout: timeout);
}
