import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_ports.dart';
import 'package:multi_cli_ai/features/usage/application/usage_refresh.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_failure.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_ports.dart';

void main() {
  group('single profile refresh', () {
    test(
      'discovers and executes provider, persistence, activity, keep alive',
      () async {
        final snapshot = _snapshot(status: UsageRefreshStatus.partial);
        final fixture = _Fixture(profiles: [_profile()], snapshot: snapshot);

        final result = await fixture.refresh('primary');

        expect(result, same(snapshot));
        expect(fixture.events, [
          'discover',
          'provider:primary',
          'persist:primary',
          'activity:primary',
          'keep-alive:primary',
        ]);
        expect(fixture.repository.saved.single.snapshot, same(snapshot));
        expect(fixture.activity.recorded.single.snapshot, same(snapshot));
        expect(fixture.keepAlive.scheduled.single.snapshot, same(snapshot));
      },
    );

    test('missing profile fails before any refresh effect', () async {
      final fixture = _Fixture(profiles: const []);

      await expectLater(
        fixture.refresh('missing'),
        throwsA(
          isA<UsageProfileNotFoundFailure>().having(
            (failure) => failure.profileId,
            'profileId',
            'missing',
          ),
        ),
      );
      expect(fixture.events, ['discover']);
    });

    test('unavailable profile reports whether it is deactivated', () async {
      final unavailable = _Fixture(profiles: [_profile(isAvailable: false)]);
      final deactivated = _Fixture(
        profiles: [_profile(isAvailable: false, kind: ProfileKind.deactivated)],
      );

      await expectLater(
        unavailable.refresh('primary'),
        throwsA(
          isA<UsageProfileUnavailableFailure>().having(
            (failure) => failure.reason,
            'reason',
            UsageProfileUnavailableReason.unavailable,
          ),
        ),
      );
      await expectLater(
        deactivated.refresh('primary'),
        throwsA(
          isA<UsageProfileUnavailableFailure>().having(
            (failure) => failure.reason,
            'reason',
            UsageProfileUnavailableReason.deactivated,
          ),
        ),
      );
      expect(unavailable.events, ['discover']);
      expect(deactivated.events, ['discover']);
    });

    test('unsupported provider is a typed precondition failure', () async {
      final fixture = _Fixture(profiles: [_profile(toolKey: 'claude-cli')]);

      await expectLater(
        fixture.refresh('primary'),
        throwsA(
          isA<UsageUnsupportedProviderFailure>()
              .having((failure) => failure.profileId, 'profileId', 'primary')
              .having((failure) => failure.toolKey, 'toolKey', 'claude-cli'),
        ),
      );
      expect(fixture.events, ['discover']);
    });

    test('provider and atomic persistence failures remain unapplied', () async {
      final providerCause = StateError('provider failed');
      final providerFixture = _Fixture(
        profiles: [_profile()],
        providerError: providerCause,
      );
      final persistenceCause = StateError('persistence failed');
      final persistenceFixture = _Fixture(
        profiles: [_profile()],
        repositoryError: persistenceCause,
      );

      await expectLater(
        providerFixture.refresh('primary'),
        throwsA(same(providerCause)),
      );
      await expectLater(
        persistenceFixture.refresh('primary'),
        throwsA(same(persistenceCause)),
      );
      expect(providerFixture.events, ['discover', 'provider:primary']);
      expect(persistenceFixture.events, [
        'discover',
        'provider:primary',
        'persist:primary',
      ]);
    });

    test('activity failure reports that the snapshot was persisted', () async {
      final cause = StateError('activity failed');
      final fixture = _Fixture(profiles: [_profile()], activityError: cause);

      await expectLater(
        fixture.refresh('primary'),
        throwsA(
          isA<UsageRefreshAppliedFailure>()
              .having(
                (failure) => failure.progress,
                'progress',
                UsageRefreshProgress.snapshotPersisted,
              )
              .having((failure) => failure.cause, 'cause', same(cause)),
        ),
      );
      expect(fixture.events, [
        'discover',
        'provider:primary',
        'persist:primary',
        'activity:primary',
      ]);
    });

    test('keep alive failure reports that activity was recorded', () async {
      final cause = StateError('keep alive failed');
      final fixture = _Fixture(profiles: [_profile()], keepAliveError: cause);

      await expectLater(
        fixture.refresh('primary'),
        throwsA(
          isA<UsageRefreshAppliedFailure>()
              .having(
                (failure) => failure.progress,
                'progress',
                UsageRefreshProgress.activityRecorded,
              )
              .having((failure) => failure.cause, 'cause', same(cause)),
        ),
      );
      expect(fixture.events, [
        'discover',
        'provider:primary',
        'persist:primary',
        'activity:primary',
        'keep-alive:primary',
      ]);
    });
  });

  group('batch refresh', () {
    test(
      'filters ineligible profiles and clamps maximum concurrency to six',
      () async {
        final profiles = [
          for (var index = 0; index < 8; index++)
            _profile(id: 'profile-$index'),
          _profile(id: 'unavailable', isAvailable: false),
          _profile(id: 'unsupported', toolKey: 'claude-cli'),
        ];
        final provider = _GatedProvider(_snapshot());
        final fixture = _Fixture(profiles: profiles, provider: provider);
        final progress = <String>[];

        final future = fixture.refreshAll(
          concurrency: 99,
          onProgress: (profileId, _) => progress.add(profileId),
        );
        await provider.sixStarted.future.timeout(const Duration(seconds: 2));
        expect(provider.started, 6);
        expect(provider.maxActive, 6);
        provider.release.complete();
        final result = await future;

        final eligibleIds = {
          for (var index = 0; index < 8; index++) 'profile-$index',
        };
        expect(result.byProfile.keys.toSet(), eligibleIds);
        expect(progress.toSet(), eligibleIds);
        expect(progress, hasLength(8));
        expect(provider.profileIds.toSet(), eligibleIds);
        expect(
          () => result.byProfile['extra'] = _snapshot(),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'serial failure exposes completed results and applied profile cause',
      () async {
        final fixture = _Fixture(
          profiles: [
            _profile(id: 'first'),
            _profile(id: 'failing'),
            _profile(id: 'unreached'),
          ],
          failingActivityProfileId: 'failing',
        );
        final progress = <String>[];

        Object? thrown;
        try {
          await fixture.refreshAll(
            concurrency: 0,
            onProgress: (profileId, _) => progress.add(profileId),
          );
        } catch (error) {
          thrown = error;
        }

        expect(thrown, isA<UsageBatchFailure>());
        final failure = thrown! as UsageBatchFailure;
        expect(failure.failedProfileId, 'failing');
        expect(failure.completedByProfile.keys, ['first']);
        expect(
          failure.cause,
          isA<UsageRefreshAppliedFailure>().having(
            (cause) => cause.progress,
            'progress',
            UsageRefreshProgress.snapshotPersisted,
          ),
        );
        expect((fixture.provider as _FakeProvider).profileIds, [
          'first',
          'failing',
        ]);
        expect(fixture.repository.saved.map((item) => item.profileId), [
          'first',
          'failing',
        ]);
        expect(progress, ['first']);
        expect(
          () => failure.completedByProfile['extra'] = _snapshot(),
          throwsUnsupportedError,
        );
      },
    );

    test('empty eligible set returns without provider effects', () async {
      final fixture = _Fixture(
        profiles: [
          _profile(id: 'unavailable', isAvailable: false),
          _profile(id: 'unsupported', toolKey: 'claude-cli'),
        ],
      );

      final result = await fixture.refreshAll();

      expect(result.byProfile, isEmpty);
      expect(fixture.events, ['discover']);
    });
  });
}

final class _Fixture {
  _Fixture({
    required List<Profile> profiles,
    UsageSnapshot? snapshot,
    UsageProvider? provider,
    Object? providerError,
    Object? repositoryError,
    Object? activityError,
    Object? keepAliveError,
    String? failingActivityProfileId,
  }) {
    discovery = _FakeDiscovery(events, profiles);
    this.provider =
        provider ??
        _FakeProvider(events, snapshot ?? _snapshot(), error: providerError);
    repository = _FakeSnapshotRepository(events, error: repositoryError);
    activity = _FakeActivityRecorder(
      events,
      error: activityError,
      failingProfileId: failingActivityProfileId,
    );
    keepAlive = _FakeKeepAliveScheduler(events, error: keepAliveError);
    refreshProfile = RefreshProfileUsage(
      provider: this.provider,
      repository: repository,
      activity: activity,
      keepAlive: keepAlive,
    );
    refresh = RefreshUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    );
    refreshAll = RefreshAllUsage(
      discovery: discovery,
      refreshProfile: refreshProfile,
    );
  }

  final List<String> events = [];
  late final _FakeDiscovery discovery;
  late final UsageProvider provider;
  late final _FakeSnapshotRepository repository;
  late final _FakeActivityRecorder activity;
  late final _FakeKeepAliveScheduler keepAlive;
  late final RefreshProfileUsage refreshProfile;
  late final RefreshUsage refresh;
  late final RefreshAllUsage refreshAll;
}

final class _FakeDiscovery implements ProfileDiscovery {
  _FakeDiscovery(this.events, this.profiles);

  final List<String> events;
  final List<Profile> profiles;

  @override
  Future<List<Profile>> discover() async {
    events.add('discover');
    return List.of(profiles);
  }
}

class _FakeProvider implements UsageProvider {
  _FakeProvider(this.events, this.snapshot, {this.error});

  final List<String> events;
  final UsageSnapshot snapshot;
  final Object? error;
  final List<String> profileIds = [];

  @override
  Future<UsageSnapshot> refresh(Profile profile) async {
    events.add('provider:${profile.id}');
    profileIds.add(profile.id);
    final failure = error;
    if (failure != null) throw failure;
    return snapshot;
  }
}

final class _GatedProvider extends _FakeProvider {
  _GatedProvider(UsageSnapshot snapshot) : super(<String>[], snapshot);

  final Completer<void> sixStarted = Completer<void>();
  final Completer<void> release = Completer<void>();
  int active = 0;
  int maxActive = 0;
  int started = 0;

  @override
  Future<UsageSnapshot> refresh(Profile profile) async {
    profileIds.add(profile.id);
    active++;
    started++;
    if (active > maxActive) maxActive = active;
    if (started == 6 && !sixStarted.isCompleted) sixStarted.complete();
    try {
      await release.future;
      return snapshot;
    } finally {
      active--;
    }
  }
}

final class _SavedSnapshot {
  const _SavedSnapshot(this.profileId, this.snapshot);

  final String profileId;
  final UsageSnapshot snapshot;
}

final class _FakeSnapshotRepository implements UsageSnapshotRepository {
  _FakeSnapshotRepository(this.events, {this.error});

  final List<String> events;
  final Object? error;
  final List<_SavedSnapshot> saved = [];

  @override
  Future<void> saveSnapshot({
    required String profileId,
    required UsageSnapshot snapshot,
  }) async {
    events.add('persist:$profileId');
    final failure = error;
    if (failure != null) throw failure;
    saved.add(_SavedSnapshot(profileId, snapshot));
  }
}

final class _RecordedActivity {
  const _RecordedActivity(this.profile, this.snapshot);

  final Profile profile;
  final UsageSnapshot snapshot;
}

final class _FakeActivityRecorder implements UsageActivityRecorder {
  _FakeActivityRecorder(this.events, {this.error, this.failingProfileId});

  final List<String> events;
  final Object? error;
  final String? failingProfileId;
  final List<_RecordedActivity> recorded = [];

  @override
  Future<void> recordRefresh({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) async {
    events.add('activity:${profile.id}');
    final failure = error;
    if (failure != null) throw failure;
    if (profile.id == failingProfileId) {
      throw StateError('activity failed for ${profile.id}');
    }
    recorded.add(_RecordedActivity(profile, snapshot));
  }
}

final class _ScheduledKeepAlive {
  const _ScheduledKeepAlive(this.profile, this.snapshot);

  final Profile profile;
  final UsageSnapshot snapshot;
}

final class _FakeKeepAliveScheduler implements UsageKeepAliveScheduler {
  _FakeKeepAliveScheduler(this.events, {this.error});

  final List<String> events;
  final Object? error;
  final List<_ScheduledKeepAlive> scheduled = [];

  @override
  bool scheduleIfEligible({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) {
    events.add('keep-alive:${profile.id}');
    final failure = error;
    if (failure != null) throw failure;
    scheduled.add(_ScheduledKeepAlive(profile, snapshot));
    return true;
  }
}

UsageSnapshot _snapshot({
  UsageRefreshStatus status = UsageRefreshStatus.success,
}) {
  final now = DateTime.utc(2026, 8, 22, 12);
  return UsageSnapshot(status: status, startedAt: now, completedAt: now);
}

Profile _profile({
  String id = 'primary',
  String toolKey = 'codex',
  bool isAvailable = true,
  ProfileKind kind = ProfileKind.full,
}) => Profile(
  id: id,
  toolKey: toolKey,
  profileName: id,
  commandName: '$toolKey-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  source: ProfileSource.multiCli,
  kind: kind,
  hasAuthFile: true,
  isAvailable: isAvailable,
  isFavorite: false,
);
