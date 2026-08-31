import 'dart:io';

import 'package:drift/drift.dart';
import 'package:nini_hub/core/database/app_database.dart';
import 'package:nini_hub/core/process/nini_agents_read_client.dart';
import 'package:nini_hub/features/profiles/data/profile_mapper.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_ports.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ProfileDiscoveryService implements ProfileDiscovery {
  ProfileDiscoveryService(this.database, NiniAgentsReadClient client)
    : _client = client;

  ProfileDiscoveryService.test(this.database) : _client = null;

  final AppDatabase database;
  final NiniAgentsReadClient? _client;
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

  Future<List<CliProfile>> reconcileProfiles(
    NiniAgentsProfileList profiles,
  ) async {
    try {
      final tools = await _requiredClient.tools();
      return _synchronize(profiles: profiles, tools: tools);
    } on NiniAgentsReadFailure {
      throw const ProfileDiscoveryUnavailableFailure();
    }
  }

  @override
  Future<List<Profile>> discover() async => (await discoverProfiles())
      .map(ProfileMapper.fromRow)
      .toList(growable: false);

  NiniAgentsReadClient get _requiredClient =>
      _client ??
      (throw StateError('ProfileDiscoveryService requires Nini Agents.'));

  Future<List<CliProfile>> _discoverProfiles() async {
    try {
      final root = await profilesRoot();
      final profiles = await _requiredClient.list(profilesRoot: root);
      final tools = await _requiredClient.tools();
      return _synchronize(profiles: profiles, tools: tools, root: root);
    } on NiniAgentsReadFailure {
      throw const ProfileDiscoveryUnavailableFailure();
    }
  }

  Future<List<CliProfile>> _synchronize({
    required NiniAgentsProfileList profiles,
    required NiniAgentsToolList tools,
    String? root,
  }) async {
    final now = DateTime.now().toUtc();
    final profilesRootPath = root ?? await profilesRoot();
    final installedTools = {
      for (final tool in tools.tools) tool.id: tool.installed,
    };
    final discovered = <_DiscoveredProfile>[];

    for (final provider in supportedProfileProviders) {
      if (!provider.showsDefaultProfile) continue;
      discovered.add(
        _DiscoveredProfile(
          toolKey: provider.toolKey,
          profileName: 'principal',
          commandName: provider.executable,
          displayName: '${provider.productName} principal',
          profileHome: p.normalize(
            p.absolute(p.join(userHome, provider.defaultHomeName)),
          ),
          profileSource: 'default',
          profileType: 'base',
          hasAuthFile: null,
          isAvailable: installedTools[provider.multiCliTool] ?? false,
        ),
      );
    }

    for (final summary in profiles.profiles) {
      final provider = _providerForEngineTool(summary.tool);
      if (provider == null) continue;
      discovered.add(
        _DiscoveredProfile(
          toolKey: provider.toolKey,
          profileName: summary.name,
          commandName: provider.commandName(summary.name),
          displayName: _title(summary.name),
          profileHome: p.normalize(
            p.absolute(p.join(profilesRootPath, summary.tool, summary.name)),
          ),
          profileSource: 'multicli',
          profileType: summary.type,
          hasAuthFile: summary.hasAuthFile,
          isAvailable: true,
        ),
      );
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
              const CliProfilesCompanion(profileType: Value('deactivated')),
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
                hasAuthFile: Value(
                  item.hasAuthFile ?? existingByIdentity?.hasAuthFile ?? false,
                ),
                isAvailable: Value(item.isAvailable),
                isFavorite: Value(existingByIdentity?.isFavorite ?? false),
                createdAt: existingByIdentity?.createdAt ?? now,
                lastDiscoveredAt: now,
                lastLaunchedAt: Value(existingByIdentity?.lastLaunchedAt),
              ),
            );
      }
    });

    final storedProfiles =
        await (database.select(database.cliProfiles)..orderBy([
              (row) => OrderingTerm.desc(row.isFavorite),
              (row) => OrderingTerm.asc(row.toolKey),
              (row) => OrderingTerm.asc(row.displayName),
            ]))
            .get();
    return storedProfiles.where((profile) {
      final provider = profileProviderOrNull(profile.toolKey);
      return provider?.showsProfileSource(profile.profileSource) ?? false;
    }).toList();
  }

  static ProfileProvider? _providerForEngineTool(String tool) {
    for (final provider in supportedProfileProviders) {
      if (provider.multiCliTool == tool) return provider;
    }
    return null;
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
  final bool? hasAuthFile;
  final bool isAvailable;
}
