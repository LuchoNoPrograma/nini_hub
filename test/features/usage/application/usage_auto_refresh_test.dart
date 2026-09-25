import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/usage/application/usage_account_projection.dart';
import 'package:nini_hub/features/usage/application/usage_auto_refresh.dart';
import 'package:nini_hub/features/usage/data/serial_usage_operation_gate.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

void main() {
  test('empty quota response cannot silently confirm an expired window', () {
    final f = _Fixture();
    f.now = f.reset.add(const Duration(minutes: 1));
    f.service.observe(
      'a',
      UsageSnapshot(
        status: UsageRefreshStatus.partial,
        startedAt: f.now,
        completedAt: f.now,
        rateLimitsReadSucceeded: true,
      ),
    );
    expect(f.service.nextAt, f.now.add(const Duration(minutes: 5)));
    expect(f.service.recentSnapshot('a'), isNull);
  });

  test('missing quota windows retry before the known reset', () {
    final f = _Fixture();
    f.now = f.reset.subtract(const Duration(hours: 1));
    f.service.observe(
      'a',
      UsageSnapshot(
        status: UsageRefreshStatus.partial,
        startedAt: f.now,
        completedAt: f.now,
        rateLimitsReadSucceeded: true,
      ),
    );
    expect(f.service.nextAt, f.now.add(const Duration(minutes: 5)));
  });

  test(
    'one read at reset + 1 minute updates all windows and publishes once',
    () async {
      final f = _Fixture();
      await f.service.refreshDue();
      expect(f.reads, 0);
      f.now = f.reset.add(const Duration(minutes: 1));
      await f.service.refreshDue();
      expect(f.reads, 1);
      expect(f.published, 1);
      expect(f.synchronizations, 1);
      expect(f.repository.lookups, 1);
      await f.service.refreshDue();
      expect(f.reads, 1);
    },
  );

  test(
    'late startup or wall-clock jump catches up once, without replaying hours',
    () async {
      final f = _Fixture();
      f.now = f.reset.add(const Duration(days: 2));
      await f.service.refreshDue();
      await f.service.refreshDue();
      expect(f.reads, 1);
    },
  );

  test(
    'waits for heartbeat/manual operation and rechecks its fresh evidence',
    () async {
      final f = _Fixture();
      f.now = f.reset.add(const Duration(minutes: 1));
      final release = Completer<void>();
      final heartbeat = f.gate.run('a', () async {
        await release.future;
        f.service.observe('a', f.result());
      });
      final automatic = f.service.refreshDue();
      await Future<void>.delayed(Duration.zero);
      expect(f.reads, 0);
      release.complete();
      await Future.wait([heartbeat, automatic]);
      expect(f.reads, 0);
    },
  );

  test(
    'fresh but expired data stays pending with 5/15/60 minute retry',
    () async {
      final f = _Fixture();
      f.keepExpired = true;
      f.now = f.reset.add(const Duration(minutes: 1));
      for (final minutes in [5, 15, 60, 60]) {
        await f.service.refreshDue();
        expect(f.service.nextAt, f.now.add(Duration(minutes: minutes)));
        f.now = f.service.nextAt!;
      }
      expect(f.reads, 4);
    },
  );

  test(
    'timeout retains expired targets and auth failure stops until a new read',
    () async {
      final f = _Fixture();
      f.now = f.reset.add(const Duration(minutes: 1));
      f.status = UsageRefreshStatus.timeout;
      await f.service.refreshDue();
      expect(f.service.nextAt, f.now.add(const Duration(seconds: 30)));
      f.now = f.service.nextAt!;
      f.status = UsageRefreshStatus.authRequired;
      await f.service.refreshDue();
      expect(f.service.nextAt, isNull);
      f.now = f.now.add(const Duration(hours: 1));
      await f.service.refreshDue();
      expect(f.reads, 2);
      f.status = UsageRefreshStatus.success;
      f.service.observe('a', f.result());
      expect(f.service.nextAt, isNotNull);
    },
  );

  test('network failure before reset retries without losing the reset', () {
    final f = _Fixture();
    f.now = f.reset.subtract(const Duration(hours: 1));
    f.service.observe(
      'a',
      UsageSnapshot(
        status: UsageRefreshStatus.timeout,
        startedAt: f.now,
        completedAt: f.now,
      ),
    );
    expect(f.service.nextAt, f.now.add(const Duration(seconds: 30)));
    f.now = f.service.nextAt!;
    f.service.observe(
      'a',
      UsageSnapshot(
        status: UsageRefreshStatus.error,
        startedAt: f.now,
        completedAt: f.now,
        errorCode: 'NETWORK_ERROR',
      ),
    );
    expect(f.service.nextAt, f.now.add(const Duration(minutes: 2)));
    f.now = f.service.nextAt!;
    f.service.observe('a', f.result());
    expect(f.service.nextAt, f.now.add(const Duration(hours: 5, minutes: 1)));
  });

  test('a failed first read retries even without known quota windows', () {
    final f = _Fixture(seed: false);
    f.service.replaceAccounts([
      _account(
        UsageSnapshot(
          status: UsageRefreshStatus.timeout,
          startedAt: f.now,
          completedAt: f.now,
        ),
      ),
    ]);
    expect(f.service.nextAt, f.now.add(const Duration(seconds: 30)));
  });

  test('stored workspace routing failure gets a short recovery retry', () {
    final f = _Fixture(seed: false);
    f.service.replaceAccounts([
      _account(
        UsageSnapshot(
          status: UsageRefreshStatus.error,
          startedAt: f.now,
          completedAt: f.now,
          errorCode: 'CODEX_RPC_ERROR',
          errorMessage: 'workspace routing discovery failed',
        ),
      ),
    ]);
    expect(f.service.nextAt, f.now.add(const Duration(seconds: 30)));
  });

  test(
    'weekly exhaustion waits for weekly reset even after several short resets',
    () async {
      final f = _Fixture();
      final weeklyReset = f.reset.add(const Duration(days: 2));
      f.service.replaceAccounts([
        _account(
          _snapshot(
            f.reset.subtract(const Duration(hours: 1)),
            f.reset,
            weeklyUsed: 100,
            weeklyReset: weeklyReset,
          ),
        ),
      ]);
      f.now = f.reset.add(const Duration(days: 1));
      await f.service.refreshDue();
      expect(f.reads, 0);
      expect(f.service.nextAt, weeklyReset.add(const Duration(minutes: 1)));
      f.now = weeklyReset.add(const Duration(minutes: 1));
      await f.service.refreshDue();
      expect(f.reads, 1);
    },
  );

  test('unknown weekly reset uses hourly reads', () async {
    final f = _Fixture(seed: false);
    f.service.replaceAccounts([
      _account(
        _snapshot(f.now, f.reset, weeklyUsed: 100, unknownWeeklyReset: true),
      ),
    ]);
    expect(f.service.nextAt, f.now.add(const Duration(hours: 1)));
  });

  test(
    'partial daily metadata failure can still resolve quota; missing quota cannot',
    () async {
      final f = _Fixture();
      f.now = f.reset.add(const Duration(minutes: 1));
      f.service.observe(
        'a',
        UsageSnapshot(
          status: UsageRefreshStatus.partial,
          startedAt: f.now,
          completedAt: f.now,
        ),
      );
      expect(f.service.nextAt, f.now.add(const Duration(minutes: 5)));
      f.now = f.now.add(const Duration(seconds: 1));
      f.service.observe(
        'a',
        UsageSnapshot(
          status: UsageRefreshStatus.partial,
          startedAt: f.now,
          completedAt: f.now,
          rateLimitsReadSucceeded: true,
          windows: f.result().windows,
        ),
      );
      expect(f.service.nextAt, f.now.add(const Duration(hours: 5, minutes: 1)));
    },
  );

  test(
    'busy account and removed profile cannot run or persist delayed work',
    () async {
      final f = _Fixture();
      f.now = f.reset.add(const Duration(minutes: 1));
      f.blocked = true;
      await f.service.refreshDue();
      expect(f.reads, 0);
      expect(await f.service.canPersist(_profile), isFalse);
      f.blocked = false;
      f.repository.profile = null;
      expect(await f.service.canPersist(_profile), isFalse);
      await f.service.refreshDue();
      expect(f.reads, 0);
      f.service.replaceAccounts([]);
      expect(f.service.nextAt, isNull);
    },
  );

  test(
    'local publication failure retries synchronization without another read',
    () async {
      final f = _Fixture();
      f.now = f.reset.add(const Duration(minutes: 1));
      f.failSynchronization = true;
      await f.service.refreshDue();
      f.failSynchronization = false;
      await f.service.refreshDue();
      expect(f.reads, 1);
      expect(f.synchronizations, 2);
      expect(f.errors, 1);
    },
  );

  test(
    'old storage snapshot cannot replace newer deadline and storage is not a reusable read',
    () {
      final f = _Fixture();
      expect(f.service.recentSnapshot('a'), isNull);
      f.now = f.reset.add(const Duration(minutes: 1));
      final fresh = f.result();
      f.service.observe('a', fresh);
      f.seed();
      expect(f.service.recentSnapshot('a'), same(fresh));
      expect(f.service.nextAt, f.now.add(const Duration(hours: 5, minutes: 1)));
    },
  );

  test('dispose prevents queued reads and late publication', () async {
    final f = _Fixture();
    f.now = f.reset.add(const Duration(minutes: 1));
    final release = Completer<void>();
    final manual = f.gate.run('a', () => release.future);
    final automatic = f.service.refreshDue();
    f.service.dispose();
    release.complete();
    await Future.wait([manual, automatic]);
    expect(f.reads, 0);
    expect(f.service.nextAt, isNull);
  });
}

