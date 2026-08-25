import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/data/codex_usage_provider.dart';
import 'package:nini_hub/features/usage/data/process_usage_activity_recorder.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';

void main() {
  test(
    'Codex provider delegates the profile home and maps the result',
    () async {
      final result = CodexRefreshResult(
        state: UsageCheckState.partial,
        startedAt: DateTime.utc(2026, 8, 22, 10),
        completedAt: DateTime.utc(2026, 8, 22, 10, 0, 1),
        accountEmail: 'owner@example.com',
      );
      final client = _RecordingClient(result);
      final provider = CodexUsageProvider(client);

      final snapshot = await provider.refresh(_profile());

      expect(client.profileHomes, ['/profiles/primary']);
      expect(snapshot.status, UsageRefreshStatus.partial);
      expect(snapshot.accountEmail, 'owner@example.com');
    },
  );

  test(
    'Codex provider resolves the current runtime client per refresh',
    () async {
      final first = _RecordingClient(
        CodexRefreshResult(
          state: UsageCheckState.success,
          startedAt: DateTime.utc(2026, 8, 22, 10),
          completedAt: DateTime.utc(2026, 8, 22, 10, 0, 1),
        ),
      );
      final second = _RecordingClient(
        CodexRefreshResult(
          state: UsageCheckState.partial,
          startedAt: DateTime.utc(2026, 8, 22, 11),
          completedAt: DateTime.utc(2026, 8, 22, 11, 0, 1),
        ),
      );
      CodexAppServerClient current = first;
      final provider = CodexUsageProvider.current(() => current);

      expect(
        (await provider.refresh(_profile())).status,
        UsageRefreshStatus.success,
      );
      current = second;
      expect(
        (await provider.refresh(_profile())).status,
        UsageRefreshStatus.partial,
      );

      expect(first.profileHomes, ['/profiles/primary']);
      expect(second.profileHomes, ['/profiles/primary']);
    },
  );

  test(
    'activity recorder preserves legacy fields and runner redaction',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final recorder = ProcessUsageActivityRecorder(ProcessRunner(database));

      await recorder.recordRefresh(
        profile: _profile(),
        snapshot: _snapshot(
          status: UsageRefreshStatus.partial,
          errorMessage: 'provider token sk-abcdefghijk',
        ),
      );
      await recorder.recordRefresh(
        profile: _profile(),
        snapshot: UsageSnapshot(
          status: UsageRefreshStatus.success,
          startedAt: DateTime.utc(2026, 8, 22, 10),
          completedAt: DateTime.utc(2026, 8, 22, 10, 0, 1),
          windows: const [
            UsageQuotaWindow(limitId: 'codex', windowType: 'primary'),
          ],
          dailyUsage: [
            UsageDailySnapshot(
              day: DateTime.utc(2026, 8, 21),
              tokens: 12,
              source: 'provider',
            ),
          ],
        ),
      );

      final logs = await database.select(database.commandLogs).get();
      expect(logs, hasLength(2));
      expect(logs.first.summary, 'Actualizar Primary');
      expect(logs.first.profileId, 'primary');
      expect(logs.first.command, 'codex app-server metadata');
      expect(logs.first.status, 'error');
      expect(logs.first.output, 'provider token [REDACTADO]');
      expect(logs.last.status, 'success');
      expect(logs.last.output, '1 ventanas y 1 días de uso.');
    },
  );
}

final class _RecordingClient extends CodexAppServerClient {
  _RecordingClient(this.result);

  final CodexRefreshResult result;
  final List<String> profileHomes = [];

  @override
  Future<CodexRefreshResult> refresh(Profile profile) async {
    profileHomes.add(profile.profileHome);
    return result;
  }
}

Profile _profile() => const Profile(
  id: 'primary',
  toolKey: 'codex',
  profileName: 'primary',
  commandName: 'codex-primary',
  displayName: 'Primary',
  profileHome: '/profiles/primary',
  source: ProfileSource.multiCli,
  kind: ProfileKind.shared,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);

UsageSnapshot _snapshot({
  required UsageRefreshStatus status,
  String? errorMessage,
}) => UsageSnapshot(
  status: status,
  startedAt: DateTime.utc(2026, 8, 22, 10),
  completedAt: DateTime.utc(2026, 8, 22, 10, 0, 1),
  errorMessage: errorMessage,
);
