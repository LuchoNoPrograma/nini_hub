import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/presentation/controllers/profiles_controller.dart';
import 'package:nini_hub/features/profiles/presentation/state/profiles_state.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  test('loads an immutable snapshot and rejects an overlapping load', () async {
    final gate = Completer<List<Profile>>();
    fixture.discovery.gate = gate;

    final firstLoad = fixture.controller.load();
    final overlappingLoad = fixture.controller.load();

    expect(fixture.state.isInitialized, isFalse);
    expect(fixture.state.isLoading, isTrue);
    expect(await overlappingLoad, isFalse);
    gate.complete([_profile()]);
    expect(await firstLoad, isTrue);
    expect(fixture.state.isInitialized, isTrue);
    expect(fixture.state.findById('profile-id'), isNotNull);
    expect(
      () => fixture.state.profiles.add(_profile(id: 'forbidden')),
      throwsUnsupportedError,
    );
  });

  test('updates only profile state from use case results', () async {
    fixture.discovery.profiles = [_profile()];
    expect(await fixture.controller.load(), isTrue);

    final created = _profile(id: 'created', profileName: 'created');
    fixture.discovery.profiles = [_profile(), created];
    expect(
      await fixture.controller.create(
        const CreateProfileCommand(
          toolKey: 'codex',
          name: 'created',
          displayName: '',
        ),
      ),
      same(created),
    );
    expect(fixture.state.findById(created.id), same(created));

    final renamed = _profile(id: created.id, profileName: 'renamed');
    fixture.repository.profile = created;
    fixture.discovery.profiles = [_profile(), renamed];
    expect(
      await fixture.controller.rename(
        RenameProfileCommand(profileId: created.id, name: 'renamed'),
      ),
      same(renamed),
    );
    expect(fixture.state.findById(created.id), same(renamed));

    fixture.repository.profile = renamed;
    final displayed = await fixture.controller.updateDisplay(
      UpdateProfileDisplayCommand(
        profileId: renamed.id,
        displayName: '  Equipo  ',
        isFavorite: true,
      ),
    );
    expect(displayed?.displayName, 'Equipo');
    expect(fixture.state.findById(renamed.id)?.displayName, 'Equipo');
    expect(fixture.state.findById(renamed.id)?.isFavorite, isTrue);

    fixture.repository.profile = displayed;
    fixture.discovery.profiles = [_profile()];
    expect(
      await fixture.controller.delete(DeleteProfileCommand(renamed.id)),
      isTrue,
    );
    expect(fixture.state.findById(renamed.id), isNull);
    expect(fixture.discovery.calls, 4);
    expect(fixture.repository.savedDisplayData, ['created:Equipo:true']);
  });

  test('rejects every overlapping operation while a mutation runs', () async {
    fixture.discovery.profiles = [_profile()];
    expect(await fixture.controller.load(), isTrue);
    final gate = Completer<void>();
    fixture.lifecycle.renameGate = gate;
    final renamed = _profile(profileName: 'renamed');
    fixture.discovery.profiles = [renamed];

    final firstRename = fixture.controller.rename(
      const RenameProfileCommand(profileId: 'profile-id', name: 'renamed'),
    );

    expect(fixture.state.operation, ProfilesOperation.rename);
    expect(fixture.state.operationProfileId, 'profile-id');
    expect(await fixture.controller.load(), isFalse);
    expect(
      await fixture.controller.create(
        const CreateProfileCommand(
          toolKey: 'codex',
          name: 'other',
          displayName: '',
        ),
      ),
      isNull,
    );
    expect(
      await fixture.controller.delete(const DeleteProfileCommand('profile-id')),
      isFalse,
    );
    expect(
      await fixture.controller.updateDisplay(
        const UpdateProfileDisplayCommand(
          profileId: 'profile-id',
          displayName: 'Other',
          isFavorite: false,
        ),
      ),
      isNull,
    );

    gate.complete();
    expect(await firstRename, same(renamed));
    expect(fixture.lifecycle.renameCalls, 1);
    expect(fixture.state.operation, isNull);
  });

  test(
    'translates typed and partial failures while retaining causes',
    () async {
      expect(
        await fixture.controller.create(
          const CreateProfileCommand(
            toolKey: 'codex',
            name: '../invalid',
            displayName: '',
          ),
        ),
        isNull,
      );
      expect(fixture.state.failure, isA<InvalidProfileNameFailure>());
      expect(
        fixture.state.errorMessage,
        'Usa entre 1 y 48 caracteres: letras, números, guion o guion bajo.',
      );

      fixture.controller.clearFailure();
      fixture.repository.profile = _profile(kind: ProfileKind.deactivated);
      expect(
        await fixture.controller.rename(
          const RenameProfileCommand(profileId: 'profile-id', name: 'renamed'),
        ),
        isNull,
      );
      expect(fixture.state.failure, isA<ProfileDeactivatedFailure>());
      expect(
        fixture.state.errorMessage,
        'La cuenta está desactivada en este equipo.',
      );

      fixture.controller.clearFailure();
      final cause = StateError('rescan failed');
      fixture.discovery.failure = cause;
      expect(
        await fixture.controller.create(
          const CreateProfileCommand(
            toolKey: 'codex',
            name: 'created',
            displayName: '',
          ),
        ),
        isNull,
      );
      expect(
        fixture.state.failure,
        isA<ProfileMutationAppliedFailure>().having(
          (failure) => failure.cause,
          'cause',
          same(cause),
        ),
      );
      expect(
        fixture.state.errorMessage,
        'Nini Agents inició la creación, pero no confirmó el resultado.',
      );
      expect(fixture.state.operation, isNull);
    },
  );

  test('refreshes visible profiles after a partial engine result', () async {
    final reconciled = _profile(id: 'created', profileName: 'created');
    fixture.discovery.profiles = [reconciled];
    fixture.lifecycle.createFailure = ProfileMutationAppliedFailure(
      operation: ProfileOperation.create,
      profileName: 'created',
      cause: StateError('partial'),
    );

    expect(
      await fixture.controller.create(
        const CreateProfileCommand(
          toolKey: 'codex',
          name: 'created',
          displayName: '',
        ),
      ),
      isNull,
    );

    expect(fixture.discovery.calls, 1);
    expect(fixture.state.findById('created'), same(reconciled));
    expect(fixture.state.isInitialized, isTrue);
    expect(fixture.state.failure, isA<ProfileMutationAppliedFailure>());
  });

  test(
    'keeps unexpected failures with an operation-specific message',
    () async {
      final failure = StateError('database failed');
      fixture.discovery.failure = failure;

      expect(await fixture.controller.load(), isFalse);

      expect(fixture.state.failure, same(failure));
      expect(fixture.state.errorMessage, 'No se pudieron cargar los perfiles.');
      expect(fixture.state.operation, isNull);
    },
  );
}

