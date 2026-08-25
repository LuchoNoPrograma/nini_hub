import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_failure.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';

final class ExecuteHeartbeat {
  const ExecuteHeartbeat({
    required this.policy,
    required this.repository,
    required this.command,
    required this.probe,
    required this.scheduler,
    required this.clock,
    required this.delay,
    required this.activity,
    this.verificationDelay = const Duration(seconds: 5),
  });

  static const prompt =
      'Responde exactamente OK. No ejecutes comandos, no uses herramientas, '
      'no leas archivos y no hagas preguntas.';

  final HeartbeatPolicy policy;
  final HeartbeatStateRepository repository;
  final HeartbeatCommandGateway command;
  final HeartbeatQuotaProbe probe;
  final HeartbeatScheduler scheduler;
  final HeartbeatClock clock;
  final HeartbeatDelay delay;
  final HeartbeatActivityRecorder activity;
  final Duration verificationDelay;

  Future<HeartbeatRunResult> call({
    required Profile profile,
    required HeartbeatObservation? before,
    required int expectedWindowMinutes,
    required HeartbeatState previousState,
  }) async {
    final now = clock.nowUtc().toUtc();
    final retryCount = previousState.retryCount + 1;
    final retryAfter = now.add(policy.retryDelay(retryCount));
    await repository.save(
      profileId: profile.id,
      state: HeartbeatState(
        observation: before,
        status: HeartbeatStatus.running,
        message: 'Codex está procesando el heartbeat.',
        lastAttemptAt: now,
        lastSuccessAt: previousState.lastSuccessAt,
        verifiedResetAt: previousState.verifiedResetAt,
        verifiedIdentity: previousState.effectiveVerifiedIdentity,
        retryAfter: retryAfter,
        retryCount: retryCount,
      ),
    );

    HeartbeatCommandResult commandResult;
    try {
      commandResult = await command.execute(profile: profile, prompt: prompt);
    } catch (error) {
      return _recordCommandFailure(
        profile: profile,
        before: before,
        previousState: previousState,
        now: now,
        retryAfter: retryAfter,
        retryCount: retryCount,
        message: error.toString(),
      );
    }
    if (!commandResult.succeeded) {
      final message = commandResult.failureMessage.trim().isEmpty
          ? 'Codex no pudo completar el heartbeat.'
          : commandResult.failureMessage;
      return _recordCommandFailure(
        profile: profile,
        before: before,
        previousState: previousState,
        now: now,
        retryAfter: retryAfter,
        retryCount: retryCount,
        message: message,
      );
    }

    final verification = await _verify(profile, expectedWindowMinutes, now);
    if (!verification.verified) {
      final message =
          'Comando enviado; Codex respondió, pero todavía no se pudo '
          'confirmar el ciclo de ${_cycleDurationLabel(expectedWindowMinutes)}.';
      await repository.save(
        profileId: profile.id,
        state: HeartbeatState(
          observation: verification.observation ?? before,
          status: HeartbeatStatus.unverified,
          message: message,
          lastAttemptAt: now,
          lastSuccessAt: now,
          retryAfter: retryAfter,
          retryCount: retryCount,
        ),
      );
      scheduler.schedule(profile: profile, at: retryAfter);
      await _recordVerification(
        profile: profile,
        kind: HeartbeatActivityKind.unverified,
        message: message,
      );
      return HeartbeatRunResult(
        outcome: HeartbeatOutcome.unverified,
        message: message,
      );
    }

    final observation = verification.observation ?? before;
    final verifiedReset =
        observation?.resetsAt ??
        now.add(Duration(minutes: expectedWindowMinutes));
    final message =
        'Comando enviado y ciclo de '
        '${_cycleDurationLabel(expectedWindowMinutes)} confirmado con un '
        'ancla de reinicio estable.';
    await repository.save(
      profileId: profile.id,
      state: HeartbeatState(
        observation: observation,
        status: HeartbeatStatus.verified,
        message: message,
        lastAttemptAt: now,
        lastSuccessAt: now,
        verifiedResetAt: verifiedReset,
        verifiedIdentity: observation?.identity,
      ),
    );
    scheduler.schedule(
      profile: profile,
      at: verifiedReset.add(HeartbeatPolicy.resetProbeMargin),
    );
    await _recordVerification(
      profile: profile,
      kind: HeartbeatActivityKind.verified,
      message: message,
    );
    return HeartbeatRunResult(
      outcome: HeartbeatOutcome.verified,
      message: message,
      verifiedResetAt: verifiedReset,
    );
  }

