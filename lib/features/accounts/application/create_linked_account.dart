import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_draft.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';

typedef AccountAuthenticationInteraction =
    Future<bool> Function(
      Profile profile,
      AccountDeviceAuthSession session,
      AccountAuthMethod method,
    );

final class AccountCreationCleanupFailure implements Exception {
  const AccountCreationCleanupFailure(this.profile, this.cause);
  final Profile profile;
  final Object cause;
}

final class AccountCreationPublicationFailure implements Exception {
  const AccountCreationPublicationFailure(this.profile, this.cause);
  final Profile profile;
  final Object cause;
}

/// Owns the provisional profile and session until authentication is confirmed.
final class CreateLinkedAccount {
  const CreateLinkedAccount({required this.drafts, required this.gateway});
  final ProfileDraftStore drafts;
  final AccountDeviceAuthGateway gateway;

  Future<Profile?> call(
    CreateProfileCommand command, {
    required AccountAuthMethod method,
    required AccountAuthenticationInteraction authenticate,
  }) async {
    final name = ProfileName(command.name);
    if (profileProviderOrNull(command.toolKey)?.supportsDeviceAuth != true) {
      throw UnsupportedProfileToolFailure(command.toolKey);
    }
    final draft = await drafts.prepare(
      toolKey: command.toolKey,
      name: name,
      displayName: command.displayName,
      setupMode: command.setupMode,
    );
    AccountDeviceAuthSession? session;
    var authenticated = false;
    Object? failure;
    Object? closeFailure;
    try {
      session = await gateway.start(draft.profile, method: method);
      authenticated = await authenticate(draft.profile, session, method);
    } catch (error) {
      failure = error;
    }
    // Stop the writer before deleting its home, including cancellation races.
    if (session != null) {
      try {
        if (!authenticated) {
          try {
            await session.cancel();
          } catch (_) {
            // Closing the writer is the final cancellation boundary.
          }
          await session.close();
        } else {
          await session.close();
        }
      } catch (error) {
        if (!authenticated) {
          // A failed close is not a safe boundary for removing files.
          throw AccountCreationCleanupFailure(draft.profile, error);
        }
        closeFailure = error;
      }
    }
    if (!authenticated) {
      try {
        await draft.discard();
      } catch (error) {
        throw AccountCreationCleanupFailure(draft.profile, error);
      }
      if (failure != null) throw failure;
      return null;
    }
    try {
      final published = await draft.publish();
      if (closeFailure != null) {
        throw AccountCreationPublicationFailure(published, closeFailure);
      }
      return published;
    } catch (error) {
      // A quota/read/UI failure must never delete a successfully linked account.
      throw AccountCreationPublicationFailure(draft.profile, error);
    }
  }
}
