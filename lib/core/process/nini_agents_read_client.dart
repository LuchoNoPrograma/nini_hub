import 'dart:convert';

import 'package:nini_hub/core/process/process_runner.dart';

enum NiniAgentsReadFailureKind {
  executableUnavailable,
  timeout,
  process,
  malformedResponse,
  unsupportedSchema,
  protocolViolation,
  remote,
}

enum NiniAgentsMutationState { notApplied, partiallyApplied }

final class NiniAgentsReadFailure implements Exception {
  const NiniAgentsReadFailure({
    required this.kind,
    required this.command,
    required this.message,
    this.code,
    this.exitCode,
    this.mutationState,
  });

  final NiniAgentsReadFailureKind kind;
  final String command;
  final String message;
  final String? code;
  final int? exitCode;
  final NiniAgentsMutationState? mutationState;

  @override
  String toString() => 'NiniAgentsReadFailure($kind, $command, $code)';
}

final class NiniAgentsVersion {
  const NiniAgentsVersion({required this.product, required this.version});

  final String product;
  final String version;
}

final class NiniAgentsProfileSummary {
  const NiniAgentsProfileSummary({
    required this.tool,
    required this.name,
    required this.type,
    required this.schemaVersion,
    required this.sizeBytes,
  });

  final String tool;
  final String name;
  final String type;
  final int schemaVersion;
  final int sizeBytes;
}

final class NiniAgentsProfileList {
  const NiniAgentsProfileList({required this.command, required this.profiles});

  final String command;
  final List<NiniAgentsProfileSummary> profiles;

  int get count => profiles.length;
}

final class NiniAgentsToolSummary {
  const NiniAgentsToolSummary({
    required this.id,
    required this.kind,
    required this.strategy,
    required this.supportLevel,
    required this.installed,
  });

  final String id;
  final String kind;
  final String strategy;
  final String supportLevel;
  final bool installed;
}

final class NiniAgentsToolList {
  const NiniAgentsToolList({required this.platform, required this.tools});

  final String platform;
  final List<NiniAgentsToolSummary> tools;

  int get count => tools.length;
}

final class NiniAgentsProfileAddress {
  const NiniAgentsProfileAddress({required this.tool, required this.name});

  final String tool;
  final String name;
}

final class NiniAgentsProfileMutationSummary {
  const NiniAgentsProfileMutationSummary({
    required this.tool,
    required this.name,
    required this.type,
    required this.schemaVersion,
  });

  final String tool;
  final String name;
  final String type;
  final int schemaVersion;
}

final class NiniAgentsProfileMutationResult {
  const NiniAgentsProfileMutationResult({
    required this.command,
    required this.profile,
    this.from,
  });

  final String command;
  final NiniAgentsProfileAddress profile;
  final NiniAgentsProfileAddress? from;
}

final class NiniAgentsReadClient {
  NiniAgentsReadClient(
    this._runner, {
    this.executable = 'nini-agents',
    this.timeout = const Duration(seconds: 15),
    this.mutationTimeout = const Duration(minutes: 2),
  });

  static const schemaVersion = 1;

  final ProcessRunner _runner;
  final String executable;
  final Duration timeout;
  final Duration mutationTimeout;

  Future<NiniAgentsVersion> version() async {
    final data = await _query(command: 'version', recordActivity: false);
    final product = _requiredString(data, 'product', command: 'version');
    final version = _requiredString(data, 'version', command: 'version');
    if (product != 'nini-agents') {
      throw _protocolFailure(
        'version',
        'The JSON response belongs to an unexpected product.',
      );
    }
    return NiniAgentsVersion(product: product, version: version);
  }

  Future<NiniAgentsProfileList> list({String? tool, String? profilesRoot}) =>
      _profiles(command: 'list', tool: tool, profilesRoot: profilesRoot);

  Future<NiniAgentsProfileList> status({String? tool, String? profilesRoot}) =>
      _profiles(command: 'status', tool: tool, profilesRoot: profilesRoot);

  Future<NiniAgentsToolList> tools() async {
    const command = 'tools';
    final data = await _query(command: command, recordActivity: false);
    final platform = _requiredString(data, 'platform', command: command);
    if (platform != 'linux' && platform != 'windows') {
      throw _protocolFailure(
        command,
        'The JSON response contains an unsupported desktop platform.',
      );
    }
    final rawTools = _requiredList(data, 'tools', command: command);
    _validateCount(data, rawTools.length, command: command);
    final tools = rawTools
        .map((item) {
          final map = _requiredObject(item, command: command, label: 'tool');
          final installed = map['installed'];
          if (installed is! bool) {
            throw _protocolFailure(
              command,
              'A tool summary contains an invalid installed flag.',
            );
          }
          return NiniAgentsToolSummary(
            id: _requiredString(map, 'id', command: command),
            kind: _requiredString(map, 'kind', command: command),
            strategy: _requiredString(map, 'strategy', command: command),
            supportLevel: _requiredString(
              map,
              'supportLevel',
              command: command,
            ),
            installed: installed,
          );
        })
        .toList(growable: false);
    _validateSorted(
      tools.map((tool) => tool.id),
      command: command,
      label: 'tools',
    );
    return NiniAgentsToolList(
      platform: platform,
      tools: List.unmodifiable(tools),
    );
  }

