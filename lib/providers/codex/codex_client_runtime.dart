import 'package:multi_cli_ai/providers/codex/codex_app_server_client.dart';

typedef CodexClientFactory =
    CodexAppServerClient Function(Duration requestTimeout);

final class CodexClientRuntime {
  CodexClientRuntime({
    CodexAppServerClient? initialClient,
    CodexClientFactory? clientFactory,
  }) : _current = initialClient ?? const CodexAppServerClient(),
       _clientFactory = clientFactory ?? _defaultClientFactory;

  CodexAppServerClient _current;
  final CodexClientFactory _clientFactory;

  CodexAppServerClient get current => _current;

  void setRequestTimeoutSeconds(int seconds) {
    _current = _clientFactory(Duration(seconds: seconds));
  }

  static CodexAppServerClient _defaultClientFactory(Duration requestTimeout) =>
      CodexAppServerClient(timeout: requestTimeout);
}
