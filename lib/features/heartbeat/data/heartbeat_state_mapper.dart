import 'dart:convert';

import 'package:nini_hub/features/heartbeat/domain/heartbeat.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_policy.dart';

final class HeartbeatStateMapper {
  const HeartbeatStateMapper._();

  static HeartbeatState fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return HeartbeatState();
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? fromJson(value) : HeartbeatState();
    } catch (_) {
      return HeartbeatState();
    }
  }

  static String toJsonString(HeartbeatState state) => jsonEncode(toJson(state));

  static HeartbeatState fromJson(Map<String, dynamic> json) {
    final observationValue = json['observation'];
    final observation = observationValue is Map<String, dynamic>
        ? _observationFromJson(observationValue)
        : null;
    final verifiedResetAt = _date(json['verifiedResetAt']);
    return HeartbeatState(
      observation: observation,
      status: _statusFromStorage(json['status']),
      message: json['message'] as String? ?? '',
      lastAttemptAt: _date(json['lastAttemptAt']),
      lastSuccessAt: _date(json['lastSuccessAt']),
      verifiedResetAt: verifiedResetAt,
      verifiedIdentity: verifiedResetAt == null ? null : observation?.identity,
      retryAfter: _date(json['retryAfter']),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, Object?> toJson(HeartbeatState state) => {
    'version': 2,
    'observation': _observationToJson(state.observation),
    'status': _statusToStorage(state.status),
    'message': state.message,
    'lastAttemptAt': state.lastAttemptAt?.toUtc().toIso8601String(),
    'lastSuccessAt': state.lastSuccessAt?.toUtc().toIso8601String(),
    'verifiedResetAt': state.verifiedResetAt?.toUtc().toIso8601String(),
    'retryAfter': state.retryAfter?.toUtc().toIso8601String(),
    'retryCount': state.retryCount,
  };

  static HeartbeatObservation _observationFromJson(Map<String, dynamic> json) =>
      HeartbeatObservation(
        limitId: json['limitId'] as String? ?? 'codex',
        usedPercent: (json['usedPercent'] as num?)?.toDouble(),
        windowDurationMinutes:
            (json['windowDurationMinutes'] as num?)?.toInt() ??
            HeartbeatPolicy.weeklyMinutes,
        resetsAt: _date(json['resetsAt']),
        observedAt:
            _date(json['observedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        accountEmail: json['accountEmail'] as String?,
        planType: json['planType'] as String?,
      );

  static Map<String, Object?>? _observationToJson(
    HeartbeatObservation? observation,
  ) => observation == null
      ? null
      : {
          'limitId': observation.limitId,
          'usedPercent': observation.usedPercent,
          'windowDurationMinutes': observation.windowDurationMinutes,
          'resetsAt': observation.resetsAt?.toUtc().toIso8601String(),
          'observedAt': observation.observedAt.toUtc().toIso8601String(),
          'accountEmail': observation.accountEmail,
          'planType': observation.planType,
        };

  static HeartbeatStatus _statusFromStorage(Object? value) => switch (value) {
    'observing' => HeartbeatStatus.observing,
    'candidate' => HeartbeatStatus.candidate,
    'running' => HeartbeatStatus.running,
    'verified' => HeartbeatStatus.verified,
    'active' => HeartbeatStatus.active,
    'unsupported' => HeartbeatStatus.unsupported,
    'unverified' => HeartbeatStatus.unverified,
    'failed' => HeartbeatStatus.failed,
    'probe_failed' => HeartbeatStatus.probeFailed,
    _ => HeartbeatStatus.unknown,
  };

  static String _statusToStorage(HeartbeatStatus value) => switch (value) {
    HeartbeatStatus.probeFailed => 'probe_failed',
    _ => value.name,
  };

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
