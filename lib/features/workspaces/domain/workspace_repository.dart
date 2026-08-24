import 'package:multi_cli_ai/features/workspaces/domain/workspace.dart';

abstract interface class WorkspaceRepository {
  Future<List<Workspace>> loadAll();

  Future<Workspace?> findById(String workspaceId);

  Future<Workspace> add(String path);

  Future<Workspace> recordOpened(String path);

  Future<void> select(String workspaceId);

  Future<void> rename({required String workspaceId, required String name});

  Future<void> remove(String workspaceId);
}

abstract interface class WorkspaceSelectionStore {
  Future<String?> loadCurrentWorkspaceId();

  Future<void> saveCurrentWorkspaceId(String? workspaceId);
}
