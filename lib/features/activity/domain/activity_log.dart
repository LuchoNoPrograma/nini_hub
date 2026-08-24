enum ActivityLogStatus { success, running, error, timeout, unknown }

final class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.profileId,
    required this.command,
    required this.summary,
    required this.output,
    required this.status,
    required this.exitCode,
    required this.startedAt,
    required this.completedAt,
  });

  final String id;
  final String? profileId;
  final String command;
  final String summary;
  final String output;
  final ActivityLogStatus status;
  final int? exitCode;
  final DateTime startedAt;
  final DateTime? completedAt;
}
