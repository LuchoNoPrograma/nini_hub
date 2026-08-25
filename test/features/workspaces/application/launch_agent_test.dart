import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/domain/agent_profile.dart';
import 'package:nini_hub/features/profiles/domain/agent_profile_repository.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/workspaces/application/launch_agent.dart';
import 'package:nini_hub/features/workspaces/domain/agent_launcher.dart';
import 'package:nini_hub/features/workspaces/domain/workspace.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_failure.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_repository.dart';

void main() {
  test('launches before recording usage and persisting selection', () async {
    final fixture = _Fixture();

    final result = await fixture.launchAgent(fixture.command);

    expect(result.profile.id, 'profile');
    expect(result.workspace.id, 'opened');
    expect(fixture.selectionStore.currentWorkspaceId, 'opened');
    expect(fixture.events, [
      'profile.find:profile',
      'workspace.find:workspace',
      'launcher.launch:profile:/tmp/workspace',
      'workspace.recordOpened:/tmp/workspace',
      'selection.save:opened',
    ]);
  });

  test('missing profile fails before workspace lookup', () async {
    final fixture = _Fixture(profileExists: false);

    await expectLater(
      fixture.launchAgent(fixture.command),
      throwsA(
        isA<ProfileNotFoundFailure>().having(
          (failure) => failure.profileId,
          'profileId',
          'profile',
        ),
      ),
    );

    expect(fixture.events, ['profile.find:profile']);
  });

  test(
    'unavailable or unlinked profile fails before workspace lookup',
    () async {
      for (final profile in [
        _profile(isAvailable: false),
        _profile(hasAuthFile: false),
      ]) {
        final fixture = _Fixture(profile: profile);

        await expectLater(
          fixture.launchAgent(fixture.command),
          throwsA(isA<ProfileUnavailableFailure>()),
        );

        expect(fixture.events, ['profile.find:profile']);
      }
    },
  );

  test('missing workspace fails before launching', () async {
    final fixture = _Fixture(workspaceExists: false);

    await expectLater(
      fixture.launchAgent(fixture.command),
      throwsA(isA<WorkspaceNotFoundFailure>()),
    );

    expect(fixture.events, [
      'profile.find:profile',
      'workspace.find:workspace',
    ]);
  });

  test('launcher failure prevents workspace bookkeeping', () async {
    const failure = AgentLauncherFailure();
    final fixture = _Fixture(launcherFailure: failure);

    await expectLater(
      fixture.launchAgent(fixture.command),
      throwsA(same(failure)),
    );

    expect(fixture.events, [
      'profile.find:profile',
      'workspace.find:workspace',
      'launcher.launch:profile:/tmp/workspace',
    ]);
    expect(fixture.selectionStore.currentWorkspaceId, isNull);
  });

  test(
    'recording failure happens after launch and prevents selection',
    () async {
      final failure = StateError('workspace bookkeeping failed');
      final fixture = _Fixture(recordOpenedFailure: failure);

      await expectLater(
        fixture.launchAgent(fixture.command),
        throwsA(same(failure)),
      );

      expect(fixture.events, [
        'profile.find:profile',
        'workspace.find:workspace',
        'launcher.launch:profile:/tmp/workspace',
        'workspace.recordOpened:/tmp/workspace',
      ]);
      expect(fixture.selectionStore.currentWorkspaceId, isNull);
    },
  );

  test('selection failure keeps launch and recorded usage completed', () async {
    final failure = StateError('selection failed');
    final fixture = _Fixture(selectionFailure: failure);

    await expectLater(
      fixture.launchAgent(fixture.command),
      throwsA(same(failure)),
    );

    expect(fixture.events, [
      'profile.find:profile',
      'workspace.find:workspace',
      'launcher.launch:profile:/tmp/workspace',
      'workspace.recordOpened:/tmp/workspace',
      'selection.save:opened',
    ]);
  });
}

