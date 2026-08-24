import 'dart:io';

import 'package:drift/drift.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/profiles/data/profile_mapper.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_ports.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ProfileDiscoveryService implements ProfileDiscovery {
  ProfileDiscoveryService(this.database);

  final AppDatabase database;
  final Uuid _uuid = const Uuid();
  Future<void> _discoveryTail = Future<void>.value();

  String get userHome =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  Future<String> profilesRoot() async {
    final configured = await database.setting('profiles_root_path');
    if (configured != null && configured.trim().isNotEmpty) {
      final raw = configured.trim();
      final expanded = raw == '~'
          ? userHome
          : raw.startsWith('~/') || raw.startsWith('~\\')
          ? p.join(userHome, raw.substring(2))
          : raw;
      return p.normalize(
        p.isAbsolute(expanded) ? expanded : p.absolute(expanded),
      );
    }
    final environment = Platform.environment['MULTICLI_HOME'];
    return p.normalize(
      p.absolute(
        environment?.trim().isNotEmpty == true
            ? environment!
            : p.join(userHome, 'MultiCliProfiles'),
      ),
    );
  }

  Future<List<CliProfile>> discoverProfiles() {
    final operation = _discoveryTail.then((_) => _discoverProfiles());
    _discoveryTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<List<Profile>> discover() async => (await discoverProfiles())
      .map(ProfileMapper.fromRow)
      .toList(growable: false);

  Future<List<CliProfile>> _discoverProfiles() async {
    final now = DateTime.now().toUtc();
    final root = await profilesRoot();
    final discovered = <_DiscoveredProfile>[];

    for (final provider in supportedProfileProviders) {
      if (provider.showsDefaultProfile) {
        discovered.add(
          _profile(
            provider: provider,
            name: 'principal',
            home: p.join(userHome, provider.defaultHomeName),
            source: 'default',
            type: 'base',
            command: provider.executable,
            display: '${provider.productName} principal',
          ),
        );
      }

      final providerRoot = Directory(p.join(root, provider.multiCliTool));
      if (await providerRoot.exists()) {
        final entries = await providerRoot
            .list(followLinks: false)
            .where((entry) => entry is Directory)
            .cast<Directory>()
            .toList();
        entries.sort((a, b) => a.path.compareTo(b.path));
        for (final directory in entries) {
          final name = p.basename(directory.path);
          if (name.startsWith('.')) continue;
          final type = await File(p.join(directory.path, '.shared')).exists()
              ? 'shared'
              : await File(p.join(directory.path, '.cli')).exists()
              ? 'cli'
              : 'full';
          discovered.add(
            _profile(
              provider: provider,
              name: name,
              home: directory.path,
              source: 'multicli',
              type: type,
              command: provider.commandName(name),
              display: _title(name),
            ),
          );
        }
      }
    }

    await database.transaction(() async {
      for (final provider in supportedProfileProviders) {
        await (database.update(database.cliProfiles)
              ..where((row) => row.toolKey.equals(provider.toolKey)))
            .write(const CliProfilesCompanion(isAvailable: Value(false)));
        await (database.update(database.cliProfiles)..where(
              (row) =>
                  row.toolKey.equals(provider.toolKey) &
                  row.profileSource.equals('multicli'),
            ))
            .write(
              const CliProfilesCompanion(
                profileType: Value('deactivated'),
                hasAuthFile: Value(false),
              ),
            );
      }
      for (final item in discovered) {
        final existingByPath =
            await (database.select(database.cliProfiles)
                  ..where((row) => row.profileHome.equals(item.profileHome)))
                .getSingleOrNull();
        final existingByIdentity =
            existingByPath ??
            await (database.select(database.cliProfiles)..where(
                  (row) =>
                      row.toolKey.equals(item.toolKey) &
                      row.profileName.equals(item.profileName) &
                      row.profileSource.equals(item.profileSource),
                ))
                .getSingleOrNull();
        final id = existingByIdentity?.id ?? _uuid.v4();
        await database
            .into(database.cliProfiles)
            .insertOnConflictUpdate(
              CliProfilesCompanion.insert(
                id: id,
                toolKey: Value(item.toolKey),
                profileName: item.profileName,
                commandName: Value(item.commandName),
                displayName:
                    existingByIdentity?.displayName ?? item.displayName,
                profileHome: item.profileHome,
                profileSource: item.profileSource,
                profileType: item.profileType,
                hasAuthFile: Value(item.hasAuthFile),
                isAvailable: Value(item.isAvailable),
                isFavorite: Value(existingByIdentity?.isFavorite ?? false),
                createdAt: existingByIdentity?.createdAt ?? now,
                lastDiscoveredAt: now,
                lastLaunchedAt: Value(existingByIdentity?.lastLaunchedAt),
              ),
            );
      }
    });

    final profiles =
        await (database.select(database.cliProfiles)..orderBy([
              (row) => OrderingTerm.desc(row.isFavorite),
              (row) => OrderingTerm.asc(row.toolKey),
              (row) => OrderingTerm.asc(row.displayName),
            ]))
            .get();
    return profiles.where((profile) {
      final provider = profileProviderOrNull(profile.toolKey);
      return provider?.showsProfileSource(profile.profileSource) ?? false;
    }).toList();
  }

  _DiscoveredProfile _profile({
    required ProfileProvider provider,
    required String name,
    required String home,
    required String source,
    required String type,
    required String command,
    required String display,
  }) {
    final normalized = p.normalize(p.absolute(home));
    return _DiscoveredProfile(
      toolKey: provider.toolKey,
      profileName: name,
      commandName: command,
      displayName: display,
      profileHome: normalized,
      profileSource: source,
      profileType: type,
      hasAuthFile: provider.credentialFiles.any(
        (fileName) => File(p.join(normalized, fileName)).existsSync(),
      ),
      isAvailable: Directory(normalized).existsSync(),
    );
  }

  static String _title(String input) => input
      .split(RegExp(r'[-_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

final class _DiscoveredProfile {
  const _DiscoveredProfile({
    required this.toolKey,
    required this.profileName,
    required this.commandName,
    required this.displayName,
    required this.profileHome,
    required this.profileSource,
    required this.profileType,
    required this.hasAuthFile,
    required this.isAvailable,
  });

  final String toolKey;
  final String profileName;
  final String? commandName;
  final String displayName;
  final String profileHome;
  final String profileSource;
  final String profileType;
  final bool hasAuthFile;
  final bool isAvailable;
}
