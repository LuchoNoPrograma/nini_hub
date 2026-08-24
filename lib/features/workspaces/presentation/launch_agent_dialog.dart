import 'package:flutter/material.dart';
import 'package:multi_cli_ai/core/widgets/app_primitives.dart';
import 'package:multi_cli_ai/features/profiles/presentation/profile_provider_icon.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace.dart';
import 'package:multi_cli_ai/features/workspaces/presentation/controllers/workspace_controller.dart';
import 'package:multi_cli_ai/features/workspaces/presentation/state/workspace_state.dart';
import 'package:multi_cli_ai/features/workspaces/presentation/workspace_dialogs.dart';

final class LaunchProfileOption {
  const LaunchProfileOption({
    required this.id,
    required this.toolKey,
    required this.displayName,
    required this.subtitle,
    required this.canLaunch,
    required this.availablePercent,
  });

  final String id;
  final String toolKey;
  final String displayName;
  final String subtitle;
  final bool canLaunch;
  final double? availablePercent;
}

class LaunchAgentDialog extends StatefulWidget {
  const LaunchAgentDialog({
    required this.controller,
    required this.state,
    required this.profiles,
    required this.pickDirectory,
    required this.fallbackDirectory,
    required this.onProfileSelected,
    required this.initialProfileId,
    super.key,
  });

  final WorkspaceController controller;
  final WorkspaceState state;
  final List<LaunchProfileOption> profiles;
  final Future<String?> Function(String? initialDirectory) pickDirectory;
  final String fallbackDirectory;
  final ValueChanged<String> onProfileSelected;
  final String? initialProfileId;

  @override
  State<LaunchAgentDialog> createState() => _LaunchAgentDialogState();
}

class _LaunchAgentDialogState extends State<LaunchAgentDialog> {
  final workspaceSearchController = TextEditingController();
  String? workspaceId;
  String? profileId;
  String workspaceQuery = '';
  bool selectCurrentAfterMutation = false;

  WorkspaceController get controller => widget.controller;
  WorkspaceState get workspaceState => widget.state;

  @override
  void initState() {
    super.initState();
    workspaceId = workspaceState.currentWorkspaceId;
    for (final profile in widget.profiles) {
      if (profile.id == widget.initialProfileId && profile.canLaunch) {
        profileId = profile.id;
        return;
      }
    }
    for (final profile in widget.profiles) {
      if (profile.canLaunch) {
        profileId = profile.id;
        break;
      }
    }
  }

  @override
  void didUpdateWidget(covariant LaunchAgentDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selectCurrentAfterMutation && widget.state.currentWorkspaceId != null) {
      workspaceId = widget.state.currentWorkspaceId;
      selectCurrentAfterMutation = false;
    } else if (workspaceId != null && selectedWorkspace == null) {
      workspaceId = null;
    }
  }

  Workspace? get selectedWorkspace {
    for (final workspace in workspaceState.workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return null;
  }

  LaunchProfileOption? get selectedProfile {
    for (final profile in widget.profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  List<Workspace> get visibleWorkspaces {
    final query = workspaceQuery.trim().toLowerCase();
    if (query.isEmpty) return workspaceState.workspaces;
    return workspaceState.workspaces
        .where(
          (workspace) =>
              workspace.name.toLowerCase().contains(query) ||
              workspace.path.toLowerCase().contains(query),
        )
        .toList();
  }

  void _searchWorkspaces(String value) {
    setState(() {
      workspaceQuery = value;
      final selected = selectedWorkspace;
      if (selected != null && !visibleWorkspaces.contains(selected)) {
        workspaceId = null;
      }
    });
  }

  void _clearWorkspaceSearch() {
    workspaceSearchController.clear();
    setState(() => workspaceQuery = '');
  }

  Future<void> _addWorkspace() async {
    if (workspaceState.isBusy) return;
    final path = await widget.pickDirectory(
      workspaceState.currentWorkspace?.path ?? widget.fallbackDirectory,
    );
    if (path == null || !mounted) return;
    final added = await controller.add(path);
    if (!added || !mounted) return;
    workspaceSearchController.clear();
    setState(() {
      workspaceQuery = '';
      selectCurrentAfterMutation = true;
    });
  }

  Future<void> _renameWorkspace(Workspace workspace) async {
    if (workspaceState.isBusy) return;
    await renameWorkspace(context, controller, workspace);
    if (!mounted) return;
    final selected = selectedWorkspace;
    if (selected != null && !visibleWorkspaces.contains(selected)) {
      setState(() => workspaceId = null);
    }
  }

  Future<void> _removeWorkspace(Workspace workspace) async {
    if (workspaceState.isBusy) return;
    await forgetWorkspace(context, controller, workspace);
    if (mounted && selectedWorkspace == null) setState(() {});
  }

  Future<void> _launch() async {
    final workspace = selectedWorkspace;
    final profile = selectedProfile;
    if (workspace == null || profile == null || workspaceState.isBusy) return;
    widget.onProfileSelected(profile.id);
    final launched = await controller.launch(
      profileId: profile.id,
      workspaceId: workspace.id,
    );
    if (launched && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    workspaceSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = viewport.width * .84;
    final height = viewport.height * .68;
    final launching = workspaceState.isLaunching;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: viewport.width * .04,
        vertical: viewport.height * .04,
      ),
      constraints: BoxConstraints(maxWidth: viewport.width * .92),
      title: Row(
        children: [
          const Icon(Icons.terminal_rounded, size: 20),
          const SizedBox(width: 9),
          const Expanded(child: Text('Lanzar agente')),
          AppIconButton(
            icon: Icons.close,
            tooltip: 'Cerrar',
            onPressed: launching ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useColumns = constraints.maxWidth >= 640;
            final workspacePanel = _WorkspacePickerPanel(
              key: const Key('launch-workspace-panel'),
              workspaces: visibleWorkspaces,
              hasWorkspaceHistory: workspaceState.workspaces.isNotEmpty,
              selectedId: workspaceId,
              searchController: workspaceSearchController,
              query: workspaceQuery,
              onSelected: (value) => setState(() => workspaceId = value.id),
              onSearch: _searchWorkspaces,
              onClearSearch: _clearWorkspaceSearch,
              onAdd: _addWorkspace,
              onRename: _renameWorkspace,
              onRemove: _removeWorkspace,
            );
            final accountPanel = _AccountPickerPanel(
              key: const Key('launch-account-panel'),
              profiles: widget.profiles,
              selectedId: profileId,
              onSelected: (value) => setState(() => profileId = value.id),
            );

            if (useColumns) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: workspacePanel),
                  const SizedBox(width: 12),
                  Expanded(child: accountPanel),
                ],
              );
            }

            final workspaceHeight = (height * .36).clamp(150.0, 240.0);
            return Column(
              children: [
                SizedBox(height: workspaceHeight, child: workspacePanel),
                const SizedBox(height: 12),
                Expanded(child: accountPanel),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: launching ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed:
              selectedWorkspace == null ||
                  selectedProfile == null ||
                  workspaceState.isBusy
              ? null
              : _launch,
          icon: launching
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.terminal_rounded, size: 17),
          label: const Text('Lanzar agente'),
        ),
      ],
    );
  }
}

