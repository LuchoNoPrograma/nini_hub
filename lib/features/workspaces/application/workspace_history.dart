import 'package:nini_hub/features/workspaces/domain/workspace.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_failure.dart';
import 'package:nini_hub/features/workspaces/domain/workspace_repository.dart';

final class WorkspaceHistorySnapshot {
  WorkspaceHistorySnapshot({
    required List<Workspace> workspaces,
    required this.currentWorkspaceId,
  }) : workspaces = List.unmodifiable(workspaces);

  final List<Workspace> workspaces;
  final String? currentWorkspaceId;

  Workspace? get currentWorkspace {
    for (final workspace in workspaces) {
      if (workspace.id == currentWorkspaceId) return workspace;
    }
    return null;
  }
}

final class LoadWorkspaceHistory {
  const LoadWorkspaceHistory({
    required this.repository,
    required this.selectionStore,
  });

  final WorkspaceRepository repository;
  final WorkspaceSelectionStore selectionStore;

  Future<WorkspaceHistorySnapshot> call() async {
    final storedId = await selectionStore.loadCurrentWorkspaceId();
    final workspaces = await repository.loadAll();
    final currentId = workspaces.any((item) => item.id == storedId)
        ? storedId
        : workspaces.isEmpty
        ? null
        : workspaces.first.id;
    return WorkspaceHistorySnapshot(
      workspaces: workspaces,
      currentWorkspaceId: currentId,
    );
  }
}

final class AddWorkspace {
  const AddWorkspace({required this.repository, required this.selectionStore});

  final WorkspaceRepository repository;
  final WorkspaceSelectionStore selectionStore;

  Future<WorkspaceHistorySnapshot> call(String path) async {
    final workspace = await repository.add(path);
    await selectionStore.saveCurrentWorkspaceId(workspace.id);
    final workspaces = await repository.loadAll();
    return WorkspaceHistorySnapshot(
      workspaces: workspaces,
      currentWorkspaceId: workspace.id,
    );
  }
}

final class SelectWorkspace {
  const SelectWorkspace({
    required this.repository,
    required this.selectionStore,
  });

  final WorkspaceRepository repository;
  final WorkspaceSelectionStore selectionStore;

  Future<WorkspaceHistorySnapshot> call(String workspaceId) async {
    await repository.select(workspaceId);
    await selectionStore.saveCurrentWorkspaceId(workspaceId);
    final workspaces = await repository.loadAll();
    return WorkspaceHistorySnapshot(
      workspaces: workspaces,
      currentWorkspaceId: workspaceId,
    );
  }
}

final class RenameWorkspace {
  const RenameWorkspace({required this.repository});

  final WorkspaceRepository repository;

  Future<WorkspaceHistorySnapshot> call({
    required String workspaceId,
    required String name,
    required String? currentWorkspaceId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const InvalidWorkspaceNameFailure();
    }
    await repository.rename(workspaceId: workspaceId, name: normalizedName);
    final workspaces = await repository.loadAll();
    return WorkspaceHistorySnapshot(
      workspaces: workspaces,
      currentWorkspaceId: currentWorkspaceId,
    );
  }
}

final class ForgetWorkspace {
  const ForgetWorkspace({
    required this.repository,
    required this.selectionStore,
  });

  final WorkspaceRepository repository;
  final WorkspaceSelectionStore selectionStore;

  Future<WorkspaceHistorySnapshot> call({
    required String workspaceId,
    required String? currentWorkspaceId,
  }) async {
    await repository.remove(workspaceId);
    final workspaces = await repository.loadAll();
    var nextCurrentId = currentWorkspaceId;
    if (workspaceId == currentWorkspaceId) {
      nextCurrentId = workspaces.isEmpty ? null : workspaces.first.id;
      await selectionStore.saveCurrentWorkspaceId(nextCurrentId);
    }
    return WorkspaceHistorySnapshot(
      workspaces: workspaces,
      currentWorkspaceId: nextCurrentId,
    );
  }
}
