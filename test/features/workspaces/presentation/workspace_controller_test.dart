import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/domain/agent_profile.dart';
import 'package:nini_hub/features/profiles/domain/agent_profile_repository.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/workspaces/application/launch_agent.dart';
import 'package:nini_hub/features/workspaces/application/workspace_history.dart';
import 'package:nini_hub/features/workspaces/domain/agent_launcher.dart';
import 'package:nini_hub/features/workspaces/domain/workspace.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_failure.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_repository.dart';
import 'package:nini_hub/features/workspaces/presentation/controllers/workspace_controller.dart';
import 'package:nini_hub/features/workspaces/presentation/state/workspace_state.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.dispose());

  test('loads an immutable snapshot and rejects an overlapping load', () async {
    final gate = Completer<List<Workspace>>();
    fixture.repository.loadGate = gate;

    final firstLoad = fixture.controller.load();
    final overlappingLoad = fixture.controller.load();

    expect(fixture.state.operation, WorkspaceOperation.load);
    expect(await overlappingLoad, isFalse);
    gate.complete(fixture.repository.snapshot);
    expect(await firstLoad, isTrue);
    expect(fixture.state.currentWorkspaceId, 'workspace-1');
    expect(fixture.state.workspaces, hasLength(2));
    expect(fixture.selectionStore.savedIds, isEmpty);
    expect(
      () => fixture.state.workspaces.add(_workspace(id: 'forbidden')),
      throwsUnsupportedError,
    );
  });

  test('updates only workspace state for history mutations', () async {
    fixture.selectionStore.currentWorkspaceId = 'workspace-1';
    expect(await fixture.controller.load(), isTrue);

    expect(await fixture.controller.add('/work/added'), isTrue);
    final addedId = fixture.state.currentWorkspaceId;
    expect(addedId, startsWith('added-'));
    expect(fixture.state.workspaces.first.id, addedId);

    expect(await fixture.controller.select('workspace-2'), isTrue);
    expect(fixture.state.currentWorkspaceId, 'workspace-2');
    expect(fixture.state.workspaces.first.id, 'workspace-2');

    expect(
      await fixture.controller.rename(
        workspaceId: 'workspace-2',
        name: '  Renamed  ',
      ),
      isTrue,
    );
    expect(fixture.state.currentWorkspace!.name, 'Renamed');

    expect(await fixture.controller.forget('workspace-2'), isTrue);
    expect(fixture.state.currentWorkspaceId, fixture.state.workspaces.first.id);
    expect(
      fixture.selectionStore.savedIds,
      containsAllInOrder([
        addedId,
        'workspace-2',
        fixture.state.currentWorkspaceId,
      ]),
    );
    expect(fixture.state.operation, isNull);
  });

  test(
    'launch is single-flight and updates recency without reloading',
    () async {
      fixture.selectionStore.currentWorkspaceId = 'workspace-1';
      expect(await fixture.controller.load(), isTrue);
      final loadCallsBeforeLaunch = fixture.repository.loadAllCalls;
      final gate = Completer<void>();
      fixture.launcher.gate = gate;

      final firstLaunch = fixture.controller.launch(
        profileId: 'profile-1',
        workspaceId: 'workspace-2',
      );
      final overlappingLaunch = fixture.controller.launch(
        profileId: 'profile-1',
        workspaceId: 'workspace-2',
      );

      expect(fixture.state.isLaunching, isTrue);
      expect(await overlappingLaunch, isFalse);
      gate.complete();
      expect(await firstLaunch, isTrue);
      expect(fixture.launcher.calls, 1);
      expect(fixture.state.currentWorkspaceId, 'workspace-2');
      expect(fixture.state.workspaces.first.id, 'workspace-2');
      expect(fixture.state.workspaces.first.openCount, 3);
      expect(fixture.repository.loadAllCalls, loadCallsBeforeLaunch);
      expect(fixture.selectionStore.currentWorkspaceId, 'workspace-2');
    },
  );

  test('translates typed failures and retains unexpected causes', () async {
    expect(await fixture.controller.load(), isTrue);

    expect(
      await fixture.controller.rename(workspaceId: 'workspace-1', name: '   '),
      isFalse,
    );
    expect(fixture.state.failure, isA<InvalidWorkspaceNameFailure>());
    expect(
      fixture.state.errorMessage,
      'El nombre del workspace no puede quedar vacío.',
    );

    fixture.controller.clearFailure();
    expect(fixture.state.failure, isNull);
    expect(fixture.state.errorMessage, isNull);

    expect(
      await fixture.controller.launch(
        profileId: 'missing',
        workspaceId: 'workspace-1',
      ),
      isFalse,
    );
    expect(fixture.state.failure, isA<ProfileNotFoundFailure>());
    expect(
      fixture.state.errorMessage,
      'El perfil seleccionado ya no está disponible.',
    );

    fixture.launcher.failure = const AgentLauncherFailure();
    expect(
      await fixture.controller.launch(
        profileId: 'profile-1',
        workspaceId: 'workspace-1',
      ),
      isFalse,
    );
    expect(fixture.state.failure, isA<AgentLauncherFailure>());
    expect(
      fixture.state.errorMessage,
      'No se pudo abrir el agente en la terminal.',
    );

    final unexpected = StateError('database failed');
    fixture.repository.nextLoadFailure = unexpected;
    expect(await fixture.controller.load(), isFalse);
    expect(fixture.state.failure, same(unexpected));
    expect(fixture.state.errorMessage, 'No se pudo completar la operación.');
    expect(fixture.state.operation, isNull);
  });
}