  Future<NiniAgentsProfileMutationResult> createProfile({
    required String tool,
    required String name,
    required String setupMode,
    required bool seedFromBase,
    String? profilesRoot,
  }) async {
    const command = 'new';
    if (setupMode != 'full' && setupMode != 'shared' && setupMode != 'cli') {
      throw ArgumentError.value(
        setupMode,
        'setupMode',
        'Unsupported profile setup mode.',
      );
    }
    final profileSpec = _profileSpec(tool, name);
    final data = await _query(
      command: command,
      arguments: [
        profileSpec,
        if (setupMode == 'shared') '--shared',
        if (setupMode == 'cli') '--cli',
        if (!seedFromBase) '--no-seed',
      ],
      environment: _profilesEnvironment(profilesRoot),
      operationTimeout: mutationTimeout,
      summary: 'Crear perfil con Nini Agents',
    );
    _validateAppliedState(data, command: command);
    final profile = _mutationProfile(data['profile'], command: command);
    _validateAddress(
      profile.tool,
      profile.name,
      expectedTool: tool,
      expectedName: name,
      command: command,
    );
    return NiniAgentsProfileMutationResult(
      command: command,
      profile: NiniAgentsProfileAddress(tool: profile.tool, name: profile.name),
    );
  }

  Future<NiniAgentsProfileMutationResult> renameProfile({
    required String tool,
    required String currentName,
    required String newName,
    required String profileId,
    String? profilesRoot,
  }) async {
    const command = 'rename';
    final current = _profileSpec(tool, currentName);
    final target = _profileSpec(tool, newName);
    final data = await _query(
      command: command,
      arguments: [current, target],
      environment: _profilesEnvironment(profilesRoot),
      operationTimeout: mutationTimeout,
      summary: 'Renombrar perfil con Nini Agents',
      profileId: profileId,
    );
    _validateAppliedState(data, command: command);
    final from = _profileAddress(data['from'], command: command);
    final profile = _mutationProfile(data['profile'], command: command);
    _validateAddress(
      from.tool,
      from.name,
      expectedTool: tool,
      expectedName: currentName,
      command: command,
    );
    _validateAddress(
      profile.tool,
      profile.name,
      expectedTool: tool,
      expectedName: newName,
      command: command,
    );
    return NiniAgentsProfileMutationResult(
      command: command,
      from: from,
      profile: NiniAgentsProfileAddress(tool: profile.tool, name: profile.name),
    );
  }

  Future<NiniAgentsProfileMutationResult> deleteProfile({
    required String tool,
    required String name,
    required String profileId,
    String? profilesRoot,
  }) async {
    const command = 'delete';
    final profileSpec = _profileSpec(tool, name);
    final data = await _query(
      command: command,
      arguments: [profileSpec, '--confirm', profileSpec],
      environment: _profilesEnvironment(profilesRoot),
      operationTimeout: mutationTimeout,
      summary: 'Eliminar perfil con Nini Agents',
      profileId: profileId,
    );
    _validateAppliedState(data, command: command);
    final profile = _profileAddress(data['profile'], command: command);
    _validateAddress(
      profile.tool,
      profile.name,
      expectedTool: tool,
      expectedName: name,
      command: command,
    );
    return NiniAgentsProfileMutationResult(command: command, profile: profile);
  }

