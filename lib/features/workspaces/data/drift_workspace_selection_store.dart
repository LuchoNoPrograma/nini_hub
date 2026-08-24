import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace_repository.dart';

final class DriftWorkspaceSelectionStore implements WorkspaceSelectionStore {
  const DriftWorkspaceSelectionStore(this._database);

  static const _settingKey = 'current_workspace_id';

  final AppDatabase _database;

  @override
  Future<String?> loadCurrentWorkspaceId() async {
    final storedId = await _database.setting(_settingKey);
    return storedId == null || storedId.trim().isEmpty ? null : storedId;
  }

  @override
  Future<void> saveCurrentWorkspaceId(String? workspaceId) =>
      _database.saveSetting(_settingKey, workspaceId ?? '');
}
