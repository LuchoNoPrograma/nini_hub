import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/usage/application/usage_reset_credit.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/features/usage/domain/usage_failure.dart';
import 'package:nini_hub/features/usage/domain/usage_ports.dart';

void main() {
  test(
    'spends one reset with a single attempt id and logs the outcome',
    () async {
      final fixture = _Fixture([_profile()]);

      final outcome = await fixture.useCase()('primary');

      expect(outcome, ResetCreditOutcome.reset);
      expect(fixture.events, [
        'consume:primary:attempt-1',
        'log:primary:reset',
      ]);
    },
  );

  test('a tool without resets is refused before anything is sent', () async {
    final fixture = _Fixture([_profile(toolKey: 'claude-cli')]);

    await expectLater(
      fixture.useCase()('primary'),
      throwsA(isA<UsageUnsupportedProviderFailure>()),
    );
    expect(fixture.events, isEmpty);
  });

  test('an unavailable or unknown profile sends nothing', () async {
    final fixture = _Fixture([_profile(isAvailable: false)]);

    await expectLater(
      fixture.useCase()('primary'),
      throwsA(isA<UsageProfileUnavailableFailure>()),
    );
    await expectLater(
      fixture.useCase()('other'),
      throwsA(isA<UsageProfileNotFoundFailure>()),
    );
    expect(fixture.events, isEmpty);
  });

  test('a provider failure is logged and reaches the caller', () async {
    final fixture = _Fixture([_profile()])
      ..failure = const UsageResetCreditFailure(
        profileId: 'primary',
        reason: UsageResetCreditFailureReason.outcomeUnknown,
        detail: 'sin respuesta',
      );

    await expectLater(
      fixture.useCase()('primary'),
      throwsA(isA<UsageResetCreditFailure>()),
    );
    expect(fixture.events, [
      'consume:primary:attempt-1',
      'log:primary:error:sin respuesta',
    ]);
  });

  test('a log failure does not hide a reset that was applied', () async {
    final fixture = _Fixture([_profile()])..logFails = true;

    expect(await fixture.useCase()('primary'), ResetCreditOutcome.reset);
  });
}

final class _Fixture
    implements
        ProfileDiscovery,
        UsageResetCreditConsumer,
        UsageResetCreditActivityRecorder {
  _Fixture(this.profiles);

  final List<Profile> profiles;
  final events = <String>[];
  UsageResetCreditFailure? failure;
  bool logFails = false;
  int _attempts = 0;

  ConsumeResetCredit useCase() => ConsumeResetCredit(
    discovery: this,
    consumer: this,
    activity: this,
    newAttemptId: () => 'attempt-${++_attempts}',
  );

  @override
  Future<List<Profile>> discover() async => List.of(profiles);

  @override
  Future<ResetCreditOutcome> consume(
    Profile profile, {
    required String attemptId,
  }) async {
    events.add('consume:${profile.id}:$attemptId');
    if (failure case final failure?) throw failure;
    return ResetCreditOutcome.reset;
  }

  @override
  Future<void> recordResetCredit({
    required Profile profile,
    required ResetCreditOutcome? outcome,
    String? errorMessage,
  }) async {
    if (logFails) throw StateError('log unavailable');
    events.add(
      outcome == null
          ? 'log:${profile.id}:error:$errorMessage'
          : 'log:${profile.id}:${outcome.name}',
    );
  }
}

Profile _profile({String toolKey = 'codex', bool isAvailable = true}) =>
    Profile(
      id: 'primary',
      toolKey: toolKey,
      profileName: 'primary',
      commandName: '$toolKey-primary',
      displayName: 'primary',
      profileHome: '/profiles/primary',
      source: ProfileSource.multiCli,
      kind: ProfileKind.full,
      hasAuthFile: true,
      isAvailable: isAvailable,
      isFavorite: false,
    );
