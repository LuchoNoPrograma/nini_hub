import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/formatters.dart';
import 'package:multi_cli_ai/core/widgets/app_primitives.dart';
import 'package:multi_cli_ai/features/activity/domain/activity_log.dart';
import 'package:multi_cli_ai/features/activity/presentation/controllers/activity_controller.dart';
import 'package:multi_cli_ai/features/activity/presentation/state/activity_state.dart';

class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});

  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends ConsumerState<ActivityView> {
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activityControllerProvider);
    final controller = ref.read(activityControllerProvider.notifier);
    final logs = state.visibleLogs;
    final selected = state.selectedLog;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 13),
          child: SectionTitle(
            title: 'Log',
            subtitle: 'Comandos ejecutados y su salida técnica.',
            trailing: AppIconButton(
              tooltip: 'Limpiar historial',
              onPressed: state.logs.isEmpty || state.isBusy
                  ? null
                  : () => _clear(controller),
              icon: Icons.delete_sweep_outlined,
            ),
          ),
        ),
        if (state.isBusy)
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
        if (state.isInitialized && state.errorMessage != null)
          _ActivityFailureBanner(
            message: state.errorMessage!,
            busy: state.isBusy,
            onRetry: controller.load,
            onDismiss: controller.clearFailure,
          ),
        _ActivityToolbar(
          searchController: searchController,
          status: state.statusFilter,
          visibleCount: logs.length,
          totalCount: state.logs.length,
          onSearchChanged: controller.setSearch,
          onClearSearch: () {
            searchController.clear();
            controller.setSearch('');
          },
          onStatusChanged: controller.setStatusFilter,
        ),
        Expanded(
          child: !state.isInitialized
              ? state.errorMessage != null
                    ? EmptyState(
                        icon: Icons.error_outline,
                        title: 'No se pudo cargar el historial',
                        message: state.errorMessage!,
                        action: FilledButton.icon(
                          onPressed: state.isBusy ? null : controller.load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator())
              : logs.isEmpty
              ? EmptyState(
                  icon: Icons.history_outlined,
                  title: state.logs.isEmpty
                      ? 'Aún no hay registros'
                      : 'No hay coincidencias',
                  message: state.logs.isEmpty
                      ? 'Los comandos y sus resultados aparecerán aquí.'
                      : 'Ajusta la búsqueda o muestra todos los estados.',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final splitView = constraints.maxWidth >= 780;
                    final timeline = _ActivityTimeline(
                      logs: logs,
                      selectedId: selected?.id,
                      onSelected: (log) {
                        controller.selectLog(log.id);
                        if (!splitView) _showLogDetails(log);
                      },
                    );
                    if (!splitView) return timeline;
                    return Row(
                      children: [
                        Expanded(child: timeline),
                        SizedBox(
                          width: (constraints.maxWidth * .4).clamp(
                            340.0,
                            430.0,
                          ),
                          child: _LogInspector(log: selected),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showLogDetails(ActivityLog log) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      constraints: BoxConstraints(
        maxWidth: 720,
        maxHeight: MediaQuery.sizeOf(context).height * .76,
      ),
      builder: (_) => _LogInspector(log: log, sheet: true),
    );
  }

  Future<void> _clear(ActivityController controller) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limpiar historial'),
        content: const Text(
          'Se eliminarán los registros locales de operaciones. Los perfiles, '
          'credenciales y capturas de uso no cambian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (accepted == true) await controller.clear();
  }
}

class _ActivityFailureBanner extends StatelessWidget {
  const _ActivityFailureBanner({
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
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
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

class _ActivityToolbar extends StatelessWidget {
  const _ActivityToolbar({
    required this.searchController,
    required this.status,
    required this.visibleCount,
    required this.totalCount,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStatusChanged,
  });

  final TextEditingController searchController;
  final ActivityStatusFilter status;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<ActivityStatusFilter> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 9, 18, 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border.symmetric(
          horizontal: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = SizedBox(
            width: constraints.maxWidth < 560 ? constraints.maxWidth : 270,
            child: TextField(
              key: const ValueKey('activity-search'),
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar en el log',
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close, size: 15),
                      ),
              ),
            ),
          );
          final controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                visibleCount == totalCount
                    ? '$totalCount eventos'
                    : '$visibleCount de $totalCount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              _StatusMenu(value: status, onChanged: onStatusChanged),
            ],
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [search, const SizedBox(height: 8), controls],
            );
          }
          return Row(children: [search, const Spacer(), controls]);
        },
      ),
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.value, required this.onChanged});

  final ActivityStatusFilter value;
  final ValueChanged<ActivityStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (value) {
      ActivityStatusFilter.running => 'En curso',
      ActivityStatusFilter.error => 'Con errores',
      ActivityStatusFilter.all => 'Todos los estados',
    };
    return PopupMenuButton<ActivityStatusFilter>(
      tooltip: 'Filtrar por estado',
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: ActivityStatusFilter.all,
          child: Text('Todos los estados'),
        ),
        PopupMenuItem(
          value: ActivityStatusFilter.running,
          child: Text('En curso'),
        ),
        PopupMenuItem(
          value: ActivityStatusFilter.error,
          child: Text('Con errores'),
        ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({
    required this.logs,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ActivityLog> logs;
  final String? selectedId;
  final ValueChanged<ActivityLog> onSelected;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 6),
    itemCount: logs.length,
    itemBuilder: (context, index) {
      final log = logs[index];
      return _ActivityRow(
            log: log,
            selected: log.id == selectedId,
            onTap: () => onSelected(log),
          )
          .animate(delay: (index.clamp(0, 7) * 24).ms)
          .fadeIn(duration: 180.ms)
          .moveY(begin: 3, end: 0);
    },
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.log,
    required this.selected,
    required this.onTap,
  });

  final ActivityLog log;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = _statusVisual(theme, log.status);
    return Semantics(
      selected: selected,
      button: true,
      label: '${visual.label}: ${log.summary}',
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: .07)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                _StatusIcon(
                  visual: visual,
                  running: log.status == ActivityLogStatus.running,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        log.command,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .78,
                          ),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: formatDateTime(log.startedAt),
                  child: Text(
                    relativeTime(log.startedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Icon(
                  Icons.chevron_right,
                  size: 17,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.visual, required this.running});

  final _LogStatusVisual visual;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: .1),
        shape: BoxShape.circle,
      ),
      child: Icon(visual.icon, size: 15, color: visual.color),
    );
    if (!running) return icon;
    return icon
        .animate(onPlay: (controller) => controller.repeat())
        .rotate(duration: 1200.ms);
  }
}