  Future<HeartbeatRunResult> _recordCommandFailure({
    required Profile profile,
    required HeartbeatObservation? before,
    required HeartbeatState previousState,
    required DateTime now,
    required DateTime retryAfter,
    required int retryCount,
    required String message,
  }) async {
    await repository.save(
      profileId: profile.id,
      state: HeartbeatState(
        observation: before,
        status: HeartbeatStatus.failed,
        message: message,
        lastAttemptAt: now,
        lastSuccessAt: previousState.lastSuccessAt,
        verifiedResetAt: previousState.verifiedResetAt,
        verifiedIdentity: previousState.effectiveVerifiedIdentity,
        retryAfter: retryAfter,
        retryCount: retryCount,
      ),
    );
    scheduler.schedule(profile: profile, at: retryAfter);
    return HeartbeatRunResult(
      outcome: HeartbeatOutcome.failed,
      message: message,
    );
  }

  Future<HeartbeatVerification> _verify(
    Profile profile,
    int expectedWindowMinutes,
    DateTime now,
  ) async {
    try {
      if (verificationDelay > Duration.zero) {
        await delay.wait(const Duration(seconds: 2));
      }
      final first = await probe.probe(profile);
      if (verificationDelay > Duration.zero) {
        await delay.wait(verificationDelay);
      }
      final second = await probe.probe(profile);
      return policy.verify(
        first: first,
        second: second,
        expectedWindowMinutes: expectedWindowMinutes,
        now: now,
      );
    } catch (_) {
      return const HeartbeatVerification(verified: false);
    }
  }

  Future<void> _recordVerification({
    required Profile profile,
    required HeartbeatActivityKind kind,
    required String message,
  }) async {
    try {
      await activity.record(profile: profile, kind: kind, message: message);
    } catch (error) {
      throw HeartbeatAppliedFailure(
        profileId: profile.id,
        progress: HeartbeatAppliedProgress.verificationPersisted,
        cause: error,
      );
    }
  }
}

String _cycleDurationLabel(int minutes) {
  const minutesPerDay = Duration.hoursPerDay * Duration.minutesPerHour;
  if (minutes > 0 && minutes % minutesPerDay == 0) {
    final days = minutes ~/ minutesPerDay;
    return '$days ${days == 1 ? 'día' : 'días'}';
  }
  if (minutes > 0 && minutes % Duration.minutesPerHour == 0) {
    final hours = minutes ~/ Duration.minutesPerHour;
    return '$hours ${hours == 1 ? 'hora' : 'horas'}';
  }
  return '$minutes minutos';
}

final class ObserveHeartbeatUsage {
  const ObserveHeartbeatUsage({
    required this.policy,
    required this.repository,
    required this.history,
    required this.scheduler,
    required this.clock,
    required this.activity,
    required this.execute,
  });

  final HeartbeatPolicy policy;
  final HeartbeatStateRepository repository;
  final HeartbeatHistoryRepository history;
  final HeartbeatScheduler scheduler;
  final HeartbeatClock clock;
  final HeartbeatActivityRecorder activity;
  final ExecuteHeartbeat execute;

