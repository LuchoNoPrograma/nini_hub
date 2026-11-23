import 'dart:async';
import 'dart:io';

import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_failure.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';
import 'package:nini_hub/providers/codex/codex_app_server_client.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';

final class CodexResetCreditConsumer implements UsageResetCreditConsumer {
  const CodexResetCreditConsumer.current(this._client);

  final CodexAppServerClient Function() _client;

  @override
  Future<ResetCreditOutcome> consume(
    Profile profile, {
    required String attemptId,
  }) async {
    UsageResetCreditFailure failure(
      UsageResetCreditFailureReason reason,
      String detail,
    ) => UsageResetCreditFailure(
      profileId: profile.id,
      reason: reason,
      detail: detail,
    );

    final String outcome;
    try {
      outcome = await _client().consumeResetCredit(
        profile,
        idempotencyKey: attemptId,
      );
    } on CodexResetCreditNotSent catch (error) {
      throw failure(UsageResetCreditFailureReason.notSent, error.message);
    } on ProcessException catch (error) {
      throw failure(UsageResetCreditFailureReason.notSent, error.message);
    } on TimeoutException {
      throw failure(
        UsageResetCreditFailureReason.outcomeUnknown,
        'Codex no respondió a tiempo.',
      );
    } on CodexAppServerFailure catch (error) {
      throw failure(switch (error.kind) {
        CodexAppServerFailureKind.rpc =>
          _authPattern.hasMatch(error.message)
              ? UsageResetCreditFailureReason.authRequired
              : UsageResetCreditFailureReason.rejected,
        CodexAppServerFailureKind.executableUnavailable ||
        CodexAppServerFailureKind.profileMissing =>
          UsageResetCreditFailureReason.notSent,
        // The request left this process and no verdict came back.
        _ => UsageResetCreditFailureReason.outcomeUnknown,
      }, error.message);
    }
    return switch (outcome) {
      'reset' => ResetCreditOutcome.reset,
      'nothingToReset' => ResetCreditOutcome.nothingToReset,
      'noCredit' => ResetCreditOutcome.noCredit,
      'alreadyRedeemed' => ResetCreditOutcome.alreadyRedeemed,
      _ => throw failure(
        UsageResetCreditFailureReason.outcomeUnknown,
        'Codex devolvió un resultado desconocido.',
      ),
    };
  }

  static final _authPattern = RegExp(
    r'not logged|login|required|unauthorized|authentication',
    caseSensitive: false,
  );
}
