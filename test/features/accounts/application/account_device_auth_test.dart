import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/application/account_device_auth.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/domain/account_failure.dart';
import 'package:nini_hub/features/accounts/domain/account_repository.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

void main() {
  test('start records Activity before opening the provider session', () async {
    final events = <String>[];
    final session = _FakeSession();
    final useCase = StartAccountDeviceAuth(
      gateway: _FakeGateway(events, session),
      activity: _FakeActivity(events),
    );

    expect(await useCase(_account()), same(session));
    expect(events, ['activity.started', 'gateway.start:account']);
  });

  test('start exposes that Activity was applied before provider failure', () {
    final cause = StateError('provider failed');
    final useCase = StartAccountDeviceAuth(
      gateway: _FakeGateway(<String>[], _FakeSession(), failure: cause),
      activity: _FakeActivity(<String>[]),
    );

    expectLater(
      useCase(_account()),
      throwsA(
        isA<AccountDeviceAuthAppliedFailure>()
            .having(
              (failure) => failure.progress,
              'progress',
              AccountDeviceAuthProgress.startRecorded,
            )
            .having((failure) => failure.cause, 'cause', same(cause)),
      ),
    );
  });

  test(
    'successful completion preserves discovery, monitor, usage, sync and account order',
    () async {
      final events = <String>[];
      final repository = _FakeAccountRepository(events, [_account()]);
      final useCase = CompleteAccountDeviceAuth(
        activity: _FakeActivity(events),
        authenticationStore: _FakeAuthenticationStore(events),
        discovery: _FakeDiscovery(events, [
          _profile('account'),
          _profile('missing-auth', hasAuthFile: false),
          _profile('other', toolKey: 'claude-cli'),
        ]),
        accountRepository: repository,
        monitorHeartbeatProfiles: (profiles) => events.add(
          'heartbeat.monitor:${profiles.map((profile) => profile.id).join(',')}',
        ),
        refreshUsage: (profile) async {
          events.add('usage.refresh:${profile.id}');
        },
        synchronizeUsageProjections: () async {
          events.add('usage.synchronize');
        },
      );

      final snapshot = await useCase(_account(), success: true);

      expect(snapshot?.accounts.single.profile.id, 'account');
      expect(events, [
        'activity.completed:true',
        'authentication.persist:account',
        'profiles.discover',
        'heartbeat.monitor:account',
        'usage.refresh:account',
        'usage.synchronize',
        'accounts.load',
      ]);
    },
  );

  test(
    'rejected completion rediscovers and monitors without refreshing',
    () async {
      final events = <String>[];
      final useCase = CompleteAccountDeviceAuth(
        activity: _FakeActivity(events),
        authenticationStore: _FakeAuthenticationStore(events),
        discovery: _FakeDiscovery(events, [_profile('account')]),
        accountRepository: _FakeAccountRepository(events, [_account()]),
        monitorHeartbeatProfiles: (_) => events.add('heartbeat.monitor'),
        refreshUsage: (_) async => events.add('usage.refresh'),
        synchronizeUsageProjections: () async =>
            events.add('usage.synchronize'),
      );

      expect(await useCase(_account(), success: false), isNull);
      expect(events, [
        'activity.completed:false',
        'profiles.discover',
        'heartbeat.monitor',
      ]);
    },
  );

  test(
    'confirmed completion reports persistence failure before discovery',
    () async {
      final events = <String>[];
      final cause = StateError('profile disappeared');
      final useCase = CompleteAccountDeviceAuth(
        activity: _FakeActivity(events),
        authenticationStore: _FakeAuthenticationStore(events, failure: cause),
        discovery: _FakeDiscovery(events, [_profile('account')]),
        accountRepository: _FakeAccountRepository(events, [_account()]),
        monitorHeartbeatProfiles: (_) => events.add('heartbeat.monitor'),
        refreshUsage: (_) async => events.add('usage.refresh'),
        synchronizeUsageProjections: () async =>
            events.add('usage.synchronize'),
      );

      await expectLater(
        useCase(_account(), success: true),
        throwsA(
          isA<AccountDeviceAuthAppliedFailure>()
              .having(
                (failure) => failure.progress,
                'progress',
                AccountDeviceAuthProgress.completionRecorded,
              )
              .having((failure) => failure.cause, 'cause', same(cause)),
        ),
      );
      expect(events, [
        'activity.completed:true',
        'authentication.persist:account',
      ]);
    },
  );

  test(
    'completion exposes persisted authentication before discovery failure',
    () async {
      final events = <String>[];
      final cause = StateError('discovery failed');
      final useCase = CompleteAccountDeviceAuth(
        activity: _FakeActivity(events),
        authenticationStore: _FakeAuthenticationStore(events),
        discovery: _FakeDiscovery(events, const [], failure: cause),
        accountRepository: _FakeAccountRepository(events, [_account()]),
        monitorHeartbeatProfiles: (_) {},
        refreshUsage: (_) async {},
        synchronizeUsageProjections: () async {},
      );

      await expectLater(
        useCase(_account(), success: true),
        throwsA(
          isA<AccountDeviceAuthAppliedFailure>()
              .having(
                (failure) => failure.progress,
                'progress',
                AccountDeviceAuthProgress.authenticationPersisted,
              )
              .having((failure) => failure.cause, 'cause', same(cause)),
        ),
      );
      expect(events, [
        'activity.completed:true',
        'authentication.persist:account',
        'profiles.discover',
      ]);
    },
  );

  test('completion reports the last definitely applied progress', () async {
    final events = <String>[];
    final cause = StateError('usage failed');
    final useCase = CompleteAccountDeviceAuth(
      activity: _FakeActivity(events),
      authenticationStore: _FakeAuthenticationStore(events),
      discovery: _FakeDiscovery(events, [_profile('account')]),
      accountRepository: _FakeAccountRepository(events, [_account()]),
      monitorHeartbeatProfiles: (_) {},
      refreshUsage: (_) => Future<void>.error(cause),
      synchronizeUsageProjections: () async {},
    );

    await expectLater(
      useCase(_account(), success: true),
      throwsA(
        isA<AccountDeviceAuthAppliedFailure>()
            .having(
              (failure) => failure.progress,
              'progress',
              AccountDeviceAuthProgress.profilesSynchronized,
            )
            .having((failure) => failure.cause, 'cause', same(cause)),
      ),
    );
  });
}