final class _Fixture {
  _Fixture({bool seed = true}) {
    service = UsageAutoRefresh(
      profiles: repository,
      gate: gate,
      now: () => now,
      isBlocked: () => blocked,
      refresh: (_) async {
        reads++;
        return result();
      },
      publish: (_, _) {
        published++;
      },
      synchronize: () async {
        synchronizations++;
        if (failSynchronization) throw StateError('publish failed');
      },
      onFailure: (_, _) async {
        errors++;
      },
    );
    if (seed) this.seed();
  }
  final reset = DateTime.utc(2026, 9, 10, 12);
  DateTime now = DateTime.utc(2026, 9, 10, 12);
  final repository = _Profiles();
  final gate = SerialUsageOperationGate();
  late final UsageAutoRefresh service;
  bool blocked = false;
  bool keepExpired = false;
  bool failSynchronization = false;
  UsageRefreshStatus status = UsageRefreshStatus.success;
  int reads = 0, published = 0, synchronizations = 0, errors = 0;

  void seed() => service.replaceAccounts([
    _account(_snapshot(reset.subtract(const Duration(hours: 2)), reset)),
  ]);

  UsageSnapshot result() => status == UsageRefreshStatus.success
      ? _snapshot(now, keepExpired ? reset : now.add(const Duration(hours: 5)))
      : UsageSnapshot(status: status, startedAt: now, completedAt: now);
}

