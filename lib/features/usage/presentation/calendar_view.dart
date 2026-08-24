import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/formatters.dart';
import 'package:multi_cli_ai/core/widgets/app_primitives.dart';
import 'package:multi_cli_ai/features/usage/domain/usage.dart';
import 'package:table_calendar/table_calendar.dart';

class UsageCalendarView extends ConsumerStatefulWidget {
  const UsageCalendarView({super.key});

  @override
  ConsumerState<UsageCalendarView> createState() => _UsageCalendarViewState();
}

class _UsageCalendarViewState extends ConsumerState<UsageCalendarView> {
  late DateTime focusedDay;

  @override
  void initState() {
    super.initState();
    focusedDay = _day(ref.read(usageControllerProvider).selectedDay);
  }

  void _focusMonth(DateTime day) {
    setState(() => focusedDay = _day(day));
  }

  void _shiftMonth(int offset) {
    _focusMonth(DateTime(focusedDay.year, focusedDay.month + offset, 1));
  }

  void _selectDay(DateTime day) {
    final selected = _day(day);
    _focusMonth(selected);
    ref.read(usageControllerProvider.notifier).selectDay(selected);
  }

  void _goToday() {
    final today = _day(DateTime.now());
    _focusMonth(today);
    ref.read(usageControllerProvider.notifier).selectDay(today);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(usageControllerProvider);
    final controller = ref.read(usageControllerProvider.notifier);
    if (!state.isCalendarInitialized) {
      final failure = state.calendarFailure;
      if (failure != null) {
        return EmptyState(
          icon: Icons.error_outline,
          title: 'No se pudo cargar el calendario',
          message: failure.message,
          action: FilledButton.icon(
            onPressed: state.isCalendarLoading ? null : controller.loadCalendar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final calendar = state.calendar.days;
    final selected = _day(state.selectedDay);
    final monthData = calendar.entries
        .where(
          (entry) =>
              entry.key.year == focusedDay.year &&
              entry.key.month == focusedDay.month,
        )
        .map((entry) => entry.value)
        .toList();
    final totalTokens = monthData.fold<int>(
      0,
      (sum, item) => sum + item.tokens,
    );
    final observedDays = monthData.where((item) => item.hasActivity).length;
    final monthChecks = monthData.fold<int>(
      0,
      (sum, item) => sum + item.successfulChecks + item.failedChecks,
    );
    final nextReset = calendar.values
        .where(
          (item) =>
              item.resetCount > 0 && !item.day.isBefore(_day(DateTime.now())),
        )
        .map((item) => item.day)
        .fold<DateTime?>(
          null,
          (current, value) =>
              current == null || value.isBefore(current) ? value : current,
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Estadísticas de uso',
            subtitle: 'Compara el uso diario, las cuentas y su evolución.',
          ),
          if (state.isCalendarLoading)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          if (state.calendarFailure != null)
            _UsageCalendarFailureBanner(
              message: state.calendarFailure!.message,
              busy: state.isCalendarLoading,
              onRetry: controller.loadCalendar,
              onDismiss: controller.clearCalendarFailure,
            ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            child: Wrap(
              spacing: 22,
              runSpacing: 8,
              children: [
                MetricItem(
                  label: 'Tokens en ${formatMonth(focusedDay)}',
                  value: formatCompactInt(totalTokens),
                  icon: Icons.data_usage,
                ),
                MetricItem(
                  label: 'Días con uso',
                  value: '$observedDays',
                  icon: Icons.calendar_view_month_outlined,
                  color: const Color(0xFF58E2AD),
                ),
                MetricItem(
                  label: 'Consultas del mes',
                  value: '$monthChecks',
                  icon: Icons.fact_check_outlined,
                ),
                MetricItem(
                  label: 'Próximo reset',
                  value: formatDate(nextReset),
                  icon: Icons.restart_alt,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final calendar = _CalendarPanel(
                data: state.calendar.days,
                focusedDay: focusedDay,
                selectedDay: selected,
                onSelected: _selectDay,
                onPageChanged: _focusMonth,
                onPreviousMonth: () => _shiftMonth(-1),
                onNextMonth: () => _shiftMonth(1),
                onToday: _goToday,
              );
              final inspector = _DayInspector(
                day: selected,
                data: state.calendar[selected],
              );
              if (constraints.maxWidth >= 840) {
                return SizedBox(
                  height: 350,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: calendar),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: inspector),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  SizedBox(height: 350, child: calendar),
                  const SizedBox(height: 12),
                  SizedBox(height: 350, child: inspector),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _UsageTrend(
                data: state.calendar.days,
                anchorDay: selected,
                onDaySelected: _selectDay,
              )
              .animate()
              .fadeIn(duration: 300.ms, delay: 80.ms)
              .moveY(begin: 8, end: 0),
        ],
      ),
    );
  }
}

class _UsageCalendarFailureBanner extends StatelessWidget {
  const _UsageCalendarFailureBanner({
    required this.message,
    required this.busy,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final bool busy;
  final Future<bool> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRetry,
            child: const Text('Reintentar'),
          ),
          IconButton(
            tooltip: 'Cerrar mensaje',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ),
    );
  }
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.data,
    required this.focusedDay,
    required this.selectedDay,
    required this.onSelected,
    required this.onPageChanged,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
  });

  final Map<DateTime, UsageCalendarDay> data;
  final DateTime focusedDay;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<DateTime> onPageChanged;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      formatMonth(focusedDay),
                      key: ValueKey('${focusedDay.year}-${focusedDay.month}'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                TextButton(onPressed: onToday, child: const Text('Hoy')),
                const SizedBox(width: 2),
                AppIconButton(
                  icon: Icons.chevron_left,
                  tooltip: 'Mes anterior',
                  onPressed: onPreviousMonth,
                ),
                AppIconButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Mes siguiente',
                  onPressed: onNextMonth,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          TableCalendar<UsageCalendarDay>(
            locale: 'es',
            firstDay: DateTime.utc(2023),
            lastDay: DateTime.now().add(const Duration(days: 730)),
            focusedDay: focusedDay,
            selectedDayPredicate: (day) => isSameDay(day, selectedDay),
            onDaySelected: (selected, _) => onSelected(selected),
            onPageChanged: onPageChanged,
            startingDayOfWeek: StartingDayOfWeek.monday,
            rowHeight: 43,
            daysOfWeekHeight: 28,
            sixWeekMonthsEnforced: true,
            headerVisible: false,
            availableGestures: AvailableGestures.horizontalSwipe,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: theme.textTheme.labelSmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              weekendStyle: theme.textTheme.labelSmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: true,
              cellMargin: const EdgeInsets.all(2),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, _) =>
                  _CalendarCell(day: day, data: data[_day(day)]),
              todayBuilder: (context, day, _) =>
                  _CalendarCell(day: day, data: data[_day(day)], today: true),
              outsideBuilder: (context, day, _) => Opacity(
                opacity: .38,
                child: _CalendarCell(day: day, data: data[_day(day)]),
              ),
              selectedBuilder: (context, day, _) => _CalendarCell(
                day: day,
                data: data[_day(day)],
                today: isSameDay(day, DateTime.now()),
                selected: true,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms).moveX(begin: -8, end: 0);
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.day,
    required this.data,
    this.today = false,
    this.selected = false,
  });

  final DateTime day;
  final UsageCalendarDay? data;
  final bool today;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alert = (data?.failedChecks ?? 0) > 0;
    final tokens = data?.tokens ?? 0;
    final background = selected
        ? theme.colorScheme.primary.withValues(alpha: .1)
        : alert
        ? theme.colorScheme.error.withValues(alpha: .08)
        : today
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.transparent;
    final tooltip = <String>[
      formatFullDate(day),
      if (today) 'Hoy',
      if (tokens > 0) formatTokenDetails(tokens),
    ].join('\n');
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip.replaceAll('\n', ', '),
        child: AnimatedContainer(
          key: ValueKey('calendar-day-${day.year}-${day.month}-${day.day}'),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(4, 3, 4, 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(5),
            border: selected
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: .7),
                  )
                : today
                ? Border.all(color: theme.colorScheme.primary)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected ? theme.colorScheme.onPrimary : null,
                        fontWeight: selected || today
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (today)
                    Text(
                      'HOY',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (data?.hasActivity == true)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 70;
                    return Row(
                      children: [
                        if (tokens > 0)
                          _Marker(
                            color: selected
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.primary,
                          ),
                        if (!narrow && (data?.resetCount ?? 0) > 0)
                          const _Marker(color: Color(0xFF58E2AD)),
                        if (!narrow && (data?.renewalCount ?? 0) > 0)
                          _Marker(color: theme.colorScheme.tertiary),
                        if ((data?.failedChecks ?? 0) > 0)
                          _Marker(color: theme.colorScheme.error),
                        if (tokens > 0) ...[
                          const SizedBox(width: 2),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  narrow
                                      ? formatCompactInt(
                                          tokens,
                                        ).replaceAll(' ', '')
                                      : formatCompactInt(tokens),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: selected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 5,
    height: 5,
    margin: const EdgeInsets.only(right: 3),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _DayInspector extends StatelessWidget {
  const _DayInspector({required this.day, required this.data});

  final DateTime day;
  final UsageCalendarDay? data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = data?.accounts ?? const <UsageAccountDay>[];
    final checks = (data?.successfulChecks ?? 0) + (data?.failedChecks ?? 0);
    final isToday = isSameDay(day, DateTime.now());
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Detalle de ${formatFullDate(day)}',
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatFullDate(day),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          accounts.isEmpty
                              ? 'Sin actividad registrada'
                              : '${accounts.length} ${accounts.length == 1 ? 'cuenta activa' : 'cuentas activas'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isToday) const _TodayBadge(),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              color: theme.colorScheme.surfaceContainerLow,
              child: Wrap(
                spacing: 24,
                runSpacing: 10,
                children: [
                  _DayMetric(
                    label: 'Tokens',
                    value: formatCompactInt(data?.tokens ?? 0),
                    caption: '${formatInteger(data?.tokens ?? 0)} exactos',
                    tooltip: formatTokenDetails(data?.tokens ?? 0),
                  ),
                  _DayMetric(label: 'Consultas', value: '$checks'),
                  _DayMetric(
                    label: 'Correctas',
                    value: '${data?.successfulChecks ?? 0}',
                  ),
                  _DayMetric(
                    label: 'Fallidas',
                    value: '${data?.failedChecks ?? 0}',
                    alert: (data?.failedChecks ?? 0) > 0,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            if (accounts.isEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 42,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 28,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No hay datos para este día',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 13, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Uso por cuenta',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  shrinkWrap: true,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) =>
                      _AccountDayRow(account: accounts[index]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayMetric extends StatelessWidget {
  const _DayMetric({
    required this.label,
    required this.value,
    this.caption,
    this.tooltip,
    this.alert = false,
  });

  final String label;
  final String value;
  final String? caption;
  final String? tooltip;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metric = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: alert ? theme.colorScheme.error : null,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 1),
          Text(
            caption!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    return tooltip == null ? metric : Tooltip(message: tooltip, child: metric);
  }
}

class _TodayBadge extends StatelessWidget {
  const _TodayBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.today_outlined, size: 13, color: theme.colorScheme.primary),
        const SizedBox(width: 5),
        Text(
          'Hoy',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AccountDayRow extends StatelessWidget {
  const _AccountDayRow({required this.account});

  final UsageAccountDay account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checks = account.successfulChecks + account.failedChecks;
    final details = <String>[
      if (checks > 0) '$checks ${checks == 1 ? 'consulta' : 'consultas'}',
      if (account.resetCount > 0)
        '${account.resetCount} ${account.resetCount == 1 ? 'reset' : 'resets'}',
      if (account.renewalCount > 0)
        '${account.renewalCount} ${account.renewalCount == 1 ? 'renovación' : 'renovaciones'}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccountAvatar(name: account.displayName),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: formatTokenDetails(account.tokens),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatCompactInt(account.tokens),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            '${formatInteger(account.tokens)} exactos',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (account.email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    account.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (account.lowestRemaining != null) ...[
                  const SizedBox(height: 9),
                  _AvailabilityBar(
                    profileId: account.profileId,
                    remaining: account.lowestRemaining!,
                  ),
                ],
                if (details.isNotEmpty || account.failedChecks > 0) ...[
                  const SizedBox(height: 7),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        if (details.isNotEmpty)
                          TextSpan(text: details.join('  ·  ')),
                        if (account.failedChecks > 0)
                          TextSpan(
                            text:
                                '${details.isEmpty ? '' : '  ·  '}${account.failedChecks} ${account.failedChecks == 1 ? 'fallida' : 'fallidas'}',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityBar extends StatelessWidget {
  const _AvailabilityBar({required this.profileId, required this.remaining});

  final String profileId;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = remaining.clamp(0, 100).toDouble();
    final color = value <= 10
        ? theme.colorScheme.error
        : value <= 25
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Cuota disponible',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${value.toStringAsFixed(0)}% disponible',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value / 100),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) => LinearProgressIndicator(
            key: ValueKey('calendar-availability-$profileId'),
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: color,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = name.trim();
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UsageTrend extends StatefulWidget {
  const _UsageTrend({
    required this.data,
    required this.anchorDay,
    required this.onDaySelected,
  });

  final Map<DateTime, UsageCalendarDay> data;
  final DateTime anchorDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<_UsageTrend> createState() => _UsageTrendState();
}

class _UsageTrendState extends State<_UsageTrend> {
  int range = 14;
  int? focusedIndex;

  @override
  void didUpdateWidget(covariant _UsageTrend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.anchorDay, widget.anchorDay)) {
      focusedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anchor = _day(widget.anchorDay);
    final days = List.generate(
      range,
      (index) => anchor.subtract(Duration(days: range - 1 - index)),
    );
    final values = days.map((day) => widget.data[day]?.tokens ?? 0).toList();
    final maximum = values.fold<int>(
      0,
      (current, value) => value > current ? value : current,
    );
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final activeDays = values.where((value) => value > 0).length;
    final spots = values
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.toDouble()))
        .toList();
    final selectedIndex = focusedIndex?.clamp(0, days.length - 1);
    final selectedDay = selectedIndex == null ? null : days[selectedIndex];
    final selectedData = selectedDay == null ? null : widget.data[selectedDay];
    final scale = _ChartScale.fromMaximum(maximum);
    final todayIndex = days.indexWhere((day) => isSameDay(day, DateTime.now()));

    return Container(
      height: 286,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tendencia de tokens',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDate(days.first)} – ${formatDate(days.last)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 d')),
                  ButtonSegment(value: 14, label: Text('14 d')),
                  ButtonSegment(value: 30, label: Text('30 d')),
                  ButtonSegment(value: 90, label: Text('90 d')),
                ],
                selected: {range},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (selection) {
                  setState(() {
                    range = selection.first;
                    focusedIndex = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.centerLeft,
            child: selectedDay == null
                ? Text(
                    'Total ${formatCompactInt(total)}  ·  Promedio ${formatCompactInt(total ~/ range)}  ·  $activeDays ${activeDays == 1 ? 'día con uso' : 'días con uso'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Row(
                    children: [
                      Text(
                        formatDate(selectedDay),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${formatCompactInt(selectedData?.tokens ?? 0)} tokens',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${selectedData?.accounts.length ?? 0} ${selectedData?.accounts.length == 1 ? 'cuenta' : 'cuentas'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: maximum == 0
                ? Center(
                    child: Text(
                      'No hay tokens registrados en este período',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (range - 1).toDouble(),
                      minY: 0,
                      maxY: scale.maximum,
                      extraLinesData: ExtraLinesData(
                        verticalLines: [
                          if (todayIndex >= 0)
                            VerticalLine(
                              x: todayIndex.toDouble(),
                              color: theme.colorScheme.tertiary.withValues(
                                alpha: .7,
                              ),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                              label: VerticalLineLabel(
                                show: true,
                                alignment: Alignment.topLeft,
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 3,
                                ),
                                style: theme.textTheme.labelSmall!.copyWith(
                                  color: theme.colorScheme.tertiary,
                                  fontWeight: FontWeight.w700,
                                ),
                                labelResolver: (_) => 'HOY',
                              ),
                            ),
                        ],
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: scale.interval,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: theme.colorScheme.outlineVariant,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 46,
                            interval: scale.interval,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(
                                formatCompactInt(value.round()),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: range <= 14
                                ? 3
                                : range <= 30
                                ? 7
                                : 15,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) {
                              final index = value.round().clamp(
                                0,
                                days.length - 1,
                              );
                              return SideTitleWidget(
                                meta: meta,
                                space: 7,
                                child: Text(
                                  isSameDay(days[index], DateTime.now())
                                      ? 'Hoy\n${days[index].day} ${_shortMonth(days[index])}'
                                      : '${days[index].day} ${_shortMonth(days[index])}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        isSameDay(days[index], DateTime.now())
                                        ? theme.colorScheme.tertiary
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontWeight:
                                        isSameDay(days[index], DateTime.now())
                                        ? FontWeight.w700
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchSpotThreshold: 24,
                        mouseCursorResolver: (_, response) =>
                            response?.lineBarSpots?.isNotEmpty == true
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        touchCallback: (event, response) {
                          final spot = response?.lineBarSpots?.firstOrNull;
                          final nextIndex = event.isInterestedForInteractions
                              ? spot?.x.round()
                              : null;
                          if (nextIndex != focusedIndex) {
                            setState(() => focusedIndex = nextIndex);
                          }
                          if (event is FlTapUpEvent && nextIndex != null) {
                            widget.onDaySelected(days[nextIndex]);
                          }
                        },
                        getTouchedSpotIndicator: (barData, indexes) => indexes
                            .map(
                              (_) => TouchedSpotIndicatorData(
                                FlLine(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: .35,
                                  ),
                                  strokeWidth: 1,
                                  dashArray: [3, 3],
                                ),
                                FlDotData(
                                  getDotPainter: (_, _, _, _) =>
                                      FlDotCirclePainter(
                                        radius: 4,
                                        color: theme.colorScheme.primary,
                                        strokeWidth: 2,
                                        strokeColor: theme.colorScheme.surface,
                                      ),
                                ),
                              ),
                            )
                            .toList(),
                        touchTooltipData: LineTouchTooltipData(
                          maxContentWidth: 170,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipColor: (_) =>
                              theme.colorScheme.inverseSurface,
                          getTooltipItems: (touchedSpots) => touchedSpots.map((
                            spot,
                          ) {
                            final index = spot.x.round().clamp(
                              0,
                              days.length - 1,
                            );
                            final value = values[index];
                            return LineTooltipItem(
                              '${formatFullDate(days[index])}\n${formatTokenDetails(value)}',
                              theme.textTheme.labelSmall!.copyWith(
                                color: theme.colorScheme.onInverseSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          curveSmoothness: .2,
                          barWidth: 2.2,
                          color: theme.colorScheme.primary,
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, _) => spot.y > 0,
                            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                              radius: 2.6,
                              color: theme.colorScheme.surface,
                              strokeWidth: 1.8,
                              strokeColor: theme.colorScheme.primary,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: theme.colorScheme.primary.withValues(
                              alpha: .07,
                            ),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChartScale {
  const _ChartScale({required this.maximum, required this.interval});

  factory _ChartScale.fromMaximum(int maximum) {
    if (maximum <= 0) return const _ChartScale(maximum: 1, interval: 1);
    final rawInterval = maximum / 4;
    final magnitude = rawInterval < 1
        ? 1.0
        : math.pow(10, math.log(rawInterval) ~/ math.ln10).toDouble();
    final normalized = rawInterval / magnitude;
    final nice = normalized <= 1
        ? 1.0
        : normalized <= 2
        ? 2.0
        : normalized <= 2.5
        ? 2.5
        : normalized <= 5
        ? 5.0
        : 10.0;
    final interval = nice * magnitude;
    var axisMaximum = (maximum / interval).ceil() * interval;
    if (axisMaximum <= maximum) axisMaximum += interval;
    return _ChartScale(maximum: axisMaximum, interval: interval);
  }

  final double maximum;
  final double interval;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _shortMonth(DateTime value) => const [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
][value.month - 1];