  Future<NiniAgentsProfileList> _profiles({
    required String command,
    String? tool,
    String? profilesRoot,
  }) async {
    final normalizedTool = tool?.trim();
    if (tool != null && normalizedTool!.isEmpty) {
      throw ArgumentError.value(tool, 'tool', 'Tool must not be empty.');
    }
    final normalizedRoot = profilesRoot?.trim();
    if (profilesRoot != null && normalizedRoot!.isEmpty) {
      throw ArgumentError.value(
        profilesRoot,
        'profilesRoot',
        'Profiles root must not be empty.',
      );
    }
    final data = await _query(
      command: command,
      arguments: [?normalizedTool],
      environment: normalizedRoot == null
          ? null
          : {'MULTICLI_HOME': normalizedRoot},
      recordActivity: false,
    );
    final rawProfiles = _requiredList(data, 'profiles', command: command);
    _validateCount(data, rawProfiles.length, command: command);
    final profiles = rawProfiles
        .map((item) {
          final map = _requiredObject(item, command: command, label: 'profile');
          final profileSchema = map['schemaVersion'];
          final sizeBytes = map['sizeBytes'];
          final type = _requiredString(map, 'type', command: command);
          if (profileSchema is! int ||
              (profileSchema != 1 && profileSchema != 2)) {
            throw _protocolFailure(
              command,
              'A profile summary contains an unsupported schema version.',
            );
          }
          if (sizeBytes is! int || sizeBytes < 0) {
            throw _protocolFailure(
              command,
              'A profile summary contains an invalid size.',
            );
          }
          if (!_profileTypes.contains(type)) {
            throw _protocolFailure(
              command,
              'A profile summary contains an unsupported type.',
            );
          }
          return NiniAgentsProfileSummary(
            tool: _requiredString(map, 'tool', command: command),
            name: _requiredString(map, 'name', command: command),
            type: type,
            schemaVersion: profileSchema,
            sizeBytes: sizeBytes,
          );
        })
        .toList(growable: false);
    _validateSorted(
      profiles.map((profile) => '${profile.tool}\u0000${profile.name}'),
      command: command,
      label: 'profiles',
    );
    return NiniAgentsProfileList(
      command: command,
      profiles: List.unmodifiable(profiles),
    );
  }

  Future<Map<String, dynamic>> _query({
    required String command,
    List<String> arguments = const [],
    Map<String, String>? environment,
    Duration? operationTimeout,
    String? summary,
    String? profileId,
    bool recordActivity = true,
  }) async {
    final result = await _runner.run(
      executable: executable,
      arguments: ['--json', command, ...arguments],
      summary: summary ?? 'Consultar Nini Agents: $command',
      profileId: profileId,
      environment: environment,
      timeout: operationTimeout ?? timeout,
      recordActivity: recordActivity,
    );
    if (result.timedOut) {
      throw NiniAgentsReadFailure(
        kind: NiniAgentsReadFailureKind.timeout,
        command: command,
        message: 'Nini Agents did not answer before the timeout.',
        exitCode: result.exitCode,
      );
    }
    if (result.stderr.trim().isNotEmpty) {
      throw NiniAgentsReadFailure(
        kind: result.exitCode == 127
            ? NiniAgentsReadFailureKind.executableUnavailable
            : NiniAgentsReadFailureKind.protocolViolation,
        command: command,
        message: result.exitCode == 127
            ? 'The Nini Agents executable is unavailable.'
            : 'The JSON transport wrote unexpected diagnostics to stderr.',
        exitCode: result.exitCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      throw NiniAgentsReadFailure(
        kind: result.exitCode == 0
            ? NiniAgentsReadFailureKind.malformedResponse
            : NiniAgentsReadFailureKind.process,
        command: command,
        message: 'Nini Agents returned an invalid JSON document.',
        exitCode: result.exitCode,
      );
    }
    final envelope = _requiredObject(
      decoded,
      command: command,
      label: 'envelope',
      malformed: true,
    );
    final responseSchema = envelope['schemaVersion'];
    if (responseSchema != schemaVersion) {
      throw NiniAgentsReadFailure(
        kind: NiniAgentsReadFailureKind.unsupportedSchema,
        command: command,
        message: 'The Nini Agents JSON schema is not supported.',
        exitCode: result.exitCode,
      );
    }
    if (envelope['command'] != command || envelope['ok'] is! bool) {
      throw _protocolFailure(
        command,
        'The JSON envelope does not match the requested command.',
        exitCode: result.exitCode,
      );
    }

    final ok = envelope['ok'] as bool;
    if (ok) {
      if (result.exitCode != 0 || envelope['error'] != null) {
        throw _protocolFailure(
          command,
          'A successful JSON envelope has inconsistent process state.',
          exitCode: result.exitCode,
        );
      }
      return _requiredObject(envelope['data'], command: command, label: 'data');
    }

    if (result.exitCode == 0 || envelope['data'] != null) {
      throw _protocolFailure(
        command,
        'A failed JSON envelope has inconsistent process state.',
        exitCode: result.exitCode,
      );
    }
    final error = _requiredObject(
      envelope['error'],
      command: command,
      label: 'error',
    );
    final code = _requiredString(error, 'code', command: command);
    final message = _requiredString(error, 'message', command: command);
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(code)) {
      throw _protocolFailure(
        command,
        'The JSON error code is not machine-safe.',
        exitCode: result.exitCode,
      );
    }
    final mutationState = _mutationCommands.contains(command)
        ? _requiredMutationState(error, command: command)
        : null;
    throw NiniAgentsReadFailure(
      kind: NiniAgentsReadFailureKind.remote,
      command: command,
      code: code,
      message: message,
      exitCode: result.exitCode,
      mutationState: mutationState,
    );
  }

