import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/heartbeat/data/heartbeat_state_mapper.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';

void main() {
  group('HeartbeatStateMapper', () {
    test('reads the existing version 2 shape and UTC dates', () {
      final state = HeartbeatStateMapper.fromJsonString(
        jsonEncode({
          'version': 2,
          'observation': {
            'limitId': 'codex',
            'usedPercent': 0,
            'windowDurationMinutes': 10080,
            'resetsAt': '2026-08-29T12:00:00-04:00',
            'observedAt': '2026-08-22T12:00:00-04:00',
            'accountEmail': ' Account@Example.com ',
            'planType': 'Pro',
          },
          'status': 'verified',
          'message': 'ok',
          'lastAttemptAt': '2026-08-22T12:01:00-04:00',
          'lastSuccessAt': '2026-08-22T12:02:00-04:00',
          'verifiedResetAt': '2026-08-29T12:00:00-04:00',
          'retryAfter': '2026-08-22T12:15:00-04:00',
          'retryCount': 2,
        }),
      );

      expect(state.status, HeartbeatStatus.verified);
      expect(state.message, 'ok');
      expect(state.retryCount, 2);
      expect(state.observation?.observedAt.isUtc, isTrue);
      expect(state.observation?.resetsAt?.isUtc, isTrue);
      expect(state.observation?.windowType, isEmpty);
      expect(state.lastAttemptAt?.isUtc, isTrue);
      expect(state.lastSuccessAt?.isUtc, isTrue);
      expect(state.verifiedResetAt?.isUtc, isTrue);
      expect(state.retryAfter?.isUtc, isTrue);
      expect(
        state.effectiveVerifiedIdentity?.accountEmail,
        'account@example.com',
      );
      expect(state.effectiveVerifiedIdentity?.planType, 'pro');
    });

    test('writes a legacy-readable version 2 payload', () {
      final now = DateTime.utc(2026, 8, 22, 12);
      final observation = HeartbeatObservation(
        limitId: 'codex',
        windowType: 'primary',
        usedPercent: 0,
        windowDurationMinutes: 10080,
        resetsAt: now.add(const Duration(days: 7)),
        observedAt: now,
        accountEmail: 'account@example.com',
        planType: 'pro',
      );
      final state = HeartbeatState(
        observation: observation,
        status: HeartbeatStatus.probeFailed,
        message: 'offline',
        lastAttemptAt: now,
        lastSuccessAt: now.subtract(const Duration(days: 1)),
        verifiedResetAt: now.add(const Duration(days: 7)),
        verifiedIdentity: observation.identity,
        retryAfter: now.add(const Duration(minutes: 15)),
        retryCount: 1,
      );

      final value =
          jsonDecode(HeartbeatStateMapper.toJsonString(state))
              as Map<String, dynamic>;

      expect(value['version'], 2);
      expect(value['status'], 'probe_failed');
      expect(value['lastAttemptAt'], now.toIso8601String());
      expect(
        value['retryAfter'],
        now.add(const Duration(minutes: 15)).toIso8601String(),
      );
      expect(value, isNot(contains('verifiedIdentity')));
      expect(
        (value['observation'] as Map<String, dynamic>)['observedAt'],
        now.toIso8601String(),
      );
      expect(
        (value['observation'] as Map<String, dynamic>)['windowType'],
        'primary',
      );
    });

    test('malformed, non-map and future statuses fall back safely', () {
      final malformed = HeartbeatStateMapper.fromJsonString('{not-json');
      final nonMap = HeartbeatStateMapper.fromJsonString('[]');
      final future = HeartbeatStateMapper.fromJsonString(
        jsonEncode({'version': 9, 'status': 'future_status'}),
      );

      expect(malformed.status, HeartbeatStatus.unknown);
      expect(nonMap.status, HeartbeatStatus.unknown);
      expect(future.status, HeartbeatStatus.unknown);
      expect(
        jsonDecode(HeartbeatStateMapper.toJsonString(malformed))['version'],
        2,
      );
    });
  });
}
