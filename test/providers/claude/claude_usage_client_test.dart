import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/usage/domain/usage.dart';
import 'package:nini_hub/providers/claude/claude_usage_client.dart';
import 'package:path/path.dart' as p;

final _now = DateTime.utc(2026, 10, 22, 4);

const _usage = {
  'five_hour': {
    'utilization': 21.0,
    'resets_at': '2026-10-22T06:50:00.234441+00:00',
    'locked_reason': null,
  },
  'seven_day': {
    'utilization': 85.0,
    'resets_at': '2026-10-24T06:00:00.234461+00:00',
    'locked_reason': null,
  },
  'seven_day_opus': null,
  'seven_day_sonnet': {
    'utilization': 40,
    'resets_at': '2026-10-24T06:00:00+00:00',
  },
};

const _profileBody = {
  'account': {'email': 'luis@example.com', 'display_name': 'Luis'},
  'organization': {'organization_type': 'claude_max'},
};

void main() {
  late Directory home;
  late Profile profile;

  setUp(() {
    home = Directory.systemTemp.createTempSync('nini-hub-claude-usage-');
    Directory(p.join(home.path, 'auth')).createSync();
    profile = Profile(
      id: 'luis',
      toolKey: 'claude-cli',
      profileName: 'luis',
      commandName: 'claude-cli-luis',
      displayName: 'Luis',
      profileHome: home.path,
      source: ProfileSource.multiCli,
      kind: ProfileKind.full,
      hasAuthFile: true,
      isAvailable: true,
      isFavorite: false,
    );
  });

  tearDown(() => home.deleteSync(recursive: true));

  void writeCredentials({
    required DateTime expiresAt,
    String? subscriptionType = 'pro',
    String? refreshToken = 'refresh',
    DateTime? refreshExpiresAt,
    String? loginEnded,
  }) {
    File(p.join(home.path, 'auth', '.credentials.json')).writeAsStringSync(
      jsonEncode({
        'claudeAiOauth': {
          'accessToken': 'secret-token',
          'refreshToken': ?refreshToken,
          'expiresAt': expiresAt.millisecondsSinceEpoch,
          'refreshTokenExpiresAt': ?refreshExpiresAt?.millisecondsSinceEpoch,
          'subscriptionType': ?subscriptionType,
          'loginEnded': ?loginEnded,
        },
      }),
    );
  }

  // Claude Code writes a renewed credential into the profile runtime.
  void writeRuntimeCredentials(String token, DateTime expiresAt) {
    final runtime = Directory(p.join(home.path, '.runtime'))
      ..createSync(recursive: true);
    File(p.join(runtime.path, '.credentials.json')).writeAsStringSync(
      jsonEncode({
        'claudeAiOauth': {
          'accessToken': token,
          'refreshToken': 'refresh-2',
          'expiresAt': expiresAt.millisecondsSinceEpoch,
        },
      }),
    );
  }

  ClaudeUsageClient client(
    Map<String, ClaudeHttpResponse> responses, {
    List<Map<String, String>>? sentHeaders,
  }) => ClaudeUsageClient(
    now: () => _now,
    httpGet: (uri, headers, _) async {
      sentHeaders?.add(headers);
      return responses[uri.path] ?? const ClaudeHttpResponse(404, '{}');
    },
  );

  test('maps five-hour and weekly quota like Codex windows', () async {
    writeCredentials(expiresAt: _now.add(const Duration(hours: 1)));
    final headers = <Map<String, String>>[];

    final snapshot = await client({
      '/api/oauth/usage': ClaudeHttpResponse(200, jsonEncode(_usage)),
      '/api/oauth/profile': ClaudeHttpResponse(200, jsonEncode(_profileBody)),
    }, sentHeaders: headers).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.success);
    expect(snapshot.planType, 'pro');
    expect(snapshot.accountEmail, 'luis@example.com');
    expect(snapshot.rateLimitsReadSucceeded, isTrue);
    expect(
      snapshot.windows.map(
        (w) =>
            (w.limitId, w.windowType, w.windowDurationMinutes, w.usedPercent),
      ),
      [
        ('claude', 'primary', 300, 21.0),
        ('claude', 'secondary', 10080, 85.0),
        ('claude-sonnet', 'secondary', 10080, 40.0),
      ],
    );
    expect(
      snapshot.windows.first.resetsAt,
      DateTime.utc(2026, 10, 22, 6, 50, 0, 234, 441),
    );
    expect(headers.first['Authorization'], 'Bearer secret-token');
    expect(headers.first['anthropic-beta'], 'oauth-2025-04-20');
  });

  test('a login Claude Code ended and cleared asks to relink', () async {
    File(p.join(home.path, 'auth', '.credentials.json')).writeAsStringSync(
      jsonEncode({
        'claudeAiOauth': {
          'accessToken': '',
          'refreshToken': '',
          'expiresAt': 0,
          'loginEnded': 'time_limit',
        },
      }),
    );

    final snapshot = await client(const {}).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.authRequired);
    expect(snapshot.errorCode, 'TOKEN_EXPIRED');
  });

  test(
    'falls back to the organization plan when credentials omit it',
    () async {
      writeCredentials(
        expiresAt: _now.add(const Duration(hours: 1)),
        subscriptionType: null,
      );

      final snapshot = await client({
        '/api/oauth/usage': ClaudeHttpResponse(200, jsonEncode(_usage)),
        '/api/oauth/profile': ClaudeHttpResponse(200, jsonEncode(_profileBody)),
      }).refresh(profile);

      expect(snapshot.planType, 'max');
    },
  );

  test(
    'renewable expired tokens wait for Claude Code without calling Claude',
    () async {
      writeCredentials(expiresAt: _now.subtract(const Duration(minutes: 1)));
      var calls = 0;

      final snapshot = await ClaudeUsageClient(
        now: () => _now,
        httpGet: (_, _, _) async {
          calls++;
          return const ClaudeHttpResponse(200, '{}');
        },
      ).refresh(profile);

      expect(calls, 0);
      expect(snapshot.status, UsageRefreshStatus.unavailable);
      expect(snapshot.errorCode, 'TOKEN_REFRESHABLE');
    },
  );

  test(
    'expired tokens are renewed through Claude Code before reading usage',
    () async {
      writeCredentials(expiresAt: _now.subtract(const Duration(minutes: 1)));
      final renewed = <String>[];
      final headers = <Map<String, String>>[];

      final snapshot = await ClaudeUsageClient(
        now: () => _now,
        renewSession: (profile) async {
          renewed.add(profile.id);
          writeRuntimeCredentials(
            'renewed-token',
            _now.add(const Duration(hours: 8)),
          );
          return true;
        },
        httpGet: (uri, sent, _) async {
          headers.add(sent);
          return uri.path == '/api/oauth/usage'
              ? ClaudeHttpResponse(200, jsonEncode(_usage))
              : const ClaudeHttpResponse(404, '{}');
        },
      ).refresh(profile);

      expect(renewed, ['luis']);
      expect(snapshot.status, UsageRefreshStatus.success);
      expect(headers.first['Authorization'], 'Bearer renewed-token');
    },
  );

  test(
    'a renewal that leaves the token expired keeps retrying later',
    () async {
      writeCredentials(expiresAt: _now.subtract(const Duration(minutes: 1)));
      var calls = 0;

      final snapshot = await ClaudeUsageClient(
        now: () => _now,
        renewSession: (_) async => null,
        httpGet: (_, _, _) async {
          calls++;
          return const ClaudeHttpResponse(200, '{}');
        },
      ).refresh(profile);

      expect(calls, 0);
      expect(snapshot.status, UsageRefreshStatus.unavailable);
      expect(snapshot.errorCode, 'TOKEN_REFRESHABLE');
    },
  );

  test('a renewal that reports no login asks to relink', () async {
    writeCredentials(expiresAt: _now.subtract(const Duration(minutes: 1)));

    final snapshot = await ClaudeUsageClient(
      now: () => _now,
      renewSession: (_) async => false,
      httpGet: (_, _, _) async => const ClaudeHttpResponse(200, '{}'),
    ).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.authRequired);
    expect(snapshot.errorCode, 'TOKEN_EXPIRED');
  });

  for (final (name, refreshExpiresAt, loginEnded) in [
    ('an expired refresh token', _now.subtract(const Duration(hours: 1)), null),
    ('a login Claude Code ended', null, 'time_limit'),
  ]) {
    test('$name asks to relink without trying to renew', () async {
      writeCredentials(
        expiresAt: loginEnded == null
            ? _now.subtract(const Duration(minutes: 1))
            : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        refreshExpiresAt: refreshExpiresAt,
        loginEnded: loginEnded,
      );
      var renewals = 0;

      final snapshot = await ClaudeUsageClient(
        now: () => _now,
        renewSession: (_) async {
          renewals++;
          return true;
        },
        httpGet: (_, _, _) async => const ClaudeHttpResponse(200, '{}'),
      ).refresh(profile);

      expect(renewals, 0);
      expect(snapshot.status, UsageRefreshStatus.authRequired);
      expect(snapshot.errorCode, 'TOKEN_EXPIRED');
    });
  }

  test(
    'expired tokens without a refresh token are reported without calling Claude',
    () async {
      writeCredentials(
        expiresAt: _now.subtract(const Duration(minutes: 1)),
        refreshToken: null,
      );
      var calls = 0;

      final snapshot = await ClaudeUsageClient(
        now: () => _now,
        httpGet: (_, _, _) async {
          calls++;
          return const ClaudeHttpResponse(200, '{}');
        },
      ).refresh(profile);

      expect(calls, 0);
      expect(snapshot.status, UsageRefreshStatus.authRequired);
      expect(snapshot.errorCode, 'TOKEN_EXPIRED');
    },
  );

  test('rejected tokens ask to relink', () async {
    writeCredentials(expiresAt: _now.add(const Duration(hours: 1)));

    final snapshot = await client({
      '/api/oauth/usage': const ClaudeHttpResponse(401, '{}'),
    }).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.authRequired);
    expect(snapshot.errorCode, 'TOKEN_INVALIDATED');
  });

  test('empty credential placeholders require linking', () async {
    File(p.join(home.path, 'auth', '.credentials.json')).writeAsStringSync('');

    final snapshot = await client(const {}).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.authRequired);
    expect(snapshot.errorCode, 'AUTH_REQUIRED');
  });

  test('network failures are reported as such', () async {
    writeCredentials(expiresAt: _now.add(const Duration(hours: 1)));

    final snapshot = await ClaudeUsageClient(
      now: () => _now,
      httpGet: (_, _, _) async =>
          throw const SocketException('Failed host lookup'),
    ).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.error);
    expect(snapshot.errorCode, 'NETWORK_ERROR');
  });

  test('prefers a credential pending reconciliation in the runtime', () async {
    writeCredentials(expiresAt: _now.subtract(const Duration(hours: 1)));
    final runtime = Directory(p.join(home.path, '.runtime'))..createSync();
    File(p.join(runtime.path, '.credentials.json')).writeAsStringSync(
      jsonEncode({
        'claudeAiOauth': {
          'accessToken': 'fresh-token',
          'expiresAt': _now
              .add(const Duration(hours: 8))
              .millisecondsSinceEpoch,
        },
      }),
    );
    final headers = <Map<String, String>>[];

    final snapshot = await client({
      '/api/oauth/usage': ClaudeHttpResponse(200, jsonEncode(_usage)),
    }, sentHeaders: headers).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.success);
    expect(headers.first['Authorization'], 'Bearer fresh-token');
  });

  test('a reconciled runtime link is not read twice', () async {
    writeCredentials(expiresAt: _now.add(const Duration(hours: 1)));
    final runtime = Directory(p.join(home.path, '.runtime'))..createSync();
    Link(
      p.join(runtime.path, '.credentials.json'),
    ).createSync(p.join(home.path, 'auth', '.credentials.json'));
    final headers = <Map<String, String>>[];

    await client({
      '/api/oauth/usage': ClaudeHttpResponse(200, jsonEncode(_usage)),
    }, sentHeaders: headers).refresh(profile);

    expect(headers.first['Authorization'], 'Bearer secret-token');
  });

  test('a missing profile endpoint still returns quota', () async {
    writeCredentials(expiresAt: _now.add(const Duration(hours: 1)));

    final snapshot = await client({
      '/api/oauth/usage': ClaudeHttpResponse(200, jsonEncode(_usage)),
    }).refresh(profile);

    expect(snapshot.status, UsageRefreshStatus.success);
    expect(snapshot.accountEmail, isNull);
    expect(snapshot.windows, hasLength(3));
  });
}
