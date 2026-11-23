import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_failure.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';

/// Spends one quota reset of an account, once per user decision.
final class ConsumeResetCredit {
  const ConsumeResetCredit({
    required this.discovery,
    required this.consumer,
    required this.activity,
    required this.newAttemptId,
    this.operationGate,
  });

  final ProfileDiscovery discovery;
  final UsageResetCreditConsumer consumer;
  final UsageResetCreditActivityRecorder activity;
  final String Function() newAttemptId;
  final UsageOperationGate? operationGate;

  Future<ResetCreditOutcome> call(String profileId) async {
    Profile? profile;
    for (final candidate in await discovery.discover()) {
      if (candidate.id == profileId) {
        profile = candidate;
        break;
      }
    }
    if (profile == null) throw UsageProfileNotFoundFailure(profileId);
    if (!profile.isAvailable) {
      throw UsageProfileUnavailableFailure(
        profileId: profile.id,
        reason: profile.isDeactivated
            ? UsageProfileUnavailableReason.deactivated
            : UsageProfileUnavailableReason.unavailable,
      );
    }
    if (profileProviderOrNull(profile.toolKey)?.supportsResetCredits != true) {
      throw UsageUnsupportedProviderFailure(
        profileId: profile.id,
        toolKey: profile.toolKey,
      );
    }

    final selected = profile;
    final attemptId = newAttemptId();
    Future<ResetCreditOutcome> spend() =>
        consumer.consume(selected, attemptId: attemptId);
    try {
      final outcome = await (operationGate?.run(selected.id, spend) ?? spend());
      await _record(selected, outcome: outcome);
      return outcome;
    } on UsageResetCreditFailure catch (failure) {
      await _record(selected, errorMessage: failure.detail);
      rethrow;
    }
  }

  // The provider already answered; a log failure must not hide that answer.
  Future<void> _record(
    Profile profile, {
    ResetCreditOutcome? outcome,
    String? errorMessage,
  }) async {
    try {
      await activity.recordResetCredit(
        profile: profile,
        outcome: outcome,
        errorMessage: errorMessage,
      );
    } catch (_) {}
  }
}
