import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';
import 'package:nini_hub/providers/codex/codex_client_runtime.dart';

void main() {
  test('replaces the current client with the configured timeout', () {
    final createdTimeouts = <Duration>[];
    final runtime = CodexClientRuntime(
      initialClient: const CodexAppServerClient(timeout: Duration(seconds: 12)),
      clientFactory: (timeout) {
        createdTimeouts.add(timeout);
        return CodexAppServerClient(timeout: timeout);
      },
    );

    expect(runtime.current.timeout, const Duration(seconds: 12));

    runtime.setRequestTimeoutSeconds(45);

    expect(createdTimeouts, [const Duration(seconds: 45)]);
    expect(runtime.current.timeout, const Duration(seconds: 45));
  });
}