  Future<HeartbeatRunResult> call({
    required Profile profile,
    required UsageSnapshot snapshot,
  }) async {
    if (!scheduler.enabled || profile.toolKey != 'codex') {
      return const HeartbeatRunResult(
        outcome: HeartbeatOutcome.skipped,
        message: 'El inicio automático de ventanas está desactivado.',
      );
    }
    if (!scheduler.acquire(profile.id)) {
      return const HeartbeatRunResult(
        outcome: HeartbeatOutcome.skipped,
        message: 'Ya hay un heartbeat en curso para esta cuenta.',
      );
    }
    scheduler.cancel(profile.id);
    try {
      final stored = await repository.load(profile.id);
      if (snapshot.status != UsageRefreshStatus.success &&
          snapshot.status != UsageRefreshStatus.partial) {
        return recordProbeFailure(
          profile: profile,
          message:
              snapshot.errorMessage ?? 'No se pudo leer la cuota de Codex.',
          previousState: stored,
        );
      }
      final current = policy.observationFrom(snapshot);
      if (current == null) {
        scheduler.cancel(profile.id);
        await repository.save(
          profileId: profile.id,
          state: HeartbeatState(
            observation: stored.observation,
            status: HeartbeatStatus.unsupported,
            message:
                'La lectura actual no contiene una ventana semanal de Codex.',
            lastAttemptAt: stored.lastAttemptAt,
            lastSuccessAt: stored.lastSuccessAt,
            verifiedResetAt: stored.verifiedResetAt,
            verifiedIdentity: stored.effectiveVerifiedIdentity,
          ),
        );
        return const HeartbeatRunResult(
          outcome: HeartbeatOutcome.skipped,
          message: 'La cuenta no expone una ventana semanal en esta lectura.',
        );
      }

      var previous = stored.observation;
      if (policy.needsHistoricalObservation(state: stored, current: current)) {
        previous = await history.loadLatestBefore(
          profileId: profile.id,
          before: current.observedAt,
          expectedWindowMinutes: HeartbeatPolicy.weeklyMinutes,
        );
        if (previous != null &&
            !previous.identity.isCompatibleWith(current.identity)) {
          previous = null;
        }
      }
      final decision = policy.decide(
        state: stored,
        current: current,
        previous: previous,
        now: clock.nowUtc(),
      );
      return switch (decision) {
        SkipHeartbeatDecision() => _applySkip(profile, decision),
        ExecuteHeartbeatDecision() => execute(
          profile: profile,
          before: decision.before,
          expectedWindowMinutes: decision.expectedWindowMinutes,
          previousState: decision.state,
        ),
      };
    } finally {
      scheduler.release(profile.id);
    }
  }

  Future<HeartbeatRunResult> _applySkip(
    Profile profile,
    SkipHeartbeatDecision decision,
  ) async {
    await repository.save(profileId: profile.id, state: decision.state);
    final nextProbe = decision.nextProbeAt;
    if (nextProbe == null) {
      scheduler.cancel(profile.id);
    } else {
      scheduler.schedule(profile: profile, at: nextProbe);
    }
    return decision.result;
  }

  Future<HeartbeatRunResult> recordProbeFailure({
    required Profile profile,
    required String message,
    HeartbeatState? previousState,
    bool requireRetained = false,
  }) async {
    final stored = previousState ?? await repository.load(profile.id);
    if (!scheduler.enabled ||
        (requireRetained && !scheduler.isRetained(profile.id))) {
      return const HeartbeatRunResult(
        outcome: HeartbeatOutcome.skipped,
        message:
            'El scheduler de heartbeat ya no está activo para esta cuenta.',
      );
    }
    final now = clock.nowUtc().toUtc();
    final retryCount = stored.retryCount + 1;
    final retryAfter = now.add(policy.retryDelay(retryCount));
    await repository.save(
      profileId: profile.id,
      state: HeartbeatState(
        observation: stored.observation,
        status: HeartbeatStatus.probeFailed,
        message: message,
        lastAttemptAt: stored.lastAttemptAt,
        lastSuccessAt: stored.lastSuccessAt,
        verifiedResetAt: stored.verifiedResetAt,
        verifiedIdentity: stored.effectiveVerifiedIdentity,
        retryAfter: retryAfter,
        retryCount: retryCount,
      ),
    );
    scheduler.schedule(profile: profile, at: retryAfter);
    try {
      await activity.record(
        profile: profile,
        kind: HeartbeatActivityKind.probeFailure,
        message: message,
      );
    } catch (error) {
      throw HeartbeatAppliedFailure(
        profileId: profile.id,
        progress: HeartbeatAppliedProgress.statePersisted,
        cause: error,
      );
    }
    return HeartbeatRunResult(
      outcome: HeartbeatOutcome.failed,
      message: message,
    );
  }
}

