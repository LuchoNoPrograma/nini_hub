import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/presentation/controllers/profiles_controller.dart';
import 'package:nini_hub/features/profiles/presentation/profile_dialogs.dart';
import 'package:nini_hub/features/profiles/presentation/state/profiles_state.dart';

void main() {
  testWidgets('cancel before creation preserves the form and creates nothing', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.container.dispose);
    var proceed = false;
    final selectedTools = <String>[];
    await tester.pumpWidget(
      _Harness(
        label: 'Abrir',
        onPressed: (context) async {
          await showCreateProfileDialog(
            context,
            create: (command) async {
              selectedTools.add(command.toolKey);
              expect(fixture.store.events, isEmpty);
              return proceed ? fixture.controller.create(command) : null;
            },
            readError: () => fixture.readState().errorMessage,
          );
        },
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'team');
    await tester.tap(find.text('Crear y vincular'));
    await tester.pumpAndSettle();
    expect(fixture.store.events, isEmpty);
    expect(find.text('Nuevo perfil'), findsOneWidget);
    expect(find.text('team'), findsOneWidget);
    proceed = true;
    await tester.tap(find.text('Crear y vincular'));
    await tester.pumpAndSettle();
    expect(selectedTools, ['codex', 'codex']);
    expect(
      fixture.store.events.first,
      'lifecycle.create:codex:team:shared:false',
    );
    expect(find.text('Nuevo perfil'), findsNothing);
  });

  testWidgets(
    'create dialog submits the application command and visible alias',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.container.dispose);
      Profile? created;
      await tester.pumpWidget(
        _Harness(
          label: 'Abrir creación',
          onPressed: (context) async {
            created = await showCreateProfileDialog(
              context,
              create: fixture.controller.create,
              readError: () => fixture.readState().errorMessage,
            );
          },
        ),
      );

      await tester.tap(find.text('Abrir creación'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '../team');
      await tester.tap(find.text('Crear y vincular'));
      await tester.pump();
      expect(
        find.textContaining('Usa entre 1 y 48 caracteres'),
        findsOneWidget,
      );
      expect(fixture.store.events, isEmpty);

      await tester.enterText(find.byType(TextFormField).first, 'team_02');
      await tester.enterText(find.byType(TextFormField).last, 'Equipo');
      await tester.tap(find.text('Crear y vincular'));
      await tester.pumpAndSettle();

      expect(created?.profileName, 'team_02');
      expect(created?.displayName, 'Equipo');
      expect(fixture.store.events, [
        'lifecycle.create:codex:team_02:shared:false',
        'save:profile-id:Equipo',
      ]);
      expect(find.text('Nuevo perfil'), findsNothing);
    },
  );

  testWidgets('rename dialog keeps a typed failure visible and recoverable', (
    tester,
  ) async {
    final fixture = _Fixture(
      profiles: [_profile(kind: ProfileKind.deactivated)],
    );
    addTearDown(fixture.container.dispose);
    await tester.pumpWidget(
      _Harness(
        label: 'Abrir renombre',
        onPressed: (context) async {
          await showRenameProfileDialog(
            context,
            controller: fixture.controller,
            readState: fixture.readState,
            profileId: 'profile-id',
            toolKey: 'codex',
            profileName: 'team',
          );
        },
      ),
    );

    await tester.tap(find.text('Abrir renombre'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'renamed');
    await tester.tap(find.text('Renombrar'));
    await tester.pumpAndSettle();

    expect(
      find.text('La cuenta está desactivada en este equipo.'),
      findsOneWidget,
    );
    expect(find.text('Cambiar identificador'), findsOneWidget);
    expect(fixture.store.events, isEmpty);
  });

  testWidgets('delete dialog confirms through Profiles and returns success', (
    tester,
  ) async {
    final fixture = _Fixture(profiles: [_profile()]);
    addTearDown(fixture.container.dispose);
    var deleted = false;
    await tester.pumpWidget(
      _Harness(
        label: 'Abrir eliminación',
        onPressed: (context) async {
          deleted = await showDeleteProfileDialog(
            context,
            controller: fixture.controller,
            readState: fixture.readState,
            profileId: 'profile-id',
            displayName: 'Team',
          );
        },
      ),
    );

    await tester.tap(find.text('Abrir eliminación'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar Team'), findsOneWidget);
    await tester.tap(find.text('Eliminar perfil'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(fixture.store.events, ['lifecycle.delete:profile-id']);
    expect(fixture.store.profiles, isEmpty);
  });
}

final class _Harness extends StatelessWidget {
  const _Harness({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => onPressed(context),
            child: Text(label),
          ),
        ),
      ),
    ),
  );
}

final class _Fixture {
  _Fixture({List<Profile> profiles = const []}) : store = _Store(profiles) {
    repository = _Repository(store);
    discovery = _Discovery(store);
    lifecycle = _Lifecycle(store);
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

  final _Store store;
  late final _Repository repository;
  late final _Discovery discovery;
  late final _Lifecycle lifecycle;
  late final NotifierProvider<ProfilesController, ProfilesState> provider;
  late final ProviderContainer container;
  late final ProfilesController controller;

  ProfilesState readState() => container.read(provider);
}

final class _Store {
  _Store(List<Profile> profiles) : profiles = [...profiles];

  List<Profile> profiles;
  final List<String> events = [];
}

final class _Repository implements ProfileRepository {
  const _Repository(this.store);

  final _Store store;

  @override
  Future<Profile?> findById(String profileId) async {
    for (final profile in store.profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  @override
  Future<void> saveDisplayData({
    required String profileId,
    required String displayName,
    required bool isFavorite,
  }) async {
    store.events.add('save:$profileId:$displayName');
    store.profiles = [
      for (final profile in store.profiles)
        if (profile.id == profileId)
          profile.withDisplayData(
            displayName: displayName,
            isFavorite: isFavorite,
          )
        else
          profile,
    ];
  }
}

final class _Discovery implements ProfileDiscovery {
  const _Discovery(this.store);

  final _Store store;

  @override
  Future<List<Profile>> discover() async => [...store.profiles];
}

final class _Lifecycle implements ProfileLifecycle {
  const _Lifecycle(this.store);

  final _Store store;

  @override
  Future<void> create({
    required String toolKey,
    required ProfileName profileName,
    required ProfileSetupMode setupMode,
    required bool seedFromBase,
  }) async {
    store.events.add(
      'lifecycle.create:$toolKey:${profileName.value}:${setupMode.name}:$seedFromBase',
    );
    store.profiles = [
      _profile(
        toolKey: toolKey,
        profileName: profileName.value,
        kind: setupMode == ProfileSetupMode.shared
            ? ProfileKind.shared
            : ProfileKind.full,
      ),
    ];
  }

  @override
  Future<void> delete(Profile profile) async {
    store.events.add('lifecycle.delete:${profile.id}');
    store.profiles = [
      for (final current in store.profiles)
        if (current.id != profile.id) current,
    ];
  }

  @override
  Future<void> rename({
    required Profile profile,
    required ProfileName profileName,
  }) async {
    store.events.add('lifecycle.rename:${profile.id}:${profileName.value}');
    store.profiles = [
      for (final current in store.profiles)
        if (current.id == profile.id)
          _profile(
            toolKey: current.toolKey,
            profileName: profileName.value,
            kind: current.kind,
          )
        else
          current,
    ];
  }
}

Profile _profile({
  String toolKey = 'codex',
  String profileName = 'team',
  ProfileKind kind = ProfileKind.full,
}) => Profile(
  id: 'profile-id',
  toolKey: toolKey,
  profileName: profileName,
  commandName: '$toolKey-$profileName',
  displayName: 'Team',
  profileHome: '/tmp/$profileName',
  source: ProfileSource.multiCli,
  kind: kind,
  hasAuthFile: false,
  isAvailable: kind != ProfileKind.deactivated,
  isFavorite: false,
);
