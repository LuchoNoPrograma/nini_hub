import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:path/path.dart' as p;

final class ClaudeHttpResponse {
  const ClaudeHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

typedef ClaudeHttpGet =
    Future<ClaudeHttpResponse> Function(
      Uri uri,
      Map<String, String> headers,
      Duration timeout,
    );

/// Reads the subscription quota that Claude Code's `/usage` shows.
///
/// The token is read from the profile's own credential file and is never
/// refreshed here: Claude Code owns rotation, and refreshing from a second
/// process could invalidate a session that is running with that profile.
class ClaudeUsageClient {
  const ClaudeUsageClient({
    this.baseUrl = 'https://api.anthropic.com',
    this.timeout = const Duration(seconds: 15),
    this.httpGet,
    this.now,
  });

  final String baseUrl;
  final Duration timeout;
  final ClaudeHttpGet? httpGet;
  final DateTime Function()? now;

  static const primaryMinutes = 300;
  static const weeklyMinutes = 10080;

  Future<UsageSnapshot> refresh(Profile profile) async {
    final started = _now();
    UsageSnapshot failure(
      UsageRefreshStatus status,
      String code,
      String message,
    ) => UsageSnapshot(
      status: status,
      startedAt: started,
      completedAt: _now(),
      errorCode: code,
      errorMessage: message,
    );

    if (!Directory(profile.profileHome).existsSync()) {
      return failure(
        UsageRefreshStatus.profileMissing,
        'PROFILE_MISSING',
        'La carpeta del perfil no existe.',
      );
    }
    final credentials = _readCredentials(profile.profileHome);
    if (credentials == null) {
      return failure(
        UsageRefreshStatus.authRequired,
        'AUTH_REQUIRED',
        'Vincula la cuenta de Claude para consultar su uso.',
      );
    }
    final expiresAt = credentials.expiresAt;
    if (expiresAt != null &&
        !expiresAt.isAfter(_now()) &&
        credentials.hasRefreshToken) {
      // The session is still valid: Claude Code renews the access token the
      // next time the profile opens, and usage resumes from that file.
      return failure(
        UsageRefreshStatus.unavailable,
        'TOKEN_REFRESHABLE',
        'Claude Code renueva el acceso al abrir este perfil.',
      );
    }
    if (expiresAt != null && !expiresAt.isAfter(_now())) {
      return failure(
        UsageRefreshStatus.authRequired,
        'TOKEN_EXPIRED',
        'El acceso de Claude venció. Abre este perfil en Claude Code para renovarlo.',
      );
    }

    final headers = {
      'Authorization': 'Bearer ${credentials.accessToken}',
      'anthropic-beta': 'oauth-2025-04-20',
      'Accept': 'application/json',
    };
    try {
      final responses = await Future.wait([
        _get('/api/oauth/usage', headers),
        _get('/api/oauth/profile', headers),
      ]);
      final usage = responses[0];
      if (usage.statusCode == 401 || usage.statusCode == 403) {
        return failure(
          UsageRefreshStatus.authRequired,
          'TOKEN_INVALIDATED',
          'Claude rechazó la credencial del perfil. Vuelve a vincular la cuenta.',
        );
      }
      if (usage.statusCode == 429) {
        return failure(
          UsageRefreshStatus.unavailable,
          'RATE_LIMITED',
          'Claude limitó las consultas de uso. Intenta de nuevo en unos minutos.',
        );
      }
      if (usage.statusCode != 200) {
        return failure(
          UsageRefreshStatus.error,
          'HTTP_${usage.statusCode}',
          'Claude respondió ${usage.statusCode} al consultar el uso.',
        );
      }
      final windows = parseWindows(_decode(usage.body));
      final profileJson = responses[1].statusCode == 200
          ? _decode(responses[1].body)
          : const <String, dynamic>{};
      final account = _map(profileJson['account']);
      return UsageSnapshot(
        status: windows.isEmpty
            ? UsageRefreshStatus.partial
            : UsageRefreshStatus.success,
        startedAt: started,
        completedAt: _now(),
        planType:
            credentials.subscriptionType ??
            _planFromOrganization(_map(profileJson['organization'])),
        accountEmail: account['email'] as String?,
        accountDisplayName: account['display_name'] as String?,
        errorCode: windows.isEmpty ? 'PARTIAL_METADATA' : null,
        errorMessage: windows.isEmpty
            ? 'Claude no devolvió ventanas de uso.'
            : null,
        rateLimitsReadSucceeded: windows.isNotEmpty,
        windows: windows,
      );
    } on TimeoutException {
      return failure(
        UsageRefreshStatus.timeout,
        'TIMEOUT',
        'Claude no respondió a tiempo.',
      );
    } on SocketException catch (error) {
      return failure(
        UsageRefreshStatus.error,
        'NETWORK_ERROR',
        'Sin conexión con Claude: ${error.message}',
      );
    } on HttpException catch (error) {
      return failure(
        UsageRefreshStatus.error,
        'NETWORK_ERROR',
        'Sin conexión con Claude: ${error.message}',
      );
    } on FormatException {
      return failure(
        UsageRefreshStatus.error,
        'PROTOCOL_ERROR',
        'Claude devolvió una respuesta de uso que no se pudo leer.',
      );
    }
  }

