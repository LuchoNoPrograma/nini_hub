import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';

void main() {
  test('discover returns an immutable snapshot', () async {
    final events = <String>[];
    final discovery = _MemoryDiscovery(events, [_profile()]);

    final snapshot = await DiscoverProfiles(discovery: discovery)();

    expect(events, ['discovery.discover']);
    expect(snapshot.findById('profile-id'), isNotNull);
    expect(
      () => snapshot.profiles.add(_profile(id: 'other')),
      throwsUnsupportedError,
    );
  });

  test('create validates before starting an external effect', () async {
    final fixture = _Fixture();

    await expectLater(
      fixture.create(
        const CreateProfileCommand(
          toolKey: 'unknown',
          name: '../team',
          displayName: '',
        ),
      ),
      throwsA(isA<InvalidProfileNameFailure>()),
    );
    expect(fixture.events, isEmpty);

    await expectLater(
      fixture.create(
        const CreateProfileCommand(
          toolKey: 'unknown',
          name: 'team',
          displayName: '',
        ),
      ),
      throwsA(isA<UnsupportedProfileToolFailure>()),
    );
    expect(fixture.events, isEmpty);
  });

  test('create preserves lifecycle, discovery, and alias order', () async {
    final fixture = _Fixture(
      discovered: [_profile(displayName: 'Team', isFavorite: true)],
    );

    final result = await fixture.create(
      const CreateProfileCommand(
        toolKey: 'codex',
        name: ' team ',
        displayName: '  Equipo  ',
        setupMode: ProfileSetupMode.shared,
      ),
    );

    expect(fixture.events, [
      'lifecycle.create:codex:team:shared:false',
      'discovery.discover',
      'repository.save:profile-id:Equipo:false',
    ]);
    expect(result.profile.displayName, 'Equipo');
    expect(result.profile.isFavorite, isFalse);
    expect(result.snapshot.findById('profile-id')?.displayName, 'Equipo');
  });

  test('create skips alias persistence when display name is empty', () async {
    final fixture = _Fixture(discovered: [_profile()]);

    final result = await fixture.create(
      const CreateProfileCommand(
        toolKey: 'codex',
        name: 'team',
        displayName: '   ',
        setupMode: ProfileSetupMode.cli,
        seedFromBase: true,
      ),
    );

    expect(fixture.events, [
      'lifecycle.create:codex:team:cli:true',
      'discovery.discover',
    ]);
    expect(result.profile.displayName, 'Team');
  });

  test(
    'create reports a typed partial failure after lifecycle success',
    () async {
      final cause = StateError('discovery failed');
      final fixture = _Fixture(discoveryFailure: cause);

      await expectLater(
        fixture.create(
          const CreateProfileCommand(
            toolKey: 'codex',
            name: 'team',
            displayName: '',
          ),
        ),
        throwsA(
          isA<ProfileMutationAppliedFailure>()
              .having(
                (failure) => failure.operation,
                'operation',
                ProfileOperation.create,
              )
              .having((failure) => failure.cause, 'cause', same(cause)),
        ),
      );
    },
  );

  test(
    'create reports a typed partial failure when discovery misses it',
    () async {
      final fixture = _Fixture(discovered: [_profile(profileName: 'other')]);

      await expectLater(
        fixture.create(
          const CreateProfileCommand(
            toolKey: 'codex',
            name: 'team',
            displayName: '',
          ),
        ),
        throwsA(
          isA<ProfileMutationAppliedFailure>().having(
            (failure) => failure.cause,
            'cause',
            isA<ProfileResultNotFoundFailure>(),
          ),
        ),
      );
    },
  );

  test('create keeps a lifecycle failure as an unapplied failure', () async {
    final cause = StateError('process failed');
    final fixture = _Fixture(createFailure: cause);

    await expectLater(
      fixture.create(
        const CreateProfileCommand(
          toolKey: 'codex',
          name: 'team',
          displayName: '',
        ),
      ),
      throwsA(same(cause)),
    );
    expect(fixture.events, ['lifecycle.create:codex:team:full:false']);
  });

  test('create wraps alias persistence after the external effect', () async {
    final cause = StateError('alias write failed');
    final fixture = _Fixture(discovered: [_profile()], saveFailure: cause);

    await expectLater(
      fixture.create(
        const CreateProfileCommand(
          toolKey: 'codex',
          name: 'team',
          displayName: 'Equipo',
        ),
      ),
      throwsA(
        isA<ProfileMutationAppliedFailure>()
            .having(
              (failure) => failure.operation,
              'operation',
              ProfileOperation.create,
            )
            .having((failure) => failure.cause, 'cause', same(cause)),
      ),
    );
  });

  test('rename validates legacy preconditions before lifecycle', () async {
    final missing = _Fixture(hasStoredProfile: false);
    await expectLater(
      missing.rename(
        const RenameProfileCommand(profileId: 'missing', name: 'new'),
      ),
      throwsA(isA<ProfileNotFoundFailure>()),
    );
    expect(missing.events, ['repository.find:missing']);

    final deactivated = _Fixture(
      stored: _profile(kind: ProfileKind.deactivated),
    );
    await expectLater(
      deactivated.rename(
        const RenameProfileCommand(profileId: 'profile-id', name: 'new'),
      ),
      throwsA(isA<ProfileDeactivatedFailure>()),
    );
    expect(deactivated.events, ['repository.find:profile-id']);

    final mainProfile = _Fixture(
      stored: _profile(source: ProfileSource.defaultProfile),
    );
    await expectLater(
      mainProfile.rename(
        const RenameProfileCommand(profileId: 'profile-id', name: 'new'),
      ),
      throwsA(isA<ProfileNotManagedFailure>()),
    );
    expect(mainProfile.events, ['repository.find:profile-id']);

    final unchanged = _Fixture();
    await expectLater(
      unchanged.rename(
        const RenameProfileCommand(profileId: 'profile-id', name: 'team'),
      ),
      throwsA(isA<ProfileNameUnchangedFailure>()),
    );
    expect(unchanged.events, ['repository.find:profile-id']);
  });

  test('rename preserves lifecycle then discovery order', () async {
    final renamed = _profile(profileName: 'new_team');
    final fixture = _Fixture(discovered: [renamed]);

    final result = await fixture.rename(
      const RenameProfileCommand(profileId: 'profile-id', name: ' new_team '),
    );

    expect(fixture.events, [
      'repository.find:profile-id',
      'lifecycle.rename:profile-id:new_team',
      'discovery.discover',
    ]);
    expect(result.profile.profileName, 'new_team');
    expect(result.snapshot.findById('profile-id'), same(renamed));
  });

  test('rename wraps a post-lifecycle failure without rollback', () async {
    final cause = StateError('rescan failed');
    final fixture = _Fixture(discoveryFailure: cause);

    await expectLater(
      fixture.rename(
        const RenameProfileCommand(profileId: 'profile-id', name: 'new_team'),
      ),
      throwsA(
        isA<ProfileMutationAppliedFailure>()
            .having(
              (failure) => failure.operation,
              'operation',
              ProfileOperation.rename,
            )
            .having((failure) => failure.cause, 'cause', same(cause)),
      ),
    );
  });

  test('delete validates then returns the rediscovered snapshot', () async {
    final remaining = _profile(id: 'remaining', profileName: 'remaining');
    final fixture = _Fixture(discovered: [remaining]);

    final snapshot = await fixture.delete(
      const DeleteProfileCommand('profile-id'),
    );

    expect(fixture.events, [
      'repository.find:profile-id',
      'lifecycle.delete:profile-id',
      'discovery.discover',
    ]);
    expect(snapshot.profiles, [remaining]);
  });

  test(
    'delete rejects deactivated and main profiles before lifecycle',
    () async {
      final deactivated = _Fixture(
        stored: _profile(kind: ProfileKind.deactivated),
      );
      await expectLater(
        deactivated.delete(const DeleteProfileCommand('profile-id')),
        throwsA(isA<ProfileDeactivatedFailure>()),
      );
      expect(deactivated.events, ['repository.find:profile-id']);

      final mainProfile = _Fixture(
        stored: _profile(source: ProfileSource.defaultProfile),
      );
      await expectLater(
        mainProfile.delete(const DeleteProfileCommand('profile-id')),
        throwsA(isA<ProfileNotManagedFailure>()),
      );
      expect(mainProfile.events, ['repository.find:profile-id']);
    },
  );

  test('delete wraps a post-lifecycle failure without rollback', () async {
    final cause = StateError('rescan failed');
    final fixture = _Fixture(discoveryFailure: cause);

    await expectLater(
      fixture.delete(const DeleteProfileCommand('profile-id')),
      throwsA(
        isA<ProfileMutationAppliedFailure>()
            .having(
              (failure) => failure.operation,
              'operation',
              ProfileOperation.delete,
            )
            .having((failure) => failure.cause, 'cause', same(cause)),
      ),
    );
  });

  test('display update normalizes alias through the repository', () async {
    final fixture = _Fixture();

    final updated = await fixture.updateDisplay(
      const UpdateProfileDisplayCommand(
        profileId: 'profile-id',
        displayName: '   ',
        isFavorite: true,
      ),
    );

    expect(fixture.events, [
      'repository.find:profile-id',
      'repository.save:profile-id:team:true',
    ]);
    expect(updated.displayName, 'team');
    expect(updated.isFavorite, isTrue);
  });

  test('display update rejects a missing profile before persistence', () async {
    final fixture = _Fixture(hasStoredProfile: false);

    await expectLater(
      fixture.updateDisplay(
        const UpdateProfileDisplayCommand(
          profileId: 'missing',
          displayName: 'Equipo',
          isFavorite: false,
        ),
      ),
      throwsA(isA<ProfileNotFoundFailure>()),
    );
    expect(fixture.events, ['repository.find:missing']);
  });
}

