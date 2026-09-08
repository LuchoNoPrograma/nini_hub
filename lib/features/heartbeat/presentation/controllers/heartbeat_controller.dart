import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/features/heartbeat/application/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_failure.dart';
import 'package:nini_hub/features/heartbeat/presentation/state/heartbeat_state.dart';

typedef HeartbeatRunner =
    Future<HeartbeatRunResult> Function({
      required String profileId,
      int? expectedWindowMinutes,
    });
typedef HeartbeatControllerDependenciesBuilder =
    HeartbeatControllerDependencies Function(
      Ref<HeartbeatPresentationState> ref,
    );

final class HeartbeatControllerDependencies {
  const HeartbeatControllerDependencies({required this.runHeartbeat});

  final HeartbeatRunner runHeartbeat;
}

final class HeartbeatController extends Notifier<HeartbeatPresentationState> {
  factory HeartbeatController({required RunHeartbeat runHeartbeat}) =>
      HeartbeatController.composed(
        (_) => HeartbeatControllerDependencies(runHeartbeat: runHeartbeat.call),
      );

  HeartbeatController.composed(this._buildDependencies);

  final HeartbeatControllerDependenciesBuilder _buildDependencies;
  late HeartbeatControllerDependencies _dependencies;
  int _generation = 0;

  @override
  HeartbeatPresentationState build() {
    final buildGeneration = ++_generation;
    ref.onDispose(() {
      if (_generation == buildGeneration) _generation++;
    });
    _dependencies = _buildDependencies(ref);
    return HeartbeatPresentationState();
  }

  Future<bool> run({
    required String profileId,
    int? expectedWindowMinutes,
  }) async {
    if (state.isRunningProfile(profileId)) return false;
    final generation = _generation;
    _begin(profileId);
    try {
      final result = await _dependencies.runHeartbeat(
        profileId: profileId,
        expectedWindowMinutes: expectedWindowMinutes,
      );
      if (generation != _generation) return false;
      if (!result.commandSucceeded) {
        _complete(
          profileId,
          result: result,
          failure: HeartbeatOperationFailure(
            cause: result,
            message: result.message,
          ),
        );
        return false;
      }
      _complete(profileId, result: result);
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      _complete(
        profileId,
        failure: HeartbeatOperationFailure(
          cause: error,
          message: _failureMessage(error),
        ),
      );
      return false;
    }
  }

  void clearFailure(String profileId) {
    if (!state.failuresByProfile.containsKey(profileId)) return;
    final failures = Map<String, HeartbeatOperationFailure>.of(
      state.failuresByProfile,
    )..remove(profileId);
    state = state.copyWith(failuresByProfile: failures);
  }

  void _begin(String profileId) {
    final running = Set<String>.of(state.runningProfileIds)..add(profileId);
    final failures = Map<String, HeartbeatOperationFailure>.of(
      state.failuresByProfile,
    )..remove(profileId);
    state = state.copyWith(
      runningProfileIds: running,
      failuresByProfile: failures,
    );
  }

  void _complete(
    String profileId, {
    HeartbeatRunResult? result,
    HeartbeatOperationFailure? failure,
  }) {
    final running = Set<String>.of(state.runningProfileIds)..remove(profileId);
    final results = Map<String, HeartbeatRunResult>.of(state.resultsByProfile);
    if (result != null) results[profileId] = result;
    final failures = Map<String, HeartbeatOperationFailure>.of(
      state.failuresByProfile,
    );
    if (failure == null) {
      failures.remove(profileId);
    } else {
      failures[profileId] = failure;
    }
    state = state.copyWith(
      runningProfileIds: running,
      resultsByProfile: results,
      failuresByProfile: failures,
    );
  }

  static String _failureMessage(Object error) => switch (error) {
    HeartbeatProfileNotFoundFailure() =>
      'El perfil ya no está disponible en este equipo.',
    HeartbeatUnsupportedProviderFailure() =>
      'El heartbeat sólo está disponible para Codex.',
    HeartbeatProfileUnavailableFailure() =>
      'La cuenta debe estar disponible y vinculada.',
    HeartbeatAppliedFailure(progress: HeartbeatAppliedProgress.usageRead) =>
      'El heartbeat terminó, pero no se pudo guardar o mostrar la actualización de datos.',
    HeartbeatAppliedFailure() =>
      'El heartbeat se aplicó, pero no se pudo registrar la actividad.',
    _ => 'No se pudo completar el heartbeat.',
  };
}