  static const _mutationCommands = {'new', 'rename', 'delete'};
  static const _profileTypes = {'full', 'shared', 'cli', 'isolated'};

  static Map<String, String>? _profilesEnvironment(String? profilesRoot) {
    final normalizedRoot = profilesRoot?.trim();
    if (profilesRoot == null) return null;
    if (normalizedRoot!.isEmpty) {
      throw ArgumentError.value(
        profilesRoot,
        'profilesRoot',
        'Profiles root must not be empty.',
      );
    }
    return {'MULTICLI_HOME': normalizedRoot};
  }

  static String _profileSpec(String tool, String name) {
    final normalizedTool = tool.trim();
    final normalizedName = name.trim();
    if (normalizedTool.isEmpty || normalizedName.isEmpty) {
      throw ArgumentError('Profile tool and name must not be empty.');
    }
    return '$normalizedTool/$normalizedName';
  }

  static void _validateAppliedState(
    Map<String, dynamic> data, {
    required String command,
  }) {
    if (data['state'] != 'applied') {
      throw _protocolFailure(
        command,
        'A successful mutation has an invalid state.',
      );
    }
  }

  static NiniAgentsProfileAddress _profileAddress(
    Object? value, {
    required String command,
  }) {
    final map = _requiredObject(value, command: command, label: 'profile');
    return NiniAgentsProfileAddress(
      tool: _requiredString(map, 'tool', command: command),
      name: _requiredString(map, 'name', command: command),
    );
  }

  static NiniAgentsProfileMutationSummary _mutationProfile(
    Object? value, {
    required String command,
  }) {
    final map = _requiredObject(value, command: command, label: 'profile');
    final type = _requiredString(map, 'type', command: command);
    final profileSchema = map['schemaVersion'];
    if (!_profileTypes.contains(type) ||
        profileSchema is! int ||
        (profileSchema != 1 && profileSchema != 2)) {
      throw _protocolFailure(command, 'A mutation profile summary is invalid.');
    }
    return NiniAgentsProfileMutationSummary(
      tool: _requiredString(map, 'tool', command: command),
      name: _requiredString(map, 'name', command: command),
      type: type,
      schemaVersion: profileSchema,
    );
  }

  static void _validateAddress(
    String tool,
    String name, {
    required String expectedTool,
    required String expectedName,
    required String command,
  }) {
    if (tool != expectedTool || name != expectedName) {
      throw _protocolFailure(
        command,
        'A mutation response addresses an unexpected profile.',
      );
    }
  }

  static NiniAgentsMutationState _requiredMutationState(
    Map<String, dynamic> error, {
    required String command,
  }) {
    final details = _requiredObject(
      error['details'],
      command: command,
      label: 'error details',
    );
    return switch (details['state']) {
      'not_applied' => NiniAgentsMutationState.notApplied,
      'partially_applied' => NiniAgentsMutationState.partiallyApplied,
      _ => throw _protocolFailure(
        command,
        'A mutation error contains an invalid state.',
      ),
    };
  }

  static Map<String, dynamic> _requiredObject(
    Object? value, {
    required String command,
    required String label,
    bool malformed = false,
  }) {
    if (value is Map<String, dynamic>) return value;
    throw NiniAgentsReadFailure(
      kind: malformed
          ? NiniAgentsReadFailureKind.malformedResponse
          : NiniAgentsReadFailureKind.protocolViolation,
      command: command,
      message: 'The JSON response contains an invalid $label.',
    );
  }

  static String _requiredString(
    Map<String, dynamic> map,
    String key, {
    required String command,
  }) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
    throw _protocolFailure(
      command,
      'The JSON response contains an invalid $key field.',
    );
  }

  static List<dynamic> _requiredList(
    Map<String, dynamic> map,
    String key, {
    required String command,
  }) {
    final value = map[key];
    if (value is List<dynamic>) return value;
    throw _protocolFailure(
      command,
      'The JSON response contains an invalid $key field.',
    );
  }

  static void _validateCount(
    Map<String, dynamic> data,
    int actual, {
    required String command,
  }) {
    final count = data['count'];
    if (count is! int || count < 0 || count != actual) {
      throw _protocolFailure(
        command,
        'The JSON response contains an inconsistent count.',
      );
    }
  }

  static void _validateSorted(
    Iterable<String> values, {
    required String command,
    required String label,
  }) {
    String? previous;
    for (final value in values) {
      if (previous != null && previous.compareTo(value) > 0) {
        throw _protocolFailure(
          command,
          'The JSON response contains unsorted $label.',
        );
      }
      previous = value;
    }
  }

  static NiniAgentsReadFailure _protocolFailure(
    String command,
    String message, {
    int? exitCode,
  }) => NiniAgentsReadFailure(
    kind: NiniAgentsReadFailureKind.protocolViolation,
    command: command,
    message: message,
    exitCode: exitCode,
  );
}