final class _Fixture {
  _Fixture({
    Profile? stored,
    bool hasStoredProfile = true,
    List<Profile>? discovered,
    Object? discoveryFailure,
    Object? saveFailure,
    Object? createFailure,
  }) : events = [],
       repository = _MemoryRepository(
         [],
         hasStoredProfile ? stored ?? _profile() : null,
         saveFailure: saveFailure,
       ),
       discovery = _MemoryDiscovery(
         [],
         discovered ?? [stored ?? _profile()],
         failure: discoveryFailure,
       ),
       lifecycle = _MemoryLifecycle([], createFailure: createFailure) {
    repository.events = events;
    discovery.events = events;
    lifecycle.events = events;
  }

  final List<String> events;
  final _MemoryRepository repository;
  final _MemoryDiscovery discovery;
  final _MemoryLifecycle lifecycle;

  Future<CreateProfileResult> create(CreateProfileCommand command) =>
      CreateProfile(
        repository: repository,
        discovery: discovery,
        lifecycle: lifecycle,
      )(command);

  Future<RenameProfileResult> rename(RenameProfileCommand command) =>
      RenameProfile(
        repository: repository,
        discovery: discovery,
        lifecycle: lifecycle,
      )(command);

  Future<ProfileSnapshot> delete(DeleteProfileCommand command) => DeleteProfile(
    repository: repository,
    discovery: discovery,
    lifecycle: lifecycle,
  )(command);