  /// Maps `/api/oauth/usage` onto the same primary/weekly windows as Codex.
  static List<UsageQuotaWindow> parseWindows(Map<String, dynamic> json) {
    UsageQuotaWindow? window(
      String key, {
      required String limitId,
      String? limitName,
      required String windowType,
      required int minutes,
    }) {
      final raw = _map(json[key]);
      final utilization = raw['utilization'];
      if (utilization is! num) return null;
      final resetsAt = raw['resets_at'];
      return UsageQuotaWindow(
        limitId: limitId,
        limitName: limitName,
        windowType: windowType,
        usedPercent: utilization.toDouble(),
        windowDurationMinutes: minutes,
        resetsAt: resetsAt is String
            ? DateTime.tryParse(resetsAt)?.toUtc()
            : null,
        reachedType: raw['locked_reason'] as String?,
      );
    }

    return [
      ?window(
        'five_hour',
        limitId: 'claude',
        windowType: 'primary',
        minutes: primaryMinutes,
      ),
      ?window(
        'seven_day',
        limitId: 'claude',
        windowType: 'secondary',
        minutes: weeklyMinutes,
      ),
      // Model-specific weekly caps only appear on plans that enforce them.
      ?window(
        'seven_day_opus',
        limitId: 'claude-opus',
        limitName: 'Opus',
        windowType: 'secondary',
        minutes: weeklyMinutes,
      ),
      ?window(
        'seven_day_sonnet',
        limitId: 'claude-sonnet',
        limitName: 'Sonnet',
        windowType: 'secondary',
        minutes: weeklyMinutes,
      ),
    ];
  }

  Future<ClaudeHttpResponse> _get(String path, Map<String, String> headers) =>
      (httpGet ?? _ioGet)(Uri.parse('$baseUrl$path'), headers, timeout);

  DateTime _now() => (now?.call() ?? DateTime.now()).toUtc();

  static _ClaudeCredentials? _readCredentials(String profileHome) {
    // A regular file in the runtime is a credential Claude Code replaced
    // after an `exec` that Nini Agents has not reconciled yet: it is newer.
    final pending = p.join(profileHome, '.runtime', '.credentials.json');
    // Schema-v2 profiles keep credentials under auth/; legacy ones at the root.
    for (final path in [
      if (!FileSystemEntity.isLinkSync(pending)) pending,
      p.join(profileHome, 'auth', '.credentials.json'),
      p.join(profileHome, '.credentials.json'),
    ]) {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) continue;
      try {
        final oauth = _map(_decode(file.readAsStringSync())['claudeAiOauth']);
        final token = oauth['accessToken'];
        if (token is! String || token.isEmpty) continue;
        final expiresAt = oauth['expiresAt'];
        final refreshToken = oauth['refreshToken'];
        return _ClaudeCredentials(
          accessToken: token,
          hasRefreshToken: refreshToken is String && refreshToken.isNotEmpty,
          expiresAt: expiresAt is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  expiresAt.toInt(),
                  isUtc: true,
                )
              : null,
          subscriptionType: oauth['subscriptionType'] as String?,
        );
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  static String? _planFromOrganization(Map<String, dynamic> organization) {
    final type = organization['organization_type'];
    if (type is! String || type.isEmpty) return null;
    return type.startsWith('claude_') ? type.substring(7) : type;
  }

  static Map<String, dynamic> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Expected a JSON object');
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
}

final class _ClaudeCredentials {
  const _ClaudeCredentials({
    required this.accessToken,
    required this.hasRefreshToken,
    required this.expiresAt,
    required this.subscriptionType,
  });

  final String accessToken;
  final bool hasRefreshToken;
  final DateTime? expiresAt;
  final String? subscriptionType;
}

Future<ClaudeHttpResponse> _ioGet(
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return ClaudeHttpResponse(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}
