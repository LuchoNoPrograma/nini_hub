import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/workspaces/application/workspace_history.dart';
import 'package:nini_hub/features/workspaces/domain/workspace.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_failure.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_repository.dart';

void main() {
  test(
    'load falls back to the first workspace without rewriting selection',
    () async {
      final events = <String>[];
      final repository = _MemoryWorkspaceRepository(events, [
        _workspace('recent'),
        _workspace('older'),
      ]);
      final selectionStore = _MemoryWorkspaceSelectionStore(
        events,
        currentWorkspaceId: 'missing',
      );

      final snapshot = await LoadWorkspaceHistory(
        repository: repository,
        selectionStore: selectionStore,
      )();

      expect(snapshot.currentWorkspaceId, 'recent');
      expect(snapshot.currentWorkspace?.id, 'recent');
      expect(selectionStore.currentWorkspaceId, 'missing');
      expect(
        () => snapshot.workspaces.add(_workspace('unexpected')),
        throwsUnsupportedError,
      );
      expect(events, ['selection.load', 'repository.loadAll']);
    },
  );

  test('add persists selection before reloading history', () async {
    final events = <String>[];
    final repository = _MemoryWorkspaceRepository(events, [
      _workspace('older'),
    ], addedWorkspace: _workspace('new'));
    final selectionStore = _MemoryWorkspaceSelectionStore(events);

    final snapshot = await AddWorkspace(
      repository: repository,
      selectionStore: selectionStore,
    )('/tmp/new');

    expect(snapshot.currentWorkspaceId, 'new');
    expect(snapshot.workspaces.map((item) => item.id), ['new', 'older']);
    expect(events, [
      'repository.add:/tmp/new',
      'selection.save:new',
      'repository.loadAll',
    ]);
  });

  test('select updates recency before persisting selection', () async {
    final events = <String>[];
    final repository = _MemoryWorkspaceRepository(events, [
      _workspace('recent'),
      _workspace('older', openCount: 4),
    ]);
    final selectionStore = _MemoryWorkspaceSelectionStore(events);

    final snapshot = await SelectWorkspace(
      repository: repository,
      selectionStore: selectionStore,
    )('older');

    expect(snapshot.currentWorkspaceId, 'older');
    expect(snapshot.currentWorkspace?.openCount, 4);
    expect(events, [
      'repository.select:older',
      'selection.save:older',
      'repository.loadAll',
    ]);
  });

  test('rename validates and trims the name before the first effect', () async {
    final events = <String>[];
    final repository = _MemoryWorkspaceRepository(events, [_workspace('one')]);
    final rename = RenameWorkspace(repository: repository);

    await expectLater(
      rename(workspaceId: 'one', name: '   ', currentWorkspaceId: 'one'),
      throwsA(isA<InvalidWorkspaceNameFailure>()),
    );
    expect(events, isEmpty);

    final snapshot = await rename(
      workspaceId: 'one',
      name: '  Proyecto  ',
      currentWorkspaceId: 'one',
    );

    expect(snapshot.currentWorkspaceId, 'one');
    expect(events, ['repository.rename:one:Proyecto', 'repository.loadAll']);
  });

  test(
    'forget current selects and persists the first remaining workspace',
    () async {
      final events = <String>[];
      final repository = _MemoryWorkspaceRepository(events, [
        _workspace('current'),
        _workspace('fallback'),
      ]);
      final selectionStore = _MemoryWorkspaceSelectionStore(
        events,
        currentWorkspaceId: 'current',
      );

      final snapshot = await ForgetWorkspace(
        repository: repository,
        selectionStore: selectionStore,
      )(workspaceId: 'current', currentWorkspaceId: 'current');

      expect(snapshot.currentWorkspaceId, 'fallback');
      expect(selectionStore.currentWorkspaceId, 'fallback');
      expect(events, [
        'repository.remove:current',
        'repository.loadAll',
        'selection.save:fallback',
      ]);
    },
  );

  test('forget non-current workspace does not rewrite selection', () async {
    final events = <String>[];
    final repository = _MemoryWorkspaceRepository(events, [
      _workspace('current'),
      _workspace('other'),
    ]);
    final selectionStore = _MemoryWorkspaceSelectionStore(
      events,
      currentWorkspaceId: 'current',
    );

    final snapshot = await ForgetWorkspace(
      repository: repository,
      selectionStore: selectionStore,
    )(workspaceId: 'other', currentWorkspaceId: 'current');

    expect(snapshot.currentWorkspaceId, 'current');
    expect(selectionStore.currentWorkspaceId, 'current');
    expect(events, ['repository.remove:other', 'repository.loadAll']);
  });
}

Workspace _workspace(String id, {int openCount = 0}) {
  final now = DateTime.utc(2026, 8, 22);
  return Workspace(
    id: id,
    path: '/tmp/$id',
    name: id,
    openCount: openCount,
    createdAt: now,
    lastUsedAt: now,
  );
}

final class _MemoryWorkspaceRepository implements WorkspaceRepository {
  _MemoryWorkspaceRepository(
    this.events,
    List<Workspace> workspaces, {
    Workspace? addedWorkspace,
  }) : workspaces = List.of(workspaces),
       addedWorkspace = addedWorkspace ?? _workspace('added');

  final List<String> events;
  final Workspace addedWorkspace;
  List<Workspace> workspaces;

  @override
  Future<List<Workspace>> loadAll() async {
    events.add('repository.loadAll');
    return List.of(workspaces);
  }

  @override
  Future<Workspace?> findById(String workspaceId) async {
    for (final workspace in workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return null;
  }

  @override
  Future<Workspace> add(String path) async {
    events.add('repository.add:$path');
    workspaces = [addedWorkspace, ...workspaces];
    return addedWorkspace;
  }

  @override
  Future<Workspace> recordOpened(String path) async {
    events.add('repository.recordOpened:$path');
    return addedWorkspace;
  }

  @override
  Future<void> select(String workspaceId) async {
    events.add('repository.select:$workspaceId');
  }

  @override
  Future<void> rename({
    required String workspaceId,
    required String name,
  }) async {
    events.add('repository.rename:$workspaceId:$name');
  }

  @override
  Future<void> remove(String workspaceId) async {
    events.add('repository.remove:$workspaceId');
    workspaces = workspaces.where((item) => item.id != workspaceId).toList();
  }
}

final class _MemoryWorkspaceSelectionStore implements WorkspaceSelectionStore {
  _MemoryWorkspaceSelectionStore(this.events, {this.currentWorkspaceId});

  final List<String> events;
  String? currentWorkspaceId;

  @override
  Future<String?> loadCurrentWorkspaceId() async {
    events.add('selection.load');
    return currentWorkspaceId;
  }

  @override
  Future<void> saveCurrentWorkspaceId(String? workspaceId) async {
    events.add('selection.save:${workspaceId ?? 'null'}');
    currentWorkspaceId = workspaceId;
  }
}