class _WorkspacePickerPanel extends StatelessWidget {
  const _WorkspacePickerPanel({
    required this.workspaces,
    required this.hasWorkspaceHistory,
    required this.selectedId,
    required this.searchController,
    required this.query,
    required this.onSelected,
    required this.onSearch,
    required this.onClearSearch,
    required this.onAdd,
    required this.onRename,
    required this.onRemove,
    super.key,
  });

  final List<Workspace> workspaces;
  final bool hasWorkspaceHistory;
  final String? selectedId;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<Workspace> onSelected;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onAdd;
  final ValueChanged<Workspace> onRename;
  final ValueChanged<Workspace> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Text('Workspaces', style: theme.textTheme.titleMedium),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    key: const Key('launch-workspace-search'),
                    controller: searchController,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o ruta',
                      prefixIcon: const Icon(Icons.search, size: 15),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: onClearSearch,
                              icon: const Icon(Icons.close, size: 15),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AppIconButton(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: 'Añadir workspace',
                  onPressed: onAdd,
                ),
                const SizedBox(width: 3),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outline),
          Expanded(
            child: workspaces.isEmpty
                ? Center(
                    child: Text(
                      hasWorkspaceHistory
                          ? 'Sin coincidencias'
                          : 'Sin workspaces guardados',
                    ),
                  )
                : ListView.separated(
                    key: const Key('launch-workspace-list'),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    itemCount: workspaces.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final workspace = workspaces[index];
                      final selected = workspace.id == selectedId;
                      return _PickerRow(
                        selected: selected,
                        onTap: () => onSelected(workspace),
                        leading: Icon(
                          selected ? Icons.folder : Icons.folder_outlined,
                          size: 18,
                        ),
                        title: workspace.name,
                        subtitle: workspace.path,
                        action: SizedBox(
                          width: 30,
                          height: 30,
                          child: PopupMenuButton<String>(
                            tooltip: 'Administrar workspace',
                            icon: const Icon(Icons.more_vert, size: 16),
                            padding: EdgeInsets.zero,
                            position: PopupMenuPosition.under,
                            onSelected: (value) {
                              if (value == 'rename') {
                                onRename(workspace);
                              } else if (value == 'remove') {
                                onRemove(workspace);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Renombrar'),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Quitar del historial'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AccountPickerPanel extends StatefulWidget {
  const _AccountPickerPanel({
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<LaunchProfileOption> profiles;
  final String? selectedId;
  final ValueChanged<LaunchProfileOption> onSelected;

  @override
  State<_AccountPickerPanel> createState() => _AccountPickerPanelState();
}

enum _AccountSort { name, availability }

class _AccountPickerPanelState extends State<_AccountPickerPanel> {
  static const itemExtent = 84.0;
  static const itemSpacing = 2.0;
  static const gridPadding = 5.0;

  final scrollController = ScrollController();
  String? scrolledSelectionId;
  int? scrolledColumnCount;
  _AccountSort sort = _AccountSort.name;

  @override
  void didUpdateWidget(covariant _AccountPickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.profiles, widget.profiles)) {
      scrolledSelectionId = null;
    }
  }

  void _scrollToSelection(
    int columnCount,
    List<LaunchProfileOption> sortedProfiles,
  ) {
    final selectedId = widget.selectedId;
    if (selectedId == null ||
        (scrolledSelectionId == selectedId &&
            scrolledColumnCount == columnCount)) {
      return;
    }
    final index = sortedProfiles.indexWhere(
      (profile) => profile.id == selectedId,
    );
    if (index < 0) return;
    scrolledSelectionId = selectedId;
    scrolledColumnCount = columnCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.selectedId != selectedId ||
          !scrollController.hasClients) {
        return;
      }
      final position = scrollController.position;
      final itemStart =
          gridPadding + (index ~/ columnCount) * (itemExtent + itemSpacing);
      final itemEnd = itemStart + itemExtent;
      final viewportStart = position.pixels;
      final viewportEnd = viewportStart + position.viewportDimension;
      if (itemStart >= viewportStart && itemEnd <= viewportEnd) return;
      final centered =
          itemStart - (position.viewportDimension - itemExtent) / 2;
      final target = centered
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedProfiles = [...widget.profiles]
      ..sort((left, right) {
        if (sort == _AccountSort.availability) {
          final availability = (right.availablePercent ?? -1).compareTo(
            left.availablePercent ?? -1,
          );
          if (availability != 0) return availability;
        }
        final name = left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        );
        if (name != 0) return name;
        return left.id.compareTo(right.id);
      });
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cuenta para lanzar',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${widget.profiles.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: PopupMenuButton<_AccountSort>(
                    tooltip: 'Ordenar cuentas',
                    initialValue: sort,
                    icon: Icon(
                      sort == _AccountSort.name
                          ? Icons.sort_by_alpha
                          : Icons.percent,
                      size: 17,
                    ),
                    padding: EdgeInsets.zero,
                    position: PopupMenuPosition.under,
                    onSelected: (value) {
                      if (value == sort) return;
                      setState(() {
                        sort = value;
                        scrolledSelectionId = null;
                      });
                    },
                    itemBuilder: (context) => [
                      CheckedPopupMenuItem(
                        value: _AccountSort.name,
                        checked: sort == _AccountSort.name,
                        child: const Text('Nombre (A-Z)'),
                      ),
                      CheckedPopupMenuItem(
                        value: _AccountSort.availability,
                        checked: sort == _AccountSort.availability,
                        child: const Text('Disponibilidad'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outline),
          Expanded(
            child: widget.profiles.isEmpty
                ? const Center(child: Text('Sin cuentas disponibles'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columnCount = constraints.maxWidth >= 620 ? 2 : 1;
                      _scrollToSelection(columnCount, sortedProfiles);
                      return GridView.builder(
                        key: const Key('launch-account-list'),
                        controller: scrollController,
                        padding: const EdgeInsets.all(gridPadding),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columnCount,
                          mainAxisExtent: itemExtent,
                          crossAxisSpacing: itemSpacing,
                          mainAxisSpacing: itemSpacing,
                        ),
                        itemCount: sortedProfiles.length,
                        itemBuilder: (context, index) {
                          final profile = sortedProfiles[index];
                          final selected = profile.id == widget.selectedId;
                          return Opacity(
                            opacity: profile.canLaunch ? 1 : .46,
                            child: _PickerRow(
                              key: ValueKey('launch-account-${profile.id}'),
                              selected: selected,
                              onTap: profile.canLaunch
                                  ? () => widget.onSelected(profile)
                                  : null,
                              leading: ProfileProviderIcon(
                                toolKey: profile.toolKey,
                                size: 24,
                              ),
                              title: profile.displayName,
                              subtitle: profile.subtitle,
                              footer: _LaunchAvailability(profile: profile),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    super.key,
    this.action,
    this.footer,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: .09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: footer == null ? 58 : 82,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (footer != null) ...[
                          const SizedBox(height: 5),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (action != null) ...[action!, const SizedBox(width: 3)],
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 17,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchAvailability extends StatelessWidget {
  const _LaunchAvailability({required this.profile});

  final LaunchProfileOption profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = profile.availablePercent;
    final color = remaining == null
        ? theme.colorScheme.onSurfaceVariant
        : remaining <= 10
        ? theme.colorScheme.error
        : remaining <= 25
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Row(
      children: [
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: 0,
              end: remaining == null ? 0 : remaining / 100,
            ),
            duration: const Duration(milliseconds: 620),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              key: ValueKey('launch-account-availability-${profile.id}'),
              value: value,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          remaining == null
              ? 'Sin porcentaje'
              : '${remaining.toStringAsFixed(0)}% disponible',
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
