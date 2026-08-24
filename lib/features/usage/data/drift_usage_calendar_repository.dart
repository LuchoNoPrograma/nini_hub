import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:multi_cli_ai/features/usage/domain/usage_ports.dart';

final class DriftUsageCalendarRepository implements UsageCalendarRepository {
  const DriftUsageCalendarRepository(this.database);

  final AppDatabase database;

  @override
  Future<UsageCalendar> loadCalendar() async {
    final rows = await database
        .customSelect(
          _calendarSql,
          readsFrom: {
            database.cliProfiles,
            database.dailyUsageBuckets,
            database.usageChecks,
            database.quotaWindows,
            database.profileMetadatas,
          },
        )
        .get();
    final days = <DateTime, _MutableUsageCalendarDay>{};
    for (final row in rows) {
      final data = row.data;
      final day = DateTime.parse(data['day_key']! as String);
      final target = days.putIfAbsent(day, _MutableUsageCalendarDay.new);
      target.add(
        UsageAccountDay(
          profileId: data['profile_id']! as String,
          displayName: data['display_name']! as String,
          email: data['email']! as String,
          tokens: _integer(data['tokens']),
          successfulChecks: _integer(data['successful_checks']),
          failedChecks: _integer(data['failed_checks']),
          lowestRemaining: _decimal(data['lowest_remaining']),
          resetCount: _integer(data['reset_count']),
          renewalCount: _integer(data['renewal_count']),
        ),
      );
    }
    return UsageCalendar(
      days.entries.map((entry) => entry.value.build(entry.key)),
    );
  }

  static int _integer(Object? value) => (value as num?)?.toInt() ?? 0;

  static double? _decimal(Object? value) => (value as num?)?.toDouble();