final class _Fixture {
  _Fixture()
    : repository = _MemoryWorkspaceRepository([
        _workspace(id: 'workspace-1', lastUsedSecond: 2),
        _workspace(id: 'workspace-2', lastUsedSecond: 1),
      ]),
      selectionStore = _MemoryWorkspaceSelectionStore(),
      profileRepository = _MemoryAgentProfileRepository(_profile()),
      launcher = _RecordingAgentLauncher() {
    provider = NotifierProvider<WorkspaceController, WorkspaceState>(
      () => WorkspaceController(
        loadWorkspaceHistory: LoadWorkspaceHistory(
          repository: repository,
          selectionStore: selectionStore,
        ),
        addWorkspace: AddWorkspace(
          repository: repository,
          selectionStore: selectionStore,
        ),
        selectWorkspace: SelectWorkspace(
          repository: repository,
          selectionStore: selectionStore,
        ),
        renameWorkspace: RenameWorkspace(repository: repository),
        forgetWorkspace: ForgetWorkspace(
          repository: repository,
          selectionStore: selectionStore,
        ),
        launchAgent: LaunchAgent(
          profileRepository: profileRepository,
          workspaceRepository: repository,
          selectionStore: selectionStore,
          launcher: launcher,
        ),
      ),
    );
    container = ProviderContainer();
    controller = container.read(provider.notifier);
  }

  final _MemoryWorkspaceRepository repository;
  final _MemoryWorkspaceSelectionStore selectionStore;
  final _MemoryAgentProfileRepository profileRepository;
  final _RecordingAgentLauncher launcher;
  late final NotifierProvider<WorkspaceController, WorkspaceState> provider;
  late final ProviderContainer container;
  late final WorkspaceController controller;

  WorkspaceState get state => container.read(provider);

  void dispose() => container.dispose();
}

final class _MemoryWorkspaceRepository implements WorkspaceRepository {
  _MemoryWorkspaceRepository(List<Workspace> workspaces)
    : _workspaces = [...workspaces];

  final List<Workspace> _workspaces;
  Completer<List<Workspace>>? loadGate;
  Object? nextLoadFailure;
  int loadAllCalls = 0;
  int _nextId = 1;
  int _nextSecond = 10;

  List<Workspace> get snapshot => List.unmodifiable(_workspaces);

  @override
  Future<List<Workspace>> loadAll() async {
    loadAllCalls += 1;
    final failure = nextLoadFailure;
    nextLoadFailure = null;
    if (failure != null) throw failure;
    final gate = loadGate;
    loadGate = null;
    return gate == null ? snapshot : gate.future;
  }

