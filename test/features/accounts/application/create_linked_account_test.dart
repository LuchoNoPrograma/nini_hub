import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/accounts/application/create_linked_account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_draft.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';

void main() {
  for (final method in AccountAuthMethod.values) {
    test('publishes only after $method confirms and session closes', () async {
      final f = _Fixture();
      final result = await f.create(
        _command,
        method: method,
        authenticate: (profile, session, selected) async {
          expect(selected, method);
          expect(f.events, ['prepare', 'start']);
          f.events.add('authenticated');
          return true;
        },
      );
      expect(result, _profile);
      expect(f.events, [
        'prepare',
        'start',
        'authenticated',
        'close',
        'publish',
      ]);
    });
  }
  for (final fails in [false, true]) {
    test(
      'cancellation/error ($fails) closes before discard and never publishes',
      () async {
        final f = _Fixture();
        final operation = f.create(
          _command,
          method: AccountAuthMethod.browser,
          authenticate: (_, _, _) async {
            if (fails) throw StateError('auth failure');
            return false;
          },
        );
        if (fails) {
          await expectLater(operation, throwsStateError);
        } else {
          expect(await operation, isNull);
        }
        expect(f.events, ['prepare', 'start', 'cancel', 'close', 'discard']);
      },
    );
  }
  test('start failure discards its owned draft', () async {
    final f = _Fixture()..startFails = true;
    await expectLater(f.run(), throwsStateError);
    expect(f.events, ['prepare', 'start', 'discard']);
  });
  test(
    'duplicate/ambiguous creation cannot delete an existing profile',
    () async {
      final f = _Fixture()..prepareFails = true;
      await expectLater(f.run(), throwsStateError);
      expect(f.events, ['prepare']);
    },
  );
  test(
    'cleanup failure is explicit and never reports cancellation as clean',
    () async {
      final f = _Fixture()..discardFails = true;
      await expectLater(
        f.run(success: false),
        throwsA(isA<AccountCreationCleanupFailure>()),
      );
      expect(f.events, ['prepare', 'start', 'cancel', 'close', 'discard']);
    },
  );
  test('cannot remove home while the writer may still be alive', () async {
    final f = _Fixture()..closeFails = true;
    await expectLater(
      f.run(success: false),
      throwsA(isA<AccountCreationCleanupFailure>()),
    );
    expect(f.events, ['prepare', 'start', 'cancel', 'close']);
  });
  test('confirmed access is preserved even if session close fails', () async {
    final f = _Fixture()..closeFails = true;
    await expectLater(
      f.run(),
      throwsA(isA<AccountCreationPublicationFailure>()),
    );
    expect(f.events, ['prepare', 'start', 'close', 'publish']);
  });
  test('publication failure preserves confirmed account', () async {
    final f = _Fixture()..publishFails = true;
    await expectLater(
      f.run(),
      throwsA(isA<AccountCreationPublicationFailure>()),
    );
    expect(f.events, ['prepare', 'start', 'close', 'publish']);
  });
  test('unsupported tools are rejected before provisioning', () async {
    final f = _Fixture();
    await expectLater(
      f.create(
        const CreateProfileCommand(
          toolKey: 'claude-cli',
          name: 'team',
          displayName: '',
        ),
        method: AccountAuthMethod.browser,
        authenticate: (_, _, _) async => true,
      ),
      throwsA(isA<UnsupportedProfileToolFailure>()),
    );
    expect(f.events, isEmpty);
  });
}

const _command = CreateProfileCommand(
  toolKey: 'codex',
  name: 'team',
  displayName: 'Team',
);
const _profile = Profile(
  id: 'draft',
  toolKey: 'codex',
  profileName: 'team',
  displayName: 'Team',
  profileHome: '/synthetic/team',
  source: ProfileSource.multiCli,
  kind: ProfileKind.shared,
  hasAuthFile: false,
  isAvailable: true,
  isFavorite: false,
);

class _Fixture
    implements
        ProfileDraftStore,
        ProfileDraft,
        AccountDeviceAuthGateway,
        AccountDeviceAuthSession {
  final events = <String>[];
  bool prepareFails = false,
      startFails = false,
      discardFails = false,
      closeFails = false,
      publishFails = false;
  CreateLinkedAccount get create =>
      CreateLinkedAccount(drafts: this, gateway: this);
  Future<Profile?> run({bool success = true}) => create(
    _command,
    method: AccountAuthMethod.deviceCode,
    authenticate: (_, _, _) async => success,
  );
  @override
  Future<ProfileDraft> prepare({
    required String toolKey,
    required ProfileName name,
    required String displayName,
    required ProfileSetupMode setupMode,
  }) async {
    events.add('prepare');
    if (prepareFails) throw StateError('prepare');
    return this;
  }

  @override
  Profile get profile => _profile;
  @override
  Future<Profile> publish() async {
    events.add('publish');
    if (publishFails) throw StateError('publish');
    return profile;
  }

  @override
  Future<void> discard() async {
    events.add('discard');
    if (discardFails) throw StateError('discard');
  }

  @override
  Future<AccountDeviceAuthSession> start(
    Profile profile, {
    AccountAuthMethod method = AccountAuthMethod.deviceCode,
  }) async {
    events.add('start');
    if (startFails) throw StateError('start');
    return this;
  }

  @override
  Future<void> cancel() async {
    events.add('cancel');
  }

  @override
  Future<void> close() async {
    events.add('close');
    if (closeFails) throw StateError('close');
  }

  @override
  Future<bool> waitForCompletion() async => true;
  @override
  String get verificationUrl => 'https://example.com';
  @override
  String get userCode => 'CODE';
}