  static const String _calendarSql = r'''
WITH token_max AS (
  SELECT profile_id,
         strftime('%Y-%m-%d', day, 'unixepoch') AS day_key,
         MAX(tokens) AS tokens
  FROM daily_usage_buckets
  GROUP BY profile_id, day_key
  HAVING MAX(tokens) > 0
),
token_days AS (
  SELECT profile_id,
         day_key,
         tokens,
         0 AS successful_checks,
         0 AS failed_checks,
         CAST(NULL AS REAL) AS lowest_remaining,
         0 AS reset_count,
         0 AS renewal_count
  FROM token_max
),
check_days AS (
  SELECT profile_id,
         strftime('%Y-%m-%d', started_at, 'unixepoch', 'localtime') AS day_key,
         0 AS tokens,
         SUM(CASE WHEN status IN ('success', 'partial') THEN 1 ELSE 0 END)
           AS successful_checks,
         SUM(CASE WHEN status IN ('success', 'partial') THEN 0 ELSE 1 END)
           AS failed_checks,
         CAST(NULL AS REAL) AS lowest_remaining,
         0 AS reset_count,
         0 AS renewal_count
  FROM usage_checks
  GROUP BY profile_id, day_key
),
remaining_days AS (
  SELECT checks.profile_id,
         strftime(
           '%Y-%m-%d',
           checks.started_at,
           'unixepoch',
           'localtime'
         ) AS day_key,
         0 AS tokens,
         0 AS successful_checks,
         0 AS failed_checks,
         MIN(
           CASE
             WHEN 100.0 - windows.used_percent < 0 THEN 0.0
             WHEN 100.0 - windows.used_percent > 100 THEN 100.0
             ELSE 100.0 - windows.used_percent
           END
         ) AS lowest_remaining,
         0 AS reset_count,
         0 AS renewal_count
  FROM quota_windows AS windows
  INNER JOIN usage_checks AS checks ON checks.id = windows.check_id
  WHERE windows.used_percent IS NOT NULL
  GROUP BY checks.profile_id, day_key
),
reset_events AS (
  SELECT DISTINCT checks.profile_id,
                  windows.limit_id,
                  windows.window_type,
                  windows.resets_at,
                  strftime(
                    '%Y-%m-%d',
                    windows.resets_at,
                    'unixepoch',
                    'localtime'
                  ) AS day_key
  FROM quota_windows AS windows
  INNER JOIN usage_checks AS checks ON checks.id = windows.check_id
  WHERE windows.resets_at IS NOT NULL
),
reset_days AS (
  SELECT profile_id,
         day_key,
         0 AS tokens,
         0 AS successful_checks,
         0 AS failed_checks,
         CAST(NULL AS REAL) AS lowest_remaining,
         COUNT(*) AS reset_count,
         0 AS renewal_count
  FROM reset_events
  GROUP BY profile_id, day_key
),
renewal_days AS (
  SELECT profile_id,
         strftime(
           '%Y-%m-%d',
           next_renewal_on,
           'unixepoch',
           'localtime'
         ) AS day_key,
         0 AS tokens,
         0 AS successful_checks,
         0 AS failed_checks,
         CAST(NULL AS REAL) AS lowest_remaining,
         0 AS reset_count,
         COUNT(*) AS renewal_count
  FROM profile_metadatas
  WHERE next_renewal_on IS NOT NULL
  GROUP BY profile_id, day_key
),
metric_rows AS (
  SELECT * FROM token_days
  UNION ALL
  SELECT * FROM check_days
  UNION ALL
  SELECT * FROM remaining_days
  UNION ALL
  SELECT * FROM reset_days
  UNION ALL
  SELECT * FROM renewal_days
),
profile_days AS (
  SELECT profile_id,
         day_key,
         SUM(tokens) AS tokens,
         SUM(successful_checks) AS successful_checks,
         SUM(failed_checks) AS failed_checks,
         MIN(lowest_remaining) AS lowest_remaining,
         SUM(reset_count) AS reset_count,
         SUM(renewal_count) AS renewal_count
  FROM metric_rows
  GROUP BY profile_id, day_key
),
historical_emails AS (
  SELECT profile_id, TRIM(account_email) AS account_email
  FROM usage_checks
  WHERE account_email IS NOT NULL AND TRIM(account_email) <> ''
  GROUP BY profile_id
)
SELECT days.profile_id,
       days.day_key,
       profiles.display_name,
       CASE
         WHEN TRIM(COALESCE(metadata.account_email, '')) <> ''
           THEN TRIM(metadata.account_email)
         ELSE COALESCE(historical_emails.account_email, '')
       END AS email,
       days.tokens,
       days.successful_checks,
       days.failed_checks,
       days.lowest_remaining,
       days.reset_count,
       days.renewal_count
FROM profile_days AS days
INNER JOIN cli_profiles AS profiles ON profiles.id = days.profile_id
LEFT JOIN profile_metadatas AS metadata
  ON metadata.profile_id = days.profile_id
LEFT JOIN historical_emails
  ON historical_emails.profile_id = days.profile_id
ORDER BY days.day_key, days.profile_id
''';
}

final class _MutableUsageCalendarDay {
  int tokens = 0;
  int successfulChecks = 0;
  int failedChecks = 0;
  double? lowestRemaining;
  int resetCount = 0;
  int renewalCount = 0;
  final List<UsageAccountDay> accounts = [];

  void add(UsageAccountDay account) {
    tokens += account.tokens;
    successfulChecks += account.successfulChecks;
    failedChecks += account.failedChecks;
    resetCount += account.resetCount;
    renewalCount += account.renewalCount;
    final remaining = account.lowestRemaining;
    if (remaining != null &&
        (lowestRemaining == null || remaining < lowestRemaining!)) {
      lowestRemaining = remaining;
    }
    if (account.hasActivity) accounts.add(account);
  }

  UsageCalendarDay build(DateTime day) {
    accounts.sort((left, right) {
      final byTokens = right.tokens.compareTo(left.tokens);
      return byTokens != 0
          ? byTokens
          : left.displayName.toLowerCase().compareTo(
              right.displayName.toLowerCase(),
            );
    });
    return UsageCalendarDay(
      day: day,
      tokens: tokens,
      successfulChecks: successfulChecks,
      failedChecks: failedChecks,
      lowestRemaining: lowestRemaining,
      resetCount: resetCount,
      renewalCount: renewalCount,
      accounts: accounts,
    );
  }
}
