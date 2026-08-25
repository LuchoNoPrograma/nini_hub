import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/usage/domain/quota_reset_anchor_policy.dart';

void main() {
  final observedAt = DateTime.utc(2026, 8, 25, 12);

  group('QuotaResetAnchorPolicy', () {
    test('marks a reset that follows observation time as estimated', () {
      final previousAt = observedAt.subtract(const Duration(minutes: 30));

      final confidence = QuotaResetAnchorPolicy.classify(
        previous: _observation(
          observedAt: previousAt,
          resetsAt: previousAt.add(const Duration(hours: 5)),
        ),
        current: _observation(
          observedAt: observedAt,
          resetsAt: observedAt.add(const Duration(hours: 5)),
        ),
      );

      expect(confidence, QuotaResetAnchorConfidence.estimated);
    });

    test('marks a stable reset anchor as confirmed', () {
      final reset = observedAt.add(const Duration(hours: 4, minutes: 30));

      final confidence = QuotaResetAnchorPolicy.classify(
        previous: _observation(
          observedAt: observedAt.subtract(const Duration(minutes: 30)),
          resetsAt: reset,
        ),
        current: _observation(observedAt: observedAt, resetsAt: reset),
      );

      expect(confidence, QuotaResetAnchorConfidence.confirmed);
    });

    test('activity confirms an anchor without a prior sample', () {
      final confidence = QuotaResetAnchorPolicy.classify(
        current: _observation(
          observedAt: observedAt,
          resetsAt: observedAt.add(const Duration(hours: 4)),
          usedPercent: 1,
        ),
      );

      expect(confidence, QuotaResetAnchorConfidence.confirmed);
    });

    test('a floating projection remains estimated despite rounded usage', () {
      final previousAt = observedAt.subtract(const Duration(minutes: 30));

      final confidence = QuotaResetAnchorPolicy.classify(
        previous: _observation(
          observedAt: previousAt,
          resetsAt: previousAt.add(const Duration(hours: 5)),
          usedPercent: 1,
        ),
        current: _observation(
          observedAt: observedAt,
          resetsAt: observedAt.add(const Duration(hours: 5)),
          usedPercent: 1,
        ),
      );

      expect(confidence, QuotaResetAnchorConfidence.estimated);
    });

    test('reports unavailable when no reset was returned', () {
      final confidence = QuotaResetAnchorPolicy.classify(
        current: _observation(observedAt: observedAt, resetsAt: null),
      );

      expect(confidence, QuotaResetAnchorConfidence.unavailable);
    });
  });
}

QuotaResetAnchorObservation _observation({
  required DateTime observedAt,
  required DateTime? resetsAt,
  double usedPercent = 0,
}) => QuotaResetAnchorObservation(
  observedAt: observedAt,
  usedPercent: usedPercent,
  windowDurationMinutes: 300,
  resetsAt: resetsAt,
);
