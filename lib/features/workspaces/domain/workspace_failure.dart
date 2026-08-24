sealed class WorkspaceFailure implements Exception {
  const WorkspaceFailure();
}

final class InvalidWorkspaceNameFailure extends WorkspaceFailure {
  const InvalidWorkspaceNameFailure();
}

final class InvalidWorkspacePathFailure extends WorkspaceFailure {
  const InvalidWorkspacePathFailure();
}

final class WorkspaceNotFoundFailure extends WorkspaceFailure {
  const WorkspaceNotFoundFailure();
}