class _LogInspector extends StatelessWidget {
  const _LogInspector({required this.log, this.sheet = false});

  final ActivityLog? log;
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (log == null) return const SizedBox.shrink();
    final item = log!;
    final visual = _statusVisual(theme, item.status);
    final duration = _measuredDuration(item);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: sheet
            ? null
            : Border(left: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, sheet ? 2 : 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Detalle', style: theme.textTheme.titleMedium),
                ),
                _StatusLabel(visual: visual),
                const SizedBox(width: 4),
                AppIconButton(
                  icon: Icons.content_copy_outlined,
                  tooltip: 'Copiar salida',
                  onPressed: () => _copyOutput(context, item),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outline),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _MetaText(
                      icon: Icons.schedule_outlined,
                      value: formatDateTime(item.startedAt),
                    ),
                    if (duration != null)
                      _MetaText(
                        icon: Icons.timer_outlined,
                        value: _formatDuration(duration),
                      ),
                    if (item.profileId != null)
                      _MetaText(
                        icon: Icons.person_outline,
                        value: item.profileId!,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  color: theme.colorScheme.surfaceContainer,
                  child: SelectableText(
                    '\$ ${item.command}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                      letterSpacing: 0,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 7),
            child: Row(
              children: [
                Text('SALIDA', style: theme.textTheme.labelSmall),
                const Spacer(),
                if (item.exitCode != null)
                  Text(
                    'Código ${item.exitCode}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: item.exitCode == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              color: theme.colorScheme.surfaceContainerLowest,
              child: SingleChildScrollView(
                child: SelectableText(
                  item.output.isNotEmpty
                      ? item.output
                      : item.status == ActivityLogStatus.running
                      ? 'Esperando salida…'
                      : 'La operación no produjo salida.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.55,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyOutput(BuildContext context, ActivityLog item) async {
    await Clipboard.setData(
      ClipboardData(text: item.output.isEmpty ? item.command : item.output),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Salida copiada')));
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.visual});

  final _LogStatusVisual visual;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusDot(color: visual.color, size: 7),
      const SizedBox(width: 6),
      Text(
        visual.label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: visual.color),
      ),
    ],
  );
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          value,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LogStatusVisual {
  const _LogStatusVisual(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

_LogStatusVisual _statusVisual(ThemeData theme, ActivityLogStatus status) =>
    switch (status) {
      ActivityLogStatus.success => const _LogStatusVisual(
        'Completado',
        Icons.check_rounded,
        Color(0xFF58E2AD),
      ),
      ActivityLogStatus.running => _LogStatusVisual(
        'En curso',
        Icons.sync_rounded,
        theme.colorScheme.tertiary,
      ),
      _ => _LogStatusVisual(
        'Falló',
        Icons.close_rounded,
        theme.colorScheme.error,
      ),
    };

String _formatDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) return '$milliseconds ms';
  if (milliseconds < 60000) {
    final seconds = milliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
  }
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return seconds == 0 ? '$minutes min' : '$minutes min $seconds s';
}

Duration? _measuredDuration(ActivityLog log) {
  final completedAt = log.completedAt;
  if (completedAt == null ||
      log.output.startsWith('Proceso iniciado en una terminal separada.')) {
    return null;
  }
  final duration = completedAt.difference(log.startedAt);
  return duration > Duration.zero ? duration : null;
}
