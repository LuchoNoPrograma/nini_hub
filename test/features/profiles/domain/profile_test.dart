import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_failure.dart';

void main() {
  test('profile names preserve the legacy validation contract', () {
    final longestName = List.filled(48, 'a').join();
    final tooLongName = List.filled(49, 'a').join();
    expect(ProfileName(' team_02 ').value, 'team_02');
    expect(ProfileName(longestName).value, longestName);

    for (final invalid in ['', '../team', 'team;rm', tooLongName]) {
      expect(
        () => ProfileName(invalid),
        throwsA(isA<InvalidProfileNameFailure>()),
      );
    }
  });

  test('profile exposes management and deactivation rules', () {
    final managed = _profile();
    final mainProfile = _profile(source: ProfileSource.defaultProfile);
    final deactivated = _profile(kind: ProfileKind.deactivated);

    expect(managed.isManagedByMultiCli, isTrue);
    expect(managed.isDeactivated, isFalse);
    expect(mainProfile.isManagedByMultiCli, isFalse);
    expect(deactivated.isDeactivated, isTrue);
  });

  test('display data trims aliases and falls back to the physical name', () {
    final profile = _profile();

    final aliased = profile.withDisplayData(
      displayName: '  Equipo  ',
      isFavorite: true,
    );
    final fallback = aliased.withDisplayData(
      displayName: '   ',
      isFavorite: false,
    );

    expect(aliased.displayName, 'Equipo');
    expect(aliased.isFavorite, isTrue);
    expect(fallback.displayName, profile.profileName);
    expect(fallback.isFavorite, isFalse);
  });
}

Profile _profile({
  ProfileSource source = ProfileSource.multiCli,
  ProfileKind kind = ProfileKind.full,
}) => Profile(
  id: 'profile-id',
  toolKey: 'codex',
  profileName: 'team',
  commandName: 'codex-team',
  displayName: 'Team',
  profileHome: '/profiles/codex/team',
  source: source,
  kind: kind,
  hasAuthFile: true,
  isAvailable: true,
  isFavorite: false,
);