final class _Fixture {
  _Fixture({
    bool profileExists = true,
    AgentProfile? profile,
    bool workspaceExists = true,
    Workspace? workspace,
    Object? launcherFailure,
    Object? recordOpenedFailure,
    Object? selectionFailure,
  }) : events = [],
       profileRepository = _MemoryAgentProfileRepository(
         profileExists ? profile ?? _profile() : null,
       ),
       workspaceRepository = _MemoryWorkspaceRepository(
         workspaceExists ? workspace ?? _workspace() : null,
         recordOpenedFailure: recordOpenedFailure,
       ),
       selectionStore = _MemoryWorkspaceSelectionStore(
         failure: selectionFailure,
       ),
       launcher = _RecordingAgentLauncher(failure: launcherFailure) {
    profileRepository.events = events;
    workspaceRepository.events = events;
    selectionStore.events = events;
    launcher.events = events;
    launchAgent = LaunchAgent(
      profileRepository: profileRepository,
      workspaceRepository: workspaceRepository,
      selectionStore: selectionStore,
      launcher: launcher,
    );
  }

  final List<String> events;
  final _MemoryAgentProfileRepository profileRepository;
  final _MemoryWorkspaceRepository workspaceRepository;
  final _MemoryWorkspaceSelectionStore selectionStore;
  final _RecordingAgentLauncher launcher;
  late final LaunchAgent launchAgent;

  final LaunchAgentCommand command = const LaunchAgentCommand(
    profileId: 'profile',
    workspaceId: 'workspace',
  );
}

AgentProfile _profile({bool isAvailable = true, bool hasAuthFile = true}) =>
    AgentProfile(
      id: 'profile',
      toolKey: 'codex',
      profileName: 'profile',
      displayName: 'Profile',
      profileHome: '/tmp/profile',
      profileSource: 'multicli',
      hasAuthFile: hasAuthFile,
      isAvailable: isAvailable,
    );

Workspace _workspace() => Workspace(
  id: 'workspace',
  path: '/tmp/workspace',
  name: 'Workspace',
  openCount: 3,
  createdAt: DateTime.utc(2026, 8, 22),
  lastUsedAt: DateTime.utc(2026, 8, 22),
);

final class _MemoryAgentProfileRepository implements AgentProfileRepository {
  _MemoryAgentProfileRepository(this.profile);

  final AgentProfile? profile;
  late List<String> events;

  @override
  Future<AgentProfile?> findById(String profileId) async {
    events.add('profile.find:$profileId');
    return profile?.id == profileId ? profile : null;
  }
}

final class _MemoryWorkspaceRepository implements WorkspaceRepository {
  _MemoryWorkspaceRepository(this.workspace, {this.recordOpenedFailure});

  final Workspace? workspace;
  final Object? recordOpenedFailure;
  late List<String> events;

  @override
  Future<Workspace?> findById(String workspaceId) async {
    events.add('workspace.find:$workspaceId');
    return workspace?.id == workspaceId ? workspace : null;
  }

  @override
  Future<Workspace> recordOpened(String path) async {
    events.add('workspace.recordOpened:$path');
    if (recordOpenedFailure != null) throw recordOpenedFailure!;
    return Workspace(
      id: 'opened',
      path: path,
      name: 'Workspace',
      openCount: 4,
      createdAt: DateTime.utc(2026, 8, 22),
      lastUsedAt: DateTime.utc(2026, 8, 22, 0, 0, 1),
    );
  }

  @override
  Future<List<Workspace>> loadAll() async => const [];

  @override
  Future<Workspace> add(String path) async => throw UnsupportedError('add');

  @override
  Future<void> select(String workspaceId) async =>
      throw UnsupportedError('select');

  @override
  Future<void> rename({required String workspaceId, required String name}) =>
      throw UnsupportedError('rename');

  @override
  Future<void> remove(String workspaceId) async =>
      throw UnsupportedError('remove');
}

final class _MemoryWorkspaceSelectionStore implements WorkspaceSelectionStore {
  _MemoryWorkspaceSelectionStore({this.failure});

  final Object? failure;
  late List<String> events;
  String? currentWorkspaceId;

  @override
  Future<String?> loadCurrentWorkspaceId() async => currentWorkspaceId;

  @override
  Future<void> saveCurrentWorkspaceId(String? workspaceId) async {
    events.add('selection.save:${workspaceId ?? 'null'}');
    if (failure != null) throw failure!;
    currentWorkspaceId = workspaceId;
  }
}

final class _RecordingAgentLauncher implements AgentLauncher {
  _RecordingAgentLauncher({this.failure});

  final Object? failure;
  late List<String> events;

  @override
  Future<void> launch(
    AgentProfile profile, {
    required String workingDirectory,
  }) async {
    events.add('launcher.launch:${profile.id}:$workingDirectory');
    if (failure != null) throw failure!;
  }
}
