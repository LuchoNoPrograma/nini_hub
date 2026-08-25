import 'package:nini_hub/features/profiles/domain/profile_failure.dart';

enum ProfileSource { defaultProfile, multiCli }

enum ProfileKind { base, full, shared, cli, isolated, deactivated }

enum ProfileSetupMode { full, shared, cli }

final class ProfileName {
  factory ProfileName(String raw) {
    final value = raw.trim();
    if (!_safeName.hasMatch(value)) {
      throw const InvalidProfileNameFailure();
    }
    return ProfileName._(value);
  }

  const ProfileName._(this.value);

  static final RegExp _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$');

  final String value;
}

final class Profile {
  const Profile({
    required this.id,
    required this.toolKey,
    required this.profileName,
    required this.displayName,
    required this.profileHome,
    required this.source,
    required this.kind,
    required this.hasAuthFile,
    required this.isAvailable,
    required this.isFavorite,
    this.commandName,
  });

  final String id;
  final String toolKey;
  final String profileName;
  final String? commandName;
  final String displayName;
  final String profileHome;
  final ProfileSource source;
  final ProfileKind kind;
  final bool hasAuthFile;
  final bool isAvailable;
  final bool isFavorite;

  bool get isManagedByMultiCli => source == ProfileSource.multiCli;

  bool get isDeactivated => kind == ProfileKind.deactivated;

  String normalizedDisplayName(String raw) {
    final value = raw.trim();
    return value.isEmpty ? profileName : value;
  }

  Profile withDisplayData({
    required String displayName,
    required bool isFavorite,
  }) => Profile(
    id: id,
    toolKey: toolKey,
    profileName: profileName,
    commandName: commandName,
    displayName: normalizedDisplayName(displayName),
    profileHome: profileHome,
    source: source,
    kind: kind,
    hasAuthFile: hasAuthFile,
    isAvailable: isAvailable,
    isFavorite: isFavorite,
  );
}