  Future<Profile> updateDisplay(UpdateProfileDisplayCommand command) =>
      UpdateProfileDisplay(repository: repository)(command);
}

final class _MemoryRepository implements ProfileRepository {
  _MemoryRepository(this.events, this.profile, {this.saveFailure});

  List<String> events;
  Profile? profile;
  final Object? saveFailure;

  @override
  Future<Profile?> findById(String profileId) async {
    events.add('repository.find:$profileId');
    return profile?.id == profileId ? profile : null;
  }

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {
    events.add('repository.save:$profileId:$displayName:$isFavorite');
    final error = saveFailure;
    if (error != null) throw error;
  }
}

final class _MemoryDiscovery implements ProfileDiscovery {
  _MemoryDiscovery(this.events, this.profiles, {this.failure});

  List<String> events;
  final List<Profile> profiles;
  final Object? failure;

  @override
  Future<List<Profile>> discover() async {
    events.add('discovery.discover');
    final error = failure;
    if (error != null) throw error;
    return profiles;
  }
}

final class _MemoryLifecycle implements ProfileLifecycle {
  _MemoryLifecycle(this.events, {this.createFailure});

  List<String> events;
  final Object? createFailure;

  @override
  Future<void> create({
    required String toolKey,
    required ProfileName profileName,
    required ProfileSetupMode setupMode,
    required bool seedFromBase,
  }) async {
    events.add(
      'lifecycle.create:$toolKey:${profileName.value}:${setupMode.name}:$seedFromBase',
    );
    final error = createFailure;
    if (error != null) throw error;
  }

  @override
  Future<void> delete(Profile profile) async {
    events.add('lifecycle.delete:${profile.id}');
  }

  @override
  Future<void> rename({
    required Profile profile,
    required ProfileName profileName,
  }) async {
    events.add('lifecycle.rename:${profile.id}:${profileName.value}');
  }
}

Profile _profile({
  String id = 'profile-id',
  String toolKey = 'codex',
  String profileName = 'team',
  String displayName = 'Team',
  bool isFavorite = false,
  ProfileSource source = ProfileSource.multiCli,
  ProfileKind kind = ProfileKind.full,
}) => Profile(
  id: id,
  toolKey: toolKey,
  profileName: profileName,
  commandName: 'codex-$profileName',
  displayName: displayName,
  profileHome: '/profiles/$toolKey/$profileName',
  source: source,
  kind: kind,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: isFavorite,
);
