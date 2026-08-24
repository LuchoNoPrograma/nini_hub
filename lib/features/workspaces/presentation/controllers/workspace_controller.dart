import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_failure.dart';
import 'package:multi_cli_ai/features/workspaces/application/launch_agent.dart';
import 'package:multi_cli_ai/features/workspaces/application/workspace_history.dart';
import 'package:multi_cli_ai/features/workspaces/domain/agent_launcher.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace_failure.dart';
import 'package:multi_cli_ai/features/workspaces/presentation/state/workspace_state.dart';

typedef WorkspaceControllerDependenciesBuilder =
    WorkspaceControllerDependencies Function(Ref<WorkspaceState> ref);

final class WorkspaceControllerDependencies {
  const WorkspaceControllerDependencies({
    required this.loadWorkspaceHistory,
    required this.addWorkspace,
    required this.selectWorkspace,
    required this.renameWorkspace,
    required this.forgetWorkspace,
    required this.launchAgent,
  });

  final LoadWorkspaceHistory loadWorkspaceHistory;
  final AddWorkspace addWorkspace;
  final SelectWorkspace selectWorkspace;
  final RenameWorkspace renameWorkspace;
  final ForgetWorkspace forgetWorkspace;
  final LaunchAgent launchAgent;
}

final class WorkspaceController extends Notifier<WorkspaceState> {
  factory WorkspaceController({
    required LoadWorkspaceHistory loadWorkspaceHistory,
    required AddWorkspace addWorkspace,
    required SelectWorkspace selectWorkspace,
    required RenameWorkspace renameWorkspace,
    required ForgetWorkspace forgetWorkspace,
    required LaunchAgent launchAgent,
  }) => WorkspaceController.composed(
    (_) => WorkspaceControllerDependencies(
      loadWorkspaceHistory: loadWorkspaceHistory,
      addWorkspace: addWorkspace,
      selectWorkspace: selectWorkspace,
      renameWorkspace: renameWorkspace,
      forgetWorkspace: forgetWorkspace,
      launchAgent: launchAgent,
    ),
  );

  WorkspaceController.composed(this._buildDependencies);

  final WorkspaceControllerDependenciesBuilder _buildDependencies;
  late WorkspaceControllerDependencies _dependencies;

  @override
  WorkspaceState build() {
    _dependencies = _buildDependencies(ref);
    return WorkspaceState();
  }

  Future<bool> load() => _runSnapshot(
    WorkspaceOperation.load,
    _dependencies.loadWorkspaceHistory.call,
  );

  Future<bool> add(String path) => _runSnapshot(
    WorkspaceOperation.add,
    () => _dependencies.addWorkspace(path),
  );

  Future<bool> select(String workspaceId) => _runSnapshot(
    WorkspaceOperation.select,
    () => _dependencies.selectWorkspace(workspaceId),
  );

  Future<bool> rename({required String workspaceId, required String name}) =>
      _runSnapshot(
        WorkspaceOperation.rename,
        () => _dependencies.renameWorkspace(
          workspaceId: workspaceId,
          name: name,
          currentWorkspaceId: state.currentWorkspaceId,
        ),
      );

  Future<bool> forget(String workspaceId) => _runSnapshot(
    WorkspaceOperation.forget,
    () => _dependencies.forgetWorkspace(
      workspaceId: workspaceId,
      currentWorkspaceId: state.currentWorkspaceId,
    ),
  );

  Future<bool> launch({
    required String profileId,
    required String workspaceId,
  }) async {
    if (!_begin(WorkspaceOperation.launch)) return false;
    try {
      final result = await _dependencies.launchAgent(
        LaunchAgentCommand(profileId: profileId, workspaceId: workspaceId),
      );
      final workspaces = [
        result.workspace,
        ...state.workspaces.where((item) => item.id != result.workspace.id),
      ];
      state = WorkspaceState(
        workspaces: workspaces,
        currentWorkspaceId: result.workspace.id,
      );
      return true;
    } catch (error) {
      _completeFailure(error);
      return false;
    }
  }

  void clearFailure() {
    if (state.failure == null && state.errorMessage == null) return;
    state = state.copyWith(failure: null, errorMessage: null);
  }

  Future<bool> _runSnapshot(
    WorkspaceOperation operation,
    Future<WorkspaceHistorySnapshot> Function() action,
  ) async {
    if (!_begin(operation)) return false;
    try {
      final snapshot = await action();
      state = WorkspaceState(
        workspaces: snapshot.workspaces,
        currentWorkspaceId: snapshot.currentWorkspaceId,
      );
      return true;
    } catch (error) {
      _completeFailure(error);
      return false;
    }
  }

  bool _begin(WorkspaceOperation operation) {
    if (state.isBusy) return false;
    state = state.copyWith(
      operation: operation,
      failure: null,
      errorMessage: null,
    );
    return true;
  }

  void _completeFailure(Object error) {
    state = state.copyWith(
      operation: null,
      failure: error,
      errorMessage: _failureMessage(error),
    );
  }

  static String _failureMessage(Object error) => switch (error) {
    InvalidWorkspaceNameFailure() =>
      'El nombre del workspace no puede quedar vacío.',
    InvalidWorkspacePathFailure() => 'El workspace seleccionado ya no existe.',
    WorkspaceNotFoundFailure() =>
      'El workspace seleccionado ya no está disponible.',
    ProfileNotFoundFailure() => 'El perfil seleccionado ya no está disponible.',
    ProfileUnavailableFailure() =>
      'La cuenta seleccionada no está disponible para lanzar.',
    AgentLauncherFailure() => 'No se pudo abrir el agente en la terminal.',
    _ => 'No se pudo completar la operación.',
  };
}
