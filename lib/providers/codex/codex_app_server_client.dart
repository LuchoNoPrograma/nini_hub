import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multi_cli_ai/core/process/process_runner.dart';
import 'package:multi_cli_ai/providers/codex/codex_app_server_models.dart';

class CodexAppServerClient {
  const CodexAppServerClient({
    this.executable = 'codex',
    this.timeout = const Duration(seconds: 15),
  });

  final String executable;
  final Duration timeout;

  Future<CodexRefreshResult> refresh(String profileHome) async {
    final started = DateTime.now().toUtc();
    _CodexRpcProcess? rpc;
    try {
      if (!Directory(profileHome).existsSync()) {
        return _failure(
          UsageCheckState.profileMissing,
          started,
          'PROFILE_MISSING',
          'La carpeta del perfil no existe.',
        );
      }
      rpc = await _CodexRpcProcess.start(
        executable: executable,
        profileHome: profileHome,
        requestTimeout: timeout,
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
    } on ProcessException catch (error) {
      return _failure(
        UsageCheckState.toolMissing,
        started,
        'CODEX_NOT_FOUND',
        _sanitize(error.message),
      );
    } on CodexRpcException catch (error) {
      final auth = RegExp(
        r'not logged|login|required|unauthorized|authentication',
        caseSensitive: false,
      ).hasMatch(error.message);
      return _failure(
        auth ? UsageCheckState.authRequired : UsageCheckState.error,
        started,
        auth ? 'AUTH_REQUIRED' : 'CODEX_RPC_ERROR',
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

  Future<CodexDeviceAuthSession> startDeviceAuth(String profileHome) async {
    final rpc = await _CodexRpcProcess.start(
      executable: executable,
      profileHome: profileHome,
      requestTimeout: timeout,
    );
    try {
      await rpc.initialize();
      final existing = await rpc.request('account/read', const {
        'refreshToken': false,
      });
      if (_hasAccount(existing)) {
        throw const CodexRpcException(
          'Este perfil ya tiene una sesión válida. Desvincúlalo en Codex antes de iniciar otro acceso.',
        );
      }
      final result = await rpc.request('account/login/start', const {
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
        throw const CodexRpcException(
          'Codex inició el acceso, pero no devolvió URL o identificador.',
        );
      }
      return CodexDeviceAuthSession._(
        rpc: rpc,
        loginId: loginId,
        verificationUrl: url,
        userCode: code ?? '',
      );
    } catch (_) {
      await rpc.close();
      rethrow;
    }
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

  static String _sanitize(String value) => value
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[REDACTADO]')
      .replaceAll(
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
          throw CodexRpcException(
            CodexAppServerClient._sanitize(completion.error!),
          );
        }
        return false;
      }

      // Older app-server versions did not always include `success`.
      final account = await _rpc.request('account/read', const {
        'refreshToken': true,
      });
      return CodexAppServerClient._hasAccount(account);
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

class CodexRpcException implements Exception {
  const CodexRpcException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _CodexRpcProcess {
  _CodexRpcProcess._(this.process, this.requestTimeout) {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: _handleDone);
    _stderrSubscription = process.stderr.transform(utf8.decoder).listen((_) {});
  }

  final Process process;
  final Duration requestTimeout;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<Map<String, dynamic>> _notifications =
      StreamController.broadcast();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  int _nextId = 1;
  bool _closed = false;

  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  static Future<_CodexRpcProcess> start({
    required String executable,
    required String profileHome,
    required Duration requestTimeout,
  }) async {
    final process = await Process.start(
      ProcessRunner.resolveExecutable(executable),
      const ['app-server', '--stdio'],
      workingDirectory: profileHome,
      environment: {...Platform.environment, 'CODEX_HOME': profileHome},
      includeParentEnvironment: true,
      runInShell: false,
    );
    return _CodexRpcProcess._(process, requestTimeout);
  }

  Future<void> initialize() async {
    await request('initialize', const {
      'clientInfo': {
        'name': 'multicli-ai',
        'title': 'MultiCLI AI',
        'version': '1.0.0',
      },
      'capabilities': null,
    });
  }

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    if (_closed) {
      throw const CodexRpcException('El proceso de Codex ya se cerró.');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final message = <String, Object?>{'id': id, 'method': method};
    if (params != null) message['params'] = params;
    process.stdin.writeln(jsonEncode(message));
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('$method agotó el tiempo de espera.');
      },
    );
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final message = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final id = message['id'];
    if (id is num && _pending.containsKey(id.toInt())) {
      final completer = _pending.remove(id.toInt())!;
      final error = message['error'];
      if (error != null) {
        final text = error is Map
            ? (error['message'] ?? error.toString()).toString()
            : error.toString();
        completer.completeError(CodexRpcException(text));
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
    if (message['method'] != null) _notifications.add(message);
  }

  void _handleDone() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const CodexRpcException(
            'Codex app-server terminó antes de responder.',
          ),
        );
      }
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const CodexRpcException(
            'Consulta cancelada al cerrar Codex app-server.',
          ),
        );
      }
    }
    _pending.clear();
    try {
      await process.stdin.close();
    } catch (_) {}
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    await _notifications.close();
  }
}
