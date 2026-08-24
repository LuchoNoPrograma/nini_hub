import 'package:multi_cli_ai/features/workspaces/domain/workspace.dart';

enum WorkspaceOperation { load, add, select, rename, forget, launch }

final class WorkspaceState {
  WorkspaceState({
    List<Workspace> workspaces = const [],
    this.currentWorkspaceId,
    this.operation,
    this.errorMessage,
    this.failure,
  }) : workspaces = List.unmodifiable(workspaces);

  static const _unset = Object();

  final List<Workspace> workspaces;
  final String? currentWorkspaceId;
  final WorkspaceOperation? operation;
  final String? errorMessage;
  final Object? failure;

  bool get isBusy => operation != null;

  bool get isLaunching => operation == WorkspaceOperation.launch;

  Workspace? get currentWorkspace {
    for (final workspace in workspaces) {
      if (workspace.id == currentWorkspaceId) return workspace;
    }
    return null;
  }

  WorkspaceState copyWith({
    List<Workspace>? workspaces,
    Object? currentWorkspaceId = _unset,
    Object? operation = _unset,
    Object? errorMessage = _unset,
    Object? failure = _unset,
  }) => WorkspaceState(
    workspaces: workspaces ?? this.workspaces,
    currentWorkspaceId: identical(currentWorkspaceId, _unset)
        ? this.currentWorkspaceId
        : currentWorkspaceId as String?,
    operation: identical(operation, _unset)
        ? this.operation
        : operation as WorkspaceOperation?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    failure: identical(failure, _unset) ? this.failure : failure,
  );
}