const _profile = Profile(
  id: 'a',
  toolKey: 'codex',
  profileName: 'a',
  displayName: 'A',
  profileHome: '/synthetic/a',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);

Account _account(UsageSnapshot snapshot) => const ProjectUsageAccount()(
  Account(
    profile: _profile,
    metadata: null,
    costShares: [],
    currentCheck: null,
    currentWindows: [],
    lastSuccessfulCheck: null,
    lastSuccessfulWindows: [],
    resetCredits: null,
  ),
  snapshot,
);

UsageSnapshot _snapshot(
  DateTime observed,
  DateTime reset, {
  double weeklyUsed = 20,
  DateTime? weeklyReset,
  bool unknownWeeklyReset = false,
}) => UsageSnapshot(
  status: UsageRefreshStatus.success,
  startedAt: observed,
  completedAt: observed,
  rateLimitsReadSucceeded: true,
  windows: [
    UsageQuotaWindow(
      limitId: 'codex',
      windowType: 'primary',
      usedPercent: 20,
      windowDurationMinutes: 300,
      resetsAt: reset,
    ),
    UsageQuotaWindow(
      limitId: 'codex',
      windowType: 'secondary',
      usedPercent: weeklyUsed,
      windowDurationMinutes: 10080,
      resetsAt: unknownWeeklyReset
          ? null
          : weeklyReset ?? reset.add(const Duration(days: 3)),
    ),
  ],
);

final class _Profiles implements ProfileRepository {
  Profile? profile = _profile;
  int lookups = 0;
  @override
  Future<Profile?> findById(String id) async {
    lookups++;
    return profile;
  }

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async => throw UnimplementedError();
}
