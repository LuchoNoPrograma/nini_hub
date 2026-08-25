import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/app/app_startup.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/widgets/app_primitives.dart';
import 'package:nini_hub/features/accounts/presentation/accounts_view.dart';
import 'package:nini_hub/features/activity/presentation/activity_view.dart';
import 'package:nini_hub/features/settings/presentation/settings_dialog.dart';
import 'package:nini_hub/features/usage/presentation/calendar_view.dart';

enum DashboardSection { accounts, calendar, activity }

class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({
    super.key,
    this.initialSection = DashboardSection.accounts,
  });

  final DashboardSection initialSection;

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  late DashboardSection section;

  @override
  void initState() {
    super.initState();
    section = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(appStartupProvider);
    final profilesBusy = ref.watch(
      profilesControllerProvider.select((state) => state.isBusy),
    );
    final accountsBusy = ref.watch(
      accountsControllerProvider.select((state) => state.isBusy),
    );
    final usageBusy = ref.watch(
      usageControllerProvider.select((state) => state.isRefreshing),
    );
    final heartbeatBusy = ref.watch(
      heartbeatControllerProvider.select((state) => state.isBusy),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _OperationsBar(
              startupBusy: startup.isLoading,
              section: section,
              onSectionChanged: (value) => setState(() => section = value),
            ),
            if (startup.isLoading ||
                usageBusy ||
                heartbeatBusy ||
                profilesBusy ||
                accountsBusy)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            Expanded(child: _body(context, ref, startup)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, AsyncValue<void> startup) {
    if (startup.hasError) {
      final failure = AppStartupFailure.from(startup.error!);
      return EmptyState(
        icon: failure.kind == AppStartupFailureKind.updateRequired
            ? Icons.system_update_alt
            : Icons.error_outline,
        title: failure.title,
        message: failure.message,
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(appStartupProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      );
    }
    if (startup.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final content = switch (section) {
      DashboardSection.accounts => const AccountsView(
        key: ValueKey('accounts'),
      ),
      DashboardSection.calendar => const UsageCalendarView(
        key: ValueKey('calendar'),
      ),
      DashboardSection.activity => const ActivityView(
        key: ValueKey('activity'),
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.015, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

class _OperationsBar extends ConsumerWidget {
  const _OperationsBar({
    required this.startupBusy,
    required this.section,
    required this.onSectionChanged,
  });

  final bool startupBusy;
  final DashboardSection section;
  final ValueChanged<DashboardSection> onSectionChanged;

  Future<void> _guard(BuildContext context, Future<void> future) async {
    try {
      await future;
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _openSettings(BuildContext context, WidgetRef ref) async {
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final initialState = ref.read(settingsControllerProvider);
    if (!initialState.isInitialized) {
      final loaded = initialState.isLoading
          ? await ref.read(settingsBootstrapProvider.future)
          : await settingsController.load();
      if (!context.mounted) return;
      if (!loaded) {
        final message = ref.read(settingsControllerProvider).errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message ?? 'No se pudo cargar la configuración.'),
          ),
        );
        return;
      }
    }
    await showSettingsDialog(context, settingsControllerProvider);
  }

  Future<void> _rediscoverProfiles(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(profilesControllerProvider.notifier);
    final loaded = await controller.load();
    if (!context.mounted) return;
    if (!loaded) {
      final message = ref.read(profilesControllerProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'No se pudieron cargar los perfiles.'),
        ),
      );
      return;
    }
    final accountsLoaded = await ref
        .read(accountsControllerProvider.notifier)
        .load();
    if (!accountsLoaded && context.mounted) {
      final message = ref.read(accountsControllerProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'No se pudieron cargar las cuentas.'),
        ),
      );
    }
  }

  Future<void> _refreshAll(BuildContext context, WidgetRef ref) async {
    await ref.read(usageRefreshCoordinatorProvider).refreshAll();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profilesBusy = ref.watch(
      profilesControllerProvider.select((state) => state.isBusy),
    );
    final accountsBusy = ref.watch(
      accountsControllerProvider.select((state) => state.isBusy),
    );
    final usageState = ref.watch(usageControllerProvider);
    final heartbeatState = ref.watch(heartbeatControllerProvider);
    final refreshingCount =
        usageState.refreshingProfileIds.length +
        heartbeatState.runningProfileIds.length;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.asset(
                    'assets/branding/nini-hub-icon.png',
                    width: 20,
                    height: 20,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(width: 7),
                Text('Nini Hub', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          _TopMenuItem(
            label: 'Cuentas',
            selected: section == DashboardSection.accounts,
            onTap: () => onSectionChanged(DashboardSection.accounts),
          ),
          _TopMenuItem(
            label: 'Estadísticas',
            selected: section == DashboardSection.calendar,
            onTap: () => onSectionChanged(DashboardSection.calendar),
          ),
          _TopMenuItem(
            label: 'Log',
            selected: section == DashboardSection.activity,
            onTap: () => onSectionChanged(DashboardSection.activity),
          ),
          const Spacer(),
          if (usageState.isRefreshingAll || refreshingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: Text(
                usageState.isRefreshingAll
                    ? '${usageState.completedBatchByProfile.length} completadas'
                    : '$refreshingCount en consulta',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          AppIconButton(
            icon: Icons.sync,
            tooltip: 'Redescubrir perfiles',
            onPressed: startupBusy || profilesBusy || accountsBusy
                ? null
                : () => _rediscoverProfiles(context, ref),
          ),
          AppIconButton(
            icon: Icons.refresh,
            tooltip: 'Actualizar todas las cuentas',
            onPressed:
                !usageState.isRefreshing &&
                    !heartbeatState.isBusy &&
                    !accountsBusy
                ? () => _guard(context, _refreshAll(context, ref))
                : null,
          ),
          AppIconButton(
            icon: Icons.person_add_alt_1_outlined,
            tooltip: 'Crear perfil',
            onPressed: profilesBusy
                ? null
                : () => showCreateProfileFlow(context, ref),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: theme.colorScheme.outline,
          ),
          AppIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Configuración',
            onPressed: () => _openSettings(context, ref),
          ),
        ],
      ),
    );
  }
}

class _TopMenuItem extends StatefulWidget {
  const _TopMenuItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TopMenuItem> createState() => _TopMenuItemState();
}

class _TopMenuItemState extends State<_TopMenuItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered
                ? theme.colorScheme.surfaceContainer
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: widget.selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