final class _Fixture {
  _Fixture()
    : repository = _MemoryRepository(_profile()),
      discovery = _MemoryDiscovery([_profile()]),
      lifecycle = _MemoryLifecycle() {
    provider = NotifierProvider<ProfilesController, ProfilesState>(
      () => ProfilesController(
        discoverProfiles: DiscoverProfiles(discovery: discovery),
        createProfile: CreateProfile(
          repository: repository,
          discovery: discovery,
          lifecycle: lifecycle,
        ),
        renameProfile: RenameProfile(
          repository: repository,
          discovery: discovery,
          lifecycle: lifecycle,
        ),
        deleteProfile: DeleteProfile(
          repository: repository,
          discovery: discovery,
          lifecycle: lifecycle,
        ),
        updateProfileDisplay: UpdateProfileDisplay(repository: repository),
      ),
    );
    container = ProviderContainer();
    controller = container.read(provider.notifier);
  }

  final _MemoryRepository repository;
  final _MemoryDiscovery discovery;
  final _MemoryLifecycle lifecycle;
  late final NotifierProvider<ProfilesController, ProfilesState> provider;
  late final ProviderContainer container;
  late final ProfilesController controller;

  ProfilesState get state => container.read(provider);

  void dispose() => container.dispose();
}

final class _MemoryRepository implements ProfileRepository {
  _MemoryRepository(this.profile);

  Profile? profile;
  final List<String> savedDisplayData = [];

  @override
  Future<Profile?> findById(String profileId) async =>
      profile?.id == profileId ? profile : null;

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {
    savedDisplayData.add('$profileId:$displayName:$isFavorite');
  }
}

final class _MemoryDiscovery implements ProfileDiscovery {
  _MemoryDiscovery(this.profiles);

  List<Profile> profiles;
  Completer<List<Profile>>? gate;
  Object? failure;
  int calls = 0;

  @override
  Future<List<Profile>> discover() async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    final currentGate = gate;
    gate = null;
    return currentGate == null ? profiles : currentGate.future;
  }
}

final class _MemoryLifecycle implements ProfileLifecycle {
  Completer<void>? renameGate;
  Object? createFailure;
  int renameCalls = 0;

  @override
  Future<void> create({
    required String toolKey,
    required ProfileName profileName,
    required ProfileSetupMode setupMode,
    required bool seedFromBase,
  }) async {
    final failure = createFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> rename({
    required Profile profile,
    required ProfileName profileName,
  }) async {
    renameCalls++;
    final gate = renameGate;
    renameGate = null;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> delete(Profile profile) async {}
}

Profile _profile({
  String id = 'profile-id',
  String profileName = 'team',
  String? displayName,
  bool isFavorite = false,
  ProfileKind kind = ProfileKind.full,
}) => Profile(
  id: id,
  toolKey: 'codex',
  profileName: profileName,
  commandName: 'codex-$profileName',
  displayName: displayName ?? profileName,
  profileHome: '/profiles/codex/$profileName',
  source: ProfileSource.multiCli,
  kind: kind,
  hasAuthFile: true,
  isAvailable: kind != ProfileKind.deactivated,
  isFavorite: isFavorite,
);