final class _FakeGateway implements AccountDeviceAuthGateway {
  const _FakeGateway(this.events, this.session, {this.failure});

  final List<String> events;
  final AccountDeviceAuthSession session;
  final Object? failure;

  @override
  Future<AccountDeviceAuthSession> start(Profile profile) async {
    events.add('gateway.start:${profile.id}');
    final failure = this.failure;
    if (failure != null) throw failure;
    return session;
  }
}

final class _FakeSession implements AccountDeviceAuthSession {
  @override
  String get userCode => 'ABCD-EFGH';

  @override
  String get verificationUrl => 'https://example.com/device';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> waitForCompletion() async => true;
}

final class _FakeActivity implements AccountDeviceAuthActivityRecorder {
  const _FakeActivity(this.events);

  final List<String> events;

  @override
  Future<void> recordStarted(Profile profile) async {
    events.add('activity.started');
  }

  @override
  Future<void> recordCompleted(Profile profile, {required bool success}) async {
    events.add('activity.completed:$success');
  }
}

final class _FakeAuthenticationStore implements AccountAuthenticationStore {
  const _FakeAuthenticationStore(this.events, {this.failure});

  final List<String> events;
  final Object? failure;

  @override
  Future<void> markAuthenticated(String profileId) async {
    events.add('authentication.persist:$profileId');
    final failure = this.failure;
    if (failure != null) throw failure;
  }
}

final class _FakeDiscovery implements ProfileDiscovery {
  const _FakeDiscovery(this.events, this.profiles, {this.failure});

  final List<String> events;
  final List<Profile> profiles;
  final Object? failure;

  @override
  Future<List<Profile>> discover() async {
    events.add('profiles.discover');
    final failure = this.failure;
    if (failure != null) throw failure;
    return profiles;
  }
}

final class _FakeAccountRepository implements AccountRepository {
  const _FakeAccountRepository(this.events, this.accounts);

  final List<String> events;
  final List<Account> accounts;

  @override
  Future<Account?> findById(String profileId) async => null;

  @override
  Future<List<Account>> loadAll() async {
    events.add('accounts.load');
    return accounts;
  }

  @override
  Future<void> saveDetails(AccountDetails details) async {}
}

Account _account() => Account(
  profile: _profile('account'),
  metadata: null,
  costShares: const [],
  currentCheck: null,
  currentWindows: const [],
  lastSuccessfulCheck: null,
  lastSuccessfulWindows: const [],
  resetCredits: null,
);

Profile _profile(
  String id, {
  String toolKey = 'codex',
  bool hasAuthFile = true,
}) => Profile(
  id: id,
  toolKey: toolKey,
  profileName: id,
  commandName: '$toolKey-$id',
  displayName: id,
  profileHome: '/profiles/$id',
  source: ProfileSource.multiCli,
  kind: ProfileKind.full,
  hasAuthFile: hasAuthFile,
  isAvailable: true,
  isFavorite: false,
);