  @override
  Future<Workspace?> findById(String workspaceId) async {
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return null;
  }

  @override
  Future<Workspace> add(String path) async {
    final workspace = Workspace(
      id: 'added-${_nextId++}',
      path: path,
      name: path.split('/').last,
      openCount: 0,
      createdAt: _nextTime(),
      lastUsedAt: _nextTime(),
    );
    _workspaces.insert(0, workspace);
    return workspace;
  }

  @override
  Future<Workspace> recordOpened(String path) async {
    final index = _workspaces.indexWhere((item) => item.path == path);
    if (index < 0) return add(path);
    final previous = _workspaces.removeAt(index);
    final opened = Workspace(
      id: previous.id,
      path: previous.path,
      name: previous.name,
      openCount: previous.openCount + 1,
      createdAt: previous.createdAt,
      lastUsedAt: _nextTime(),
    );
    _workspaces.insert(0, opened);
    return opened;
  }

  @override
  Future<void> select(String workspaceId) async {
    final index = _workspaces.indexWhere((item) => item.id == workspaceId);
    if (index < 0) return;
    final previous = _workspaces.removeAt(index);
    _workspaces.insert(
      0,
      Workspace(
        id: previous.id,
        path: previous.path,
        name: previous.name,
        openCount: previous.openCount,
        createdAt: previous.createdAt,
        lastUsedAt: _nextTime(),
      ),
    );
  }

  @override
  Future<void> rename({
    required String workspaceId,
    required String name,
  }) async {
    final index = _workspaces.indexWhere((item) => item.id == workspaceId);
    if (index < 0) return;
    final previous = _workspaces[index];
    _workspaces[index] = Workspace(
      id: previous.id,
      path: previous.path,
      name: name,
      openCount: previous.openCount,
      createdAt: previous.createdAt,
      lastUsedAt: previous.lastUsedAt,
    );
  }

  @override
  Future<void> remove(String workspaceId) async {
    _workspaces.removeWhere((item) => item.id == workspaceId);
  }

  DateTime _nextTime() => DateTime.utc(2026, 8, 22, 0, 0, _nextSecond++);
}

final class _MemoryWorkspaceSelectionStore implements WorkspaceSelectionStore {
  String? currentWorkspaceId = 'missing';
  final List<String?> savedIds = [];

  @override
  Future<String?> loadCurrentWorkspaceId() async => currentWorkspaceId;

  @override
  Future<void> saveCurrentWorkspaceId(String? workspaceId) async {
    currentWorkspaceId = workspaceId;
    savedIds.add(workspaceId);
  }
}

final class _MemoryAgentProfileRepository implements AgentProfileRepository {
  _MemoryAgentProfileRepository(this.profile);

  final AgentProfile profile;

  @override
  Future<AgentProfile?> findById(String profileId) async =>
      profile.id == profileId ? profile : null;
}

final class _RecordingAgentLauncher implements AgentLauncher {
  Completer<void>? gate;
  Object? failure;
  int calls = 0;

  @override
  Future<void> launch(
    AgentProfile profile, {
    required String workingDirectory,
  }) async {
    calls += 1;
    final currentGate = gate;
    gate = null;
    if (currentGate != null) await currentGate.future;
    if (failure != null) throw failure!;
  }
}

AgentProfile _profile() => const AgentProfile(
  id: 'profile-1',
  toolKey: 'codex',
  profileName: 'profile',
  displayName: 'Profile',
  profileHome: '/profiles/profile',
  profileSource: 'multicli',
  hasAuthFile: true,
  isAvailable: true,
);

Workspace _workspace({required String id, int lastUsedSecond = 0}) => Workspace(
  id: id,
  path: '/work/$id',
  name: id,
  openCount: 2,
  createdAt: DateTime.utc(2026, 8, 22),
  lastUsedAt: DateTime.utc(2026, 8, 22, 0, 0, lastUsedSecond),
);
