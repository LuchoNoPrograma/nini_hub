import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/features/accounts/data/account_mapper.dart';
import 'package:multi_cli_ai/features/accounts/data/drift_account_repository.dart';
import 'package:multi_cli_ai/features/accounts/domain/account.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_models.dart';
import 'package:multi_cli_ai/features/profiles/data/profile_mapper.dart';
import 'package:multi_cli_ai/features/usage/application/usage_refresh.dart';
import 'package:multi_cli_ai/features/usage/data/codex_usage_provider.dart';
import 'package:multi_cli_ai/features/usage/data/drift_usage_snapshot_repository.dart';
import 'package:multi_cli_ai/features/usage/data/process_usage_activity_recorder.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_client.dart';

void main() {
  test('a partial refresh keeps the last successful quota visible', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final profile = _profile();
    final earlier = DateTime.utc(2026, 8, 20, 14, 55);
    final latest = earlier.add(const Duration(minutes: 18));
    await database.into(database.cliProfiles).insert(profile);
    await database
        .into(database.usageChecks)
        .insert(
          UsageCheck(
            id: 'successful-check',
            profileId: profile.id,
            queryMethod: 'test',
            status: 'success',
            startedAt: earlier,
          ),
        );
    await database
        .into(database.quotaWindows)
        .insert(
          QuotaWindow(
            id: 'weekly-window',
            checkId: 'successful-check',
            limitId: 'codex',
            windowType: 'secondary',
            usedPercent: 12,
            windowDurationMinutes: 10080,
            resetsAt: earlier.add(const Duration(days: 6)),
          ),
        );
    await database
        .into(database.usageChecks)
        .insert(
          UsageCheck(
            id: 'partial-check',
            profileId: profile.id,
            queryMethod: 'test',
            status: 'partial',
            startedAt: latest,
            errorCode: 'PARTIAL_METADATA',
            errorMessage: 'error sending request',
          ),
        );

    final account = (await DriftAccountRepository(database).loadAll()).single;

    expect(
      account.currentCheck?.startedAt.millisecondsSinceEpoch,
      latest.millisecondsSinceEpoch,
    );
    expect(account.currentWindows, isEmpty);
    expect(
      account.lastSuccessfulCheck?.startedAt.millisecondsSinceEpoch,
      earlier.millisecondsSinceEpoch,
    );
    expect(account.visibleWindows.single.windowType, 'secondary');
    expect(account.visibleWindows.single.usedPercent, 12);
    expect(account.currentIssue, AccountUsageIssue.network);
  });

  test('stored provider errors expose a descriptive account issue', () {
    expect(
      _accountWithError(
        code: 'PARTIAL_METADATA',
        message: 'code: token_expired',
      ).currentIssue,
      AccountUsageIssue.credentialExpired,
    );
    expect(
      _accountWithError(
        code: 'PARTIAL_METADATA',
        message: 'code: token_invalidated',
      ).currentIssue,
      AccountUsageIssue.credentialInvalidated,
    );
    expect(
      _accountWithError(code: 'NETWORK_ERROR').currentIssue,
      AccountUsageIssue.network,
    );
    expect(
      _accountWithError(code: 'PARTIAL_METADATA').currentIssue,
      AccountUsageIssue.partialMetadata,
    );
  });

  test('partial metadata is recorded as an activity error', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final profile = _profile();
    await database.into(database.cliProfiles).insert(profile);
    final now = DateTime.utc(2026, 8, 20, 15, 13);
    final refresh = RefreshProfileUsage(
      provider: CodexUsageProvider(
        _StaticClient(
          CodexRefreshResult(
            state: UsageCheckState.partial,
            startedAt: now,
            completedAt: now,
            errorCode: 'PARTIAL_METADATA',
            errorMessage: 'error sending request',
          ),
        ),
      ),
      repository: DriftUsageSnapshotRepository(database),
      activity: ProcessUsageActivityRecorder(ProcessRunner(database)),
    );

    await refresh(ProfileMapper.fromRow(profile));

    final log = await database.select(database.commandLogs).getSingle();
    expect(log.status, 'error');
    expect(log.output, contains('error sending request'));
  });
}

class _StaticClient extends CodexAppServerClient {
  const _StaticClient(this.result);

  final CodexRefreshResult result;

  @override
  Future<CodexRefreshResult> refresh(String profileHome) async => result;
}

CliProfile _profile() {
  final now = DateTime.utc(2026, 8, 20);
  return CliProfile(
    id: 'profile',
    toolKey: 'codex',
    profileName: 'profile',
    commandName: 'codex-profile',
    displayName: 'Profile',
    profileHome: '/tmp/profile',
    profileSource: 'multicli',
    profileType: 'full',
    hasAuthFile: true,
    isAvailable: true,
    isFavorite: false,
    createdAt: now,
    lastDiscoveredAt: now,
  );
}

Account _accountWithError({String? code, String? message}) {
  final profile = _profile();
  final check = UsageCheck(
    id: 'error-check',
    profileId: profile.id,
    queryMethod: 'test',
    status: 'partial',
    startedAt: DateTime.utc(2026, 8, 20),
    errorCode: code,
    errorMessage: message,
  );
  return AccountMapper.fromRows(
    profile: profile,
    metadata: null,
    costShares: const [],
    currentCheck: check,
    currentWindows: const [],
    lastSuccessfulCheck: null,
    lastSuccessfulWindows: const [],
    resetCredits: null,
  );
}