final class RunHeartbeat {
  const RunHeartbeat({
    required this.discovery,
    required this.repository,
    required this.scheduler,
    required this.execute,
  });

  final ProfileDiscovery discovery;
  final HeartbeatStateRepository repository;
  final HeartbeatScheduler scheduler;
  final ExecuteHeartbeat execute;

  Future<HeartbeatRunResult> call({
    required String profileId,
    int? expectedWindowMinutes,
  }) async {
    if (!scheduler.enabled) {
      return const HeartbeatRunResult(
        outcome: HeartbeatOutcome.skipped,
        message: 'El inicio de ventanas está desactivado.',
      );
    }
    final profile = _findProfile(await discovery.discover(), profileId);
    _validateManualProfile(profile);
    if (!scheduler.acquire(profile.id)) {
      return const HeartbeatRunResult(
        outcome: HeartbeatOutcome.skipped,
        message: 'Ya hay un heartbeat en curso para esta cuenta.',
      );
    }
    try {
      final stored = await repository.load(profile.id);
      return execute(
        profile: profile,
        before: stored.observation,
        expectedWindowMinutes:
            expectedWindowMinutes ??
            stored.observation?.windowDurationMinutes ??
            HeartbeatPolicy.weeklyMinutes,
        previousState: stored,
      );
    } finally {
      scheduler.release(profile.id);
    }
  }
}

final class ProbeHeartbeat {
  const ProbeHeartbeat({
    required this.profiles,
    required this.probe,
    required this.scheduler,
    required this.observe,
  });

  final ProfileRepository profiles;
  final HeartbeatQuotaProbe probe;
  final HeartbeatScheduler scheduler;
  final ObserveHeartbeatUsage observe;

  Future<HeartbeatRunResult> call(String profileId) async {
    if (!scheduler.enabled || !scheduler.isRetained(profileId)) {
      return _disabledResult;
    }
    final profile = await profiles.findById(profileId);
    if (profile == null) throw HeartbeatProfileNotFoundFailure(profileId);
    _validateManualProfile(profile);
    try {
      final snapshot = await probe.probe(profile);
      if (!scheduler.enabled || !scheduler.isRetained(profileId)) {
        return _disabledResult;
      }
      return observe(profile: profile, snapshot: snapshot);
    } catch (error) {
      if (!scheduler.enabled || !scheduler.isRetained(profileId)) {
        return _disabledResult;
      }
      return observe.recordProbeFailure(
        profile: profile,
        message: error.toString(),
        requireRetained: true,
      );
    }
  }

  static const _disabledResult = HeartbeatRunResult(
    outcome: HeartbeatOutcome.skipped,
    message: 'El scheduler de heartbeat ya no está activo para esta cuenta.',
  );
}

Profile _findProfile(List<Profile> profiles, String profileId) {
  for (final profile in profiles) {
    if (profile.id == profileId) return profile;
  }
  throw HeartbeatProfileNotFoundFailure(profileId);
}

void _validateManualProfile(Profile profile) {
  if (profile.toolKey != 'codex') {
    throw HeartbeatUnsupportedProviderFailure(
      profileId: profile.id,
      toolKey: profile.toolKey,
    );
  }
  if (!profile.isAvailable) {
    throw HeartbeatProfileUnavailableFailure(
      profileId: profile.id,
      reason: profile.isDeactivated
          ? HeartbeatProfileUnavailableReason.deactivated
          : HeartbeatProfileUnavailableReason.unavailable,
    );
  }
  if (!profile.hasAuthFile) {
    throw HeartbeatProfileUnavailableFailure(
      profileId: profile.id,
      reason: HeartbeatProfileUnavailableReason.missingCredential,
    );
  }
}
