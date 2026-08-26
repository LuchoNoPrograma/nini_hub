import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nini_hub/core/process/process_runner.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/providers/codex/codex_app_server_models.dart';
import 'package:path/path.dart' as p;

final class CodexProcessLaunch {
  const CodexProcessLaunch({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
}

abstract interface class CodexProcessHandle {
  Stream<List<int>> get stdout;

  Stream<List<int>> get stderr;

  Future<int> get exitCode;

  int get pid;

  void writeLine(String value);

  Future<void> closeStdin();

  bool kill(ProcessSignal signal);
}

typedef CodexProcessStarter =
    Future<CodexProcessHandle> Function(CodexProcessLaunch launch);
typedef CodexProcessTreeTerminator = Future<void> Function(int pid);

class CodexAppServerClient {
  const CodexAppServerClient({
    this.executable = 'codex',
    this.niniAgentsExecutable = 'nini-agents',
    this.timeout = const Duration(seconds: 15),
    this.processStarter,
    this.processTreeTerminator,
    this.isWindows,
  });

  final String executable;
  final String niniAgentsExecutable;
  final Duration timeout;
  final CodexProcessStarter? processStarter;
  final CodexProcessTreeTerminator? processTreeTerminator;
  final bool? isWindows;

  Future<CodexRefreshResult> refresh(Profile profile) async {
    final started = DateTime.now().toUtc();
    _CodexRpcProcess? rpc;
    try {
      if (!Directory(profile.profileHome).existsSync()) {
        return _failure(
          UsageCheckState.profileMissing,
          started,
          'PROFILE_MISSING',
          'La carpeta del perfil no existe.',
        );
      }
      rpc = await _CodexRpcProcess.start(
        launch: _processLaunch(profile),
        requestTimeout: timeout,
        processStarter: processStarter,
        processTreeTerminator: processTreeTerminator,
        isWindows: isWindows ?? Platform.isWindows,
      );
      await rpc.initialize();
      final account = await rpc.request('account/read', const {
        'refreshToken': false,
      });
      if (!_hasAccount(account)) {
        return _failure(
          UsageCheckState.authRequired,
          started,
          'AUTH_REQUIRED',
          'Codex no confirmó una sesión válida para este perfil.',
        );
      }

      Map<String, dynamic>? limits;
      Map<String, dynamic>? usage;
      Object? limitsError;
      Object? usageError;
      await Future.wait([
        _requestMetadata(
          rpc,
          'account/rateLimits/read',
        ).then((value) => limits = value).catchError((Object error) {
          limitsError = error;
          return <String, dynamic>{};
        }),
        _requestMetadata(
          rpc,
          'account/usage/read',
        ).then((value) => usage = value).catchError((Object error) {
          usageError = error;
          return <String, dynamic>{};
        }),
      ]);

      final windows = parseQuotaWindows(limits ?? const {});
      final daily = _parseDailyUsage(usage ?? const {});
      final credits = _parseResetCredits(limits ?? const {});
      final identity = _parseIdentity(account);
      final plan = _firstString(
        [account, limits ?? const {}],
        const {'planType', 'plan_type', 'plan'},
      );
      final hasAnyMetadata = windows.isNotEmpty || daily.isNotEmpty;
      final metadataFailureCode = _metadataFailureCode(limitsError, usageError);
      final authenticationFailed =
          metadataFailureCode == 'TOKEN_EXPIRED' ||
          metadataFailureCode == 'TOKEN_INVALIDATED' ||
          metadataFailureCode == 'AUTH_REQUIRED';
      final partial =
          limitsError != null || usageError != null || !hasAnyMetadata;
      return CodexRefreshResult(
        state: authenticationFailed
            ? UsageCheckState.authRequired
            : partial
            ? UsageCheckState.partial
            : UsageCheckState.success,
        startedAt: started,
        completedAt: DateTime.now().toUtc(),
        planType: plan,
        accountEmail: identity.$1,
        accountDisplayName: identity.$2,
        rateLimitsReadSucceeded: limitsError == null,
        windows: windows,
        dailyUsage: daily,
        resetCredits: credits.$1,
        nextCreditExpiry: credits.$2,
        errorCode: metadataFailureCode ?? (partial ? 'PARTIAL_METADATA' : null),
        errorMessage: partial
            ? _joinErrors(limitsError, usageError, hasAnyMetadata)
            : null,
      );
    } on TimeoutException {
      return _failure(
        UsageCheckState.timeout,
        started,
        'TIMEOUT',
        'Codex no respondió dentro de ${timeout.inSeconds} segundos.',
      );
    } on ProcessException {
      return _failure(
        UsageCheckState.toolMissing,
        started,
        profile.source == ProfileSource.multiCli
            ? 'NINI_AGENTS_NOT_FOUND'
            : 'CODEX_NOT_FOUND',
        profile.source == ProfileSource.multiCli
            ? 'No se encontró el ejecutable de Nini Agents.'
            : 'No se encontró el ejecutable de Codex.',
      );
    } on CodexAppServerFailure catch (error) {
      final auth = RegExp(
        r'not logged|login|required|unauthorized|authentication',
        caseSensitive: false,
      ).hasMatch(error.message);
      if (error.kind == CodexAppServerFailureKind.timeout) {
        return _failure(
          UsageCheckState.timeout,
          started,
          error.code,
          error.message,
        );
      }
      return _failure(
        auth ? UsageCheckState.authRequired : UsageCheckState.error,
        started,
        auth ? 'AUTH_REQUIRED' : error.code,
        _sanitize(error.message),
      );
    } catch (error) {
      return _failure(
        UsageCheckState.error,
        started,
        'UNEXPECTED_ERROR',
        _sanitize(error.toString()),
      );
    } finally {
      await rpc?.close();
    }
  }

  Future<CodexDeviceAuthSession> startDeviceAuth(Profile profile) async {
    if (!Directory(profile.profileHome).existsSync()) {
      throw const CodexAppServerFailure(
        kind: CodexAppServerFailureKind.profileMissing,
        code: 'PROFILE_MISSING',
        message: 'La carpeta del perfil no existe.',
      );
    }
    _CodexRpcProcess? rpc;
    try {
      final startedRpc = await _CodexRpcProcess.start(
        launch: _processLaunch(profile),
        requestTimeout: timeout,
        processStarter: processStarter,
        processTreeTerminator: processTreeTerminator,
        isWindows: isWindows ?? Platform.isWindows,
      );
      rpc = startedRpc;
      await startedRpc.initialize();
      final result = await startedRpc.request('account/login/start', const {
        'type': 'chatgptDeviceCode',
      });
      final loginId = _firstString(
        [result],
        const {'loginId', 'login_id', 'id'},
      );
      final url = _firstString(
        [result],
        const {
          'verificationUrl',
          'verification_url',
          'authUrl',
          'auth_url',
          'url',
        },
      );
      final code = _firstString(
        [result],
        const {'userCode', 'user_code', 'code'},
      );
      if (loginId == null || url == null) {
        throw const CodexAppServerFailure(
          kind: CodexAppServerFailureKind.protocolViolation,
          code: 'CODEX_PROTOCOL_ERROR',
          message:
              'Codex inició el acceso, pero no devolvió URL o identificador.',
        );
      }
      return CodexDeviceAuthSession._(
        rpc: startedRpc,
        loginId: loginId,
        verificationUrl: url,
        userCode: code ?? '',
      );
    } on ProcessException catch (error) {
      throw CodexAppServerFailure(
        kind: CodexAppServerFailureKind.executableUnavailable,
        code: profile.source == ProfileSource.multiCli
            ? 'NINI_AGENTS_NOT_FOUND'
            : 'CODEX_NOT_FOUND',
        message: profile.source == ProfileSource.multiCli
            ? 'No se encontró el ejecutable de Nini Agents.'
            : 'No se encontró el ejecutable de Codex.',
        diagnostic: _sanitize(error.message),
      );
    } catch (_) {
      await rpc?.close();
      rethrow;
    }
  }

  CodexProcessLaunch _processLaunch(Profile profile) {
    final profileHome = p.normalize(p.absolute(profile.profileHome));
    if (profile.source == ProfileSource.defaultProfile) {
      return CodexProcessLaunch(
        executable: executable,
        arguments: const ['app-server', '--stdio'],
        workingDirectory: profileHome,
        environment: {'CODEX_HOME': profileHome},
      );
    }
    final provider = profileProvider(profile.toolKey);
    final toolDirectory = p.dirname(profileHome);
    if (p.basename(toolDirectory) != provider.multiCliTool) {
      throw const CodexAppServerFailure(
        kind: CodexAppServerFailureKind.protocolViolation,
        code: 'INVALID_PROFILE_HOME',
        message: 'La ubicación del perfil no coincide con su herramienta.',
      );
    }
    return CodexProcessLaunch(
      executable: niniAgentsExecutable,
      arguments: [
        'exec',
        provider.profileSpec(profile.profileName),
        '--',
        'app-server',
        '--stdio',
      ],
      workingDirectory: profileHome,
      environment: {'MULTICLI_HOME': p.dirname(toolDirectory)},
    );
  }

  static CodexRefreshResult _failure(
    UsageCheckState state,
    DateTime started,
    String code,
    String message,
  ) => CodexRefreshResult(
    state: state,
    startedAt: started,
    completedAt: DateTime.now().toUtc(),
    errorCode: code,
    errorMessage: message,
  );

  static Future<Map<String, dynamic>> _requestMetadata(
    _CodexRpcProcess rpc,
    String method,
  ) async {
    try {
      return await rpc.request(method);
    } catch (error) {
      if (!_isTransientMetadataError(error)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return rpc.request(method);
    }
  }

  static bool _isTransientMetadataError(Object? error) {
    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('error sending request') ||
        message.contains('connection reset') ||
        message.contains('connection refused') ||
        message.contains('temporary failure') ||
        message.contains('failed host lookup');
  }

  static String? _metadataFailureCode(Object? limits, Object? usage) {
    final message = '$limits\n$usage'.toLowerCase();
    if (message.contains('token_invalidated') ||
        message.contains('authentication token has been invalidated')) {
      return 'TOKEN_INVALIDATED';
    }
    if (message.contains('token_expired') ||
        message.contains('authentication token is expired')) {
      return 'TOKEN_EXPIRED';
    }
    if (message.contains('401 unauthorized')) return 'AUTH_REQUIRED';
    if (_isTransientMetadataError(limits) || _isTransientMetadataError(usage)) {
      return 'NETWORK_ERROR';
    }
    return null;
  }

  static bool _hasAccount(Map<String, dynamic> result) {
    if (result['account'] == null && result.containsKey('account')) {
      return false;
    }
    final status = _firstString([result], const {'status', 'authStatus'});
    if (status != null &&
        RegExp(r'logged.?out|unauth', caseSensitive: false).hasMatch(status)) {
      return false;
    }
    return result['account'] is Map ||
        _firstString([result], const {'email', 'accountId', 'planType'}) !=
            null;
  }

  static (String?, String?) _parseIdentity(Map<String, dynamic> result) {
    final email = _firstString([result], const {'email', 'accountEmail'});
    final name = _firstString(
      [result],
      const {'displayName', 'name', 'accountName'},
    );
    return (email, name);
  }

  static List<QuotaSnapshot> parseQuotaWindows(Map<String, dynamic> result) {
    final snapshots = <(String, Map<String, dynamic>)>[];
    final byId = result['rateLimitsByLimitId'];
    if (byId is Map) {
      for (final entry in byId.entries) {
        if (entry.value is Map) {
          snapshots.add((entry.key.toString(), _stringMap(entry.value as Map)));
        }
      }
    }
    final direct = result['rateLimits'];
    if (direct is Map) {
      final map = _stringMap(direct);
      if (map['primary'] is Map || map['secondary'] is Map) {
        snapshots.add(((map['limitId'] ?? 'codex').toString(), map));
      } else {
        for (final entry in map.entries) {
          if (entry.value is Map) {
            final candidate = _stringMap(entry.value as Map);
            if (candidate['primary'] is Map || candidate['secondary'] is Map) {
              snapshots.add((entry.key, candidate));
            }
          }
        }
      }
    }
    if (snapshots.isEmpty &&
        (result['primary'] is Map || result['secondary'] is Map)) {
      snapshots.add(((result['limitId'] ?? 'codex').toString(), result));
    }

    final output = <String, QuotaSnapshot>{};
    for (final item in snapshots) {
      for (final type in const ['primary', 'secondary']) {
        final raw = item.$2[type];
        if (raw is! Map) continue;
        final window = _stringMap(raw);
        final candidate = QuotaSnapshot(
          limitId: item.$1,
          limitName: item.$2['limitName']?.toString(),
          windowType: type,
          usedPercent: _number(window['usedPercent']),
          windowDurationMinutes: _integer(window['windowDurationMins']),
          resetsAt: _date(window['resetsAt'] ?? window['resetsAtIso']),
          reachedType: item.$2['rateLimitReachedType']?.toString(),
          planType: item.$2['planType']?.toString(),
        );
        final key = '${candidate.limitId.toLowerCase()}\u0000$type';
        final existing = output[key];
        if (existing == null ||
            _quotaCompleteness(candidate) > _quotaCompleteness(existing)) {
          output[key] = candidate;
        }
      }
    }
    final values = output.values.toList()
      ..sort(
        (a, b) => (a.windowDurationMinutes ?? 1 << 30).compareTo(
          b.windowDurationMinutes ?? 1 << 30,
        ),
      );
    return values;
  }

  static int _quotaCompleteness(QuotaSnapshot value) => [
    value.limitName,
    value.usedPercent,
    value.windowDurationMinutes,
    value.resetsAt,
    value.reachedType,
    value.planType,
  ].where((item) => item != null).length;

  static List<DailyUsageSnapshot> _parseDailyUsage(
    Map<String, dynamic> result,
  ) {
    Object? raw = result['dailyUsageBuckets'];
    raw ??= result['daily_usage_buckets'];
    if (raw == null && result['usage'] is Map) {
      raw = (result['usage'] as Map)['dailyUsageBuckets'];
    }
    if (raw is! List) return const [];
    final output = <DailyUsageSnapshot>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final bucket = _stringMap(item);
      final day = _date(
        bucket['startDate'] ??
            bucket['date'] ??
            bucket['day'] ??
            bucket['startTime'],
      );
      // Only explicit provider totals are accepted. Component sums are not
      // reconstructed because fields can be cumulative or overlapping.
      final tokens = _integer(bucket['totalTokens'] ?? bucket['tokens']);
      if (day == null || tokens == null || tokens < 0) continue;
      output.add(
        DailyUsageSnapshot(
          day: DateTime.utc(day.year, day.month, day.day),
          tokens: tokens,
          activeMinutes: _integer(bucket['activeMinutes']),
          messageCount: _integer(bucket['messageCount']),
          source: 'account/usage/read',
        ),
      );
    }
    return output;
  }

  static (int, DateTime?) _parseResetCredits(Map<String, dynamic> result) {
    final raw = result['rateLimitResetCredits'];
    if (raw is! Map) return (0, null);
    final map = _stringMap(raw);
    final count = _integer(map['availableCount']) ?? 0;
    final expiries = <DateTime>[];
    if (map['credits'] is List) {
      for (final item in map['credits'] as List) {
        if (item is! Map) continue;
        final credit = _stringMap(item);
        if ((credit['status']?.toString().toLowerCase() ?? '') != 'available') {
          continue;
        }
        final expiry = _date(credit['expiresAt']);
        if (expiry != null) expiries.add(expiry);
      }
    }
    expiries.sort();
    return (count, expiries.firstOrNull);
  }

  static String _joinErrors(Object? limits, Object? usage, bool hasMetadata) {
    final messages = <String>[];
    if (limits != null) {
      messages.add('Límites: ${_sanitize(limits.toString())}');
    }
    if (usage != null) {
      messages.add('Uso diario: ${_sanitize(usage.toString())}');
    }
    if (!hasMetadata && messages.isEmpty) {
      messages.add(
        'Codex confirmó la cuenta, pero no expuso límites ni uso diario.',
      );
    }
    return messages.join(' · ');
  }

  static String? _firstString(
    List<Map<String, dynamic>> roots,
    Set<String> keys,
  ) {
    String? visit(Object? value, int depth) {
      if (depth > 8) return null;
      if (value is Map) {
        for (final entry in value.entries) {
          if (keys.contains(entry.key.toString()) && entry.value != null) {
            final text = entry.value.toString().trim();
            if (text.isNotEmpty && text != 'null') return text;
          }
        }
        for (final child in value.values) {
          final found = visit(child, depth + 1);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final child in value) {
          final found = visit(child, depth + 1);
          if (found != null) return found;
        }
      }
      return null;
    }

    for (final root in roots) {
      final found = visit(root, 0);
      if (found != null) return found;
    }
    return null;
  }

  static Map<String, dynamic> _stringMap(Map value) =>
      value.map((key, item) => MapEntry(key.toString(), item));

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static int? _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final milliseconds = value > 1000000000000
          ? value.toInt()
          : value.toInt() * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static String _sanitize(String value) =>
      ProcessRunner.sanitizeOutput(value).replaceAll(
        RegExp(r'bearer\s+[^\s]+', caseSensitive: false),
        'Bearer [REDACTADO]',
      );
}

class CodexDeviceAuthSession {
  CodexDeviceAuthSession._({
    required this._rpc,
    required this.loginId,
    required this.verificationUrl,
    required this.userCode,
  });

  final _CodexRpcProcess _rpc;
  final String loginId;
  final String verificationUrl;
  final String userCode;
  bool _closed = false;

  Future<bool> waitForCompletion({
    Duration timeout = const Duration(minutes: 10),
  }) async {
    try {
      final notification = await _rpc.notifications
          .firstWhere((item) {
            if (item['method'] != 'account/login/completed') return false;
            final params = item['params'];
            if (params is! Map) return true;
            final id = params['loginId'] ?? params['login_id'];
            return id == null || id.toString() == loginId;
          })
          .timeout(timeout);
      final completion = parseCompletionNotification(notification);
      if (completion.success == true) return true;
      if (completion.success == false) {
        if (completion.error != null) {
          throw CodexAppServerFailure(
            kind: CodexAppServerFailureKind.rpc,
            code: 'DEVICE_AUTH_FAILED',
            message: CodexAppServerClient._sanitize(completion.error!),
          );
        }
        return false;
      }

      // Older app-server versions did not always include `success`.
      final account = await _rpc.request('account/read', const {
        'refreshToken': true,
      });
      return CodexAppServerClient._hasAccount(account);
    } on TimeoutException {
      throw const CodexAppServerFailure(
        kind: CodexAppServerFailureKind.timeout,
        code: 'DEVICE_AUTH_TIMEOUT',
        message: 'Codex no confirmó el acceso dentro del tiempo disponible.',
      );
    } finally {
      await close();
    }
  }

  static ({bool? success, String? error}) parseCompletionNotification(
    Map<String, dynamic> notification,
  ) {
    final params = notification['params'];
    if (params is! Map) return (success: null, error: null);
    final success = params['success'];
    final rawError = params['error'];
    final error = rawError is String && rawError.trim().isNotEmpty
        ? rawError.trim()
        : null;
    return (success: success is bool ? success : null, error: error);
  }

  Future<void> cancel() async {
    if (_closed) return;
    try {
      await _rpc.request('account/login/cancel', {'loginId': loginId});
    } catch (_) {
      // Closing the owned app-server process is the final cancellation boundary.
    } finally {
      await close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _rpc.close();
  }
}

class _CodexRpcProcess {
  _CodexRpcProcess._({
    required this.process,
    required this.requestTimeout,
    required this.processTreeTerminator,
    required this.isWindows,
  }) {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleStreamError);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(_captureStderr, onError: (_) {});
    unawaited(process.exitCode.then(_handleExit, onError: _handleStreamError));
  }

  static const _stderrLimit = 4096;

  final CodexProcessHandle process;
  final Duration requestTimeout;
  final CodexProcessTreeTerminator processTreeTerminator;
  final bool isWindows;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<Map<String, dynamic>> _notifications =
      StreamController.broadcast();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  int _nextId = 1;
  bool _closed = false;
  bool _closing = false;
  String _stderr = '';
  CodexAppServerFailure? _terminalFailure;

  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  static Future<_CodexRpcProcess> start({
    required CodexProcessLaunch launch,
    required Duration requestTimeout,
    required CodexProcessStarter? processStarter,
    required CodexProcessTreeTerminator? processTreeTerminator,
    required bool isWindows,
  }) async {
    final process = await (processStarter ?? _startCodexProcess)(launch);
    return _CodexRpcProcess._(
      process: process,
      requestTimeout: requestTimeout,
      processTreeTerminator:
          processTreeTerminator ?? _terminateWindowsProcessTree,
      isWindows: isWindows,
    );
  }

  Future<void> initialize() async {
    await request('initialize', const {
      'clientInfo': {
        'name': 'nini-hub',
        'title': 'Nini Hub',
        'version': '1.0.0',
      },
      'capabilities': null,
    });
  }

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final terminalFailure = _terminalFailure;
    if (_closed || terminalFailure != null) {
      throw terminalFailure ??
          const CodexAppServerFailure(
            kind: CodexAppServerFailureKind.cancelled,
            code: 'CODEX_CANCELLED',
            message: 'El proceso de Codex ya se cerró.',
          );
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final message = <String, Object?>{'id': id, 'method': method};
    if (params != null) message['params'] = params;
    try {
      process.writeLine(jsonEncode(message));
    } catch (_) {
      _pending.remove(id);
      throw const CodexAppServerFailure(
        kind: CodexAppServerFailureKind.processExited,
        code: 'CODEX_PROCESS_EXITED',
        message: 'Codex app-server no aceptó la solicitud.',
      );
    }
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw CodexAppServerFailure(
          kind: CodexAppServerFailureKind.timeout,
          code: 'TIMEOUT',
          message: '$method agotó el tiempo de espera.',
        );
      },
    );
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      _fail(
        const CodexAppServerFailure(
          kind: CodexAppServerFailureKind.protocolViolation,
          code: 'CODEX_PROTOCOL_ERROR',
          message:
              'Codex app-server escribió una respuesta que no es JSON-RPC.',
        ),
      );
      return;
    }
    if (decoded is! Map) {
      _fail(
        const CodexAppServerFailure(
          kind: CodexAppServerFailureKind.protocolViolation,
          code: 'CODEX_PROTOCOL_ERROR',
          message: 'Codex app-server escribió un mensaje JSON-RPC inválido.',
        ),
      );
      return;
    }
    final message = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final id = message['id'];
    if (id is num) {
      final completer = _pending.remove(id.toInt());
      if (completer == null) return;
      final error = message['error'];
      if (error != null) {
        final text = error is Map
            ? (error['message'] ?? error.toString()).toString()
            : error.toString();
        completer.completeError(
          CodexAppServerFailure(
            kind: CodexAppServerFailureKind.rpc,
            code: 'CODEX_RPC_ERROR',
            message: CodexAppServerClient._sanitize(text),
          ),
        );
      } else {
        final result = message['result'];
        completer.complete(
          result is Map
              ? result.map((key, value) => MapEntry(key.toString(), value))
              : <String, dynamic>{'value': result},
        );
      }
      return;
    }
    if (message['method'] is String) {
      _notifications.add(message);
      return;
    }
    _fail(
      const CodexAppServerFailure(
        kind: CodexAppServerFailureKind.protocolViolation,
        code: 'CODEX_PROTOCOL_ERROR',
        message: 'Codex app-server escribió un mensaje JSON-RPC inválido.',
      ),
    );
  }

  void _captureStderr(String chunk) {
    final remaining = _stderrLimit - _stderr.length;
    if (remaining <= 0) return;
    _stderr += chunk.length <= remaining
        ? chunk
        : chunk.substring(0, remaining);
  }

  void _handleStreamError(Object _) {
    if (_closing) return;
    _fail(
      const CodexAppServerFailure(
        kind: CodexAppServerFailureKind.protocolViolation,
        code: 'CODEX_PROTOCOL_ERROR',
        message: 'Codex app-server cerró un canal con datos inválidos.',
      ),
    );
  }

  void _handleExit(int exitCode) {
    if (_closing) return;
    final detail = CodexAppServerClient._sanitize(_stderr).trim();
    _fail(
      CodexAppServerFailure(
        kind: CodexAppServerFailureKind.processExited,
        code: 'CODEX_PROCESS_EXITED',
        message: 'Codex app-server terminó antes de responder.',
        exitCode: exitCode,
        diagnostic: detail.isEmpty ? null : detail,
      ),
    );
  }

  void _fail(CodexAppServerFailure failure) {
    if (_terminalFailure != null || _closing) return;
    _terminalFailure = failure;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(failure);
      }
    }
    _pending.clear();
    if (!_notifications.isClosed) _notifications.addError(failure);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closing = true;
    const cancelled = CodexAppServerFailure(
      kind: CodexAppServerFailureKind.cancelled,
      code: 'CODEX_CANCELLED',
      message: 'Consulta cancelada al cerrar Codex app-server.',
    );
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(cancelled);
      }
    }
    _pending.clear();
    if (!_notifications.isClosed) _notifications.addError(cancelled);
    try {
      await process.closeStdin();
    } catch (_) {}
    if (!await _waitForExit(const Duration(milliseconds: 200))) {
      if (isWindows) {
        try {
          await processTreeTerminator(process.pid);
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
        }
      } else {
        process.kill(ProcessSignal.sigterm);
      }
      if (!await _waitForExit(const Duration(seconds: 2))) {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    await _notifications.close();
  }

  Future<bool> _waitForExit(Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }
}

Future<CodexProcessHandle> _startCodexProcess(
  CodexProcessLaunch launch,
) async => _IoCodexProcessHandle(
  await Process.start(
    ProcessRunner.resolveExecutable(launch.executable),
    launch.arguments,
    workingDirectory: launch.workingDirectory,
    environment: launch.environment,
    includeParentEnvironment: true,
    runInShell: false,
  ),
);

Future<void> _terminateWindowsProcessTree(int pid) async {
  await Process.run(ProcessRunner.resolveExecutable('taskkill'), [
    '/PID',
    '$pid',
    '/T',
    '/F',
  ], runInShell: false);
}

final class _IoCodexProcessHandle implements CodexProcessHandle {
  const _IoCodexProcessHandle(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> closeStdin() => _process.stdin.close();

  @override
  bool kill(ProcessSignal signal) => _process.kill(signal);

  @override
  void writeLine(String value) => _process.stdin.writeln(value);
}
