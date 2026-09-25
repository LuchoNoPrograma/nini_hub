import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/formatters.dart';
import 'package:nini_hub/core/widgets/app_primitives.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/presentation/account_dialogs.dart';
import 'package:nini_hub/features/accounts/presentation/accounts_quota_clock.dart';
import 'package:nini_hub/features/accounts/presentation/controllers/accounts_controller.dart';
import 'package:nini_hub/features/accounts/presentation/state/accounts_state.dart';
import 'package:nini_hub/features/heartbeat/domain/heartbeat_policy.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/presentation/profile_dialogs.dart';
import 'package:nini_hub/features/profiles/presentation/profile_provider_icon.dart';
import 'package:nini_hub/features/usage/application/usage_account_projection.dart';
import 'package:nini_hub/features/usage/domain/quota_reset_anchor_policy.dart';
import 'package:nini_hub/features/usage/presentation/state/usage_state.dart';
import 'package:nini_hub/features/workspaces/presentation/launch_agent_dialog.dart';

Future<void> showCreateProfileFlow(BuildContext context, WidgetRef ref) async {
  if (_profilesBusy(context, ref)) return;
  final controller = ref.read(accountsControllerProvider.notifier);
  controller.clearFailure();
  await showCreateProfileDialog(
    context,
    readError: () => ref.read(accountsControllerProvider).errorMessage,
    create: (command) async {
      final method = await showAccountAuthMethodDialog(
        context,
        title: 'Elige cómo vincular el nuevo perfil',
      );
      if (method == null || !context.mounted) return null;
      return controller.createLinkedAccount(
        command,
        method: method,
        authenticate: (profile, session, method) async {
          if (!context.mounted) return false;
          return showPendingAccountAuthDialog(
            context,
            profile,
            session,
            method,
          );
        },
      );
    },
  );
}

Future<void> _renameProfileFlow(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  if (_profilesBusy(context, ref)) return;
  final renamed = await showRenameProfileDialog(
    context,
    controller: ref.read(profilesControllerProvider.notifier),
    readState: () => ref.read(profilesControllerProvider),
    profileId: account.profile.id,
    toolKey: account.profile.toolKey,
    profileName: account.profile.profileName,
  );
  if (renamed == null || !context.mounted) return;
  await _reloadAccounts(context, ref);
}

Future<void> _deleteProfileFlow(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  if (_profilesBusy(context, ref)) return;
  final deleted = await showDeleteProfileDialog(
    context,
    controller: ref.read(profilesControllerProvider.notifier),
    readState: () => ref.read(profilesControllerProvider),
    profileId: account.profile.id,
    displayName: _profileTitle(account),
  );
  if (!deleted || !context.mounted) return;
  await _reloadAccounts(context, ref, removedProfileId: account.profile.id);
}

Future<bool> _reloadAccounts(
  BuildContext context,
  WidgetRef ref, {
  String? removedProfileId,
}) async {
  final loaded = await ref
      .read(accountsControllerProvider.notifier)
      .load(removedProfileId: removedProfileId);
  if (loaded) return true;
  if (context.mounted) {
    final message = ref.read(accountsControllerProvider).errorMessage;
    _showProfileFlowError(
      context,
      StateError(message ?? 'No se pudieron cargar las cuentas.'),
    );
  }
  return false;
}

Future<void> _showDeviceAuth(
  BuildContext context,
  WidgetRef ref,
  Account account, {
  AccountAuthMethod? method,
  bool isNewProfile = false,
}) => showDeviceAuthDialog(
  context,
  account,
  method: method,
  isNewProfile: isNewProfile,
  start: (account) async {
    final session = await ref
        .read(accountsControllerProvider.notifier)
        .startDeviceAuth(account);
    if (session != null) return session;
    final state = ref.read(accountsControllerProvider);
    throw state.failure ??
        StateError(state.errorMessage ?? 'No se pudo iniciar la vinculación.');
  },
  startBrowser: (account) async {
    final session = await ref
        .read(accountsControllerProvider.notifier)
        .startDeviceAuth(account, method: AccountAuthMethod.browser);
    if (session != null) return session;
    final state = ref.read(accountsControllerProvider);
    throw state.failure ??
        StateError(state.errorMessage ?? 'No se pudo iniciar la vinculación.');
  },
  complete: (account, success) async {
    final completed = await ref
        .read(accountsControllerProvider.notifier)
        .completeDeviceAuth(account, success);
    if (completed) return;
    final state = ref.read(accountsControllerProvider);
    throw state.failure ??
        StateError(
          state.errorMessage ?? 'No se pudo completar la vinculación.',
        );
  },
);

bool _profilesBusy(BuildContext context, WidgetRef ref) {
  if (!ref.read(profilesControllerProvider).isBusy) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Ya hay una operación de perfiles en curso.')),
  );
  return true;
}

void _showProfileFlowError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
  );
}

Future<void> _openLaunchAgentDialog(
  BuildContext context,
  WidgetRef ref, {
  String? initialProfileId,
}) async {
  final state = ref.read(workspaceControllerProvider);
  if (state.isBusy) return;
  final loaded = await ref.read(workspaceControllerProvider.notifier).load();
  if (!context.mounted) return;
  if (!loaded) {
    final message = ref.read(workspaceControllerProvider).errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, dialogRef, _) {
        dialogRef.listen(workspaceControllerProvider, (previous, next) {
          final message = next.errorMessage;
          if (message == null || identical(previous?.failure, next.failure)) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        });
        final accountsState = dialogRef.watch(accountsControllerProvider);
        return LaunchAgentDialog(
          controller: dialogRef.read(workspaceControllerProvider.notifier),
          state: dialogRef.watch(workspaceControllerProvider),
          profiles: accountsState.accounts.map(_launchProfileOption).toList(),
          pickDirectory: dialogRef.read(workspaceDirectoryPickerProvider),
          fallbackDirectory: dialogRef.read(workspaceFallbackDirectoryProvider),
          onProfileSelected: dialogRef
              .read(accountsControllerProvider.notifier)
              .selectAccount,
          initialProfileId: initialProfileId ?? accountsState.selectedProfileId,
        );
      },
    ),
  );
}

LaunchProfileOption _launchProfileOption(Account account) {
  final provider = profileProvider(account.profile.toolKey);
  return LaunchProfileOption(
    id: account.profile.id,
    toolKey: account.profile.toolKey,
    displayName: _profileTitle(account),
    subtitle: _launchProfileSubtitle(account, provider),
    canLaunch: _canLaunchAccount(account, provider),
    availablePercent: account.operationalAvailablePercent,
  );
}

bool _canLaunchAccount(Account account, [ProfileProvider? accountProvider]) {
  final provider = accountProvider ?? profileProvider(account.profile.toolKey);
  return account.profile.isAvailable &&
      (account.profile.hasAuthFile || !provider.supportsDeviceAuth);
}

String _profileTitle(Account account) =>
    account.profile.source == ProfileSource.defaultProfile &&
        const [
          'main',
          'principal',
          'codex principal',
          'codex main',
        ].contains(account.profile.displayName.trim().toLowerCase())
    ? 'Perfil principal'
    : account.profile.displayName;

String _launchProfileSubtitle(Account account, ProfileProvider provider) {
  if (account.isDeactivated) return 'Desactivada en este equipo';
  if (!account.profile.isAvailable) return 'Perfil no disponible';
  if (!account.profile.hasAuthFile && provider.supportsDeviceAuth) {
    return 'Cuenta sin vincular';
  }
  if (account.displayEmail.isNotEmpty) return account.displayEmail;
  return account.profile.commandName ?? provider.executable;
}

class AccountsView extends ConsumerWidget {
  const AccountsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsControllerProvider);
    final accountsController = ref.read(accountsControllerProvider.notifier);
    final usageState = ref.watch(usageControllerProvider);
    final heartbeatState = ref.watch(heartbeatControllerProvider);
    final workspaceBusy = ref.watch(
      workspaceControllerProvider.select((state) => state.isBusy),
    );
    final profilesBusy = ref.watch(
      profilesControllerProvider.select((state) => state.isBusy),
    );
    final quotaNow =
        ref.watch(accountsQuotaClockProvider).asData?.value ?? DateTime.now();
    final cardLayout = ref.watch(settingsCardLayoutProvider);
    if (!accountsState.isInitialized) {
      if (accountsState.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudieron cargar las cuentas',
        message:
            accountsState.errorMessage ??
            'Intenta cargar las cuentas otra vez.',
        action: FilledButton.icon(
          onPressed: accountsState.isBusy ? null : accountsController.load,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      );
    }
    const projectUsageAccount = ProjectUsageAccount();
    final accounts = [
      for (final account in accountsState.accounts)
        if (usageState.latestSnapshotByProfile[account.profile.id]
            case final snapshot?)
          projectUsageAccount(account, snapshot)
        else
          account,
    ];
    final statusCounts = <AccountStatus, int>{};
    for (final account in accounts) {
      statusCounts.update(
        account.status,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final recent = accounts
        .map((item) => item.currentCheck?.startedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (latest, value) {
          if (latest == null || value.isAfter(latest)) return value;
          return latest;
        });
    final visibleAccounts = AccountSnapshot(
      accounts,
    ).visible(accountsState.query);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Perfiles de IA',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    _SummaryBand(
                      total: accounts.length,
                      statusCounts: statusCounts,
                      recent: recent,
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton.icon(
                      onPressed: accounts.isEmpty || workspaceBusy
                          ? null
                          : () => _openLaunchAgentDialog(context, ref),
                      icon: const Icon(Icons.terminal_rounded, size: 18),
                      label: const Text('Lanzar agente'),
                    ),
                    OutlinedButton.icon(
                      onPressed: profilesBusy
                          ? null
                          : () => showCreateProfileFlow(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nuevo perfil'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 850) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), actions],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    actions,
                  ],
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          sliver: SliverToBoxAdapter(
            child: _AccountFilters(
              controller: accountsController,
              state: accountsState,
            ),
          ),
        ),
        if (accountsState.authRefreshingProfileIds.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text(
                'Acceso confirmado. Actualizando cuotas en segundo plano…',
              ),
            ),
          ),
        for (final entry in accountsState.authRefreshFailures.entries)
          if (accountsState.snapshot.findById(entry.key) case final account?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${account.profile.displayName}: ${entry.value}'),
                    TextButton(
                      onPressed: accountsState.isBusy
                          ? null
                          : () => accountsController.refreshAuthUsage(account),
                      child: const Text('Reintentar cuotas'),
                    ),
                  ],
                ),
              ),
            ),
        if (visibleAccounts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: accounts.isEmpty
                  ? Icons.account_tree_outlined
                  : Icons.search_off,
              title: accounts.isEmpty
                  ? 'No hay perfiles de IA'
                  : 'No hay coincidencias',
              message: accounts.isEmpty
                  ? 'Crea un perfil en Nini Hub y vincula tu cuenta para empezar.'
                  : 'Cambia la búsqueda o el filtro de estado.',
              action: accounts.isEmpty
                  ? FilledButton.icon(
                      onPressed: profilesBusy
                          ? null
                          : () => showCreateProfileFlow(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear perfil'),
                    )
                  : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final columns = width >= 1800
                    ? 4
                    : width >= 1120
                    ? 3
                    : width >= 720
                    ? 2
                    : 1;
                const spacing = 10.0;
                final extent = (width - spacing * (columns - 1)) / columns;
                final fontSize = Theme.of(
                  context,
                ).textTheme.bodyMedium!.fontSize!;
                final systemScale =
                    MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
                final densityScale =
                    cardLayout.fontScale.clamp(.8, 1.2) / .9 * systemScale;
                final cardExtent = _accountCardExtent(
                  accounts: visibleAccounts,
                  compact: cardLayout.compactCards,
                  densityScale: densityScale,
                );
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    mainAxisExtent: cardExtent,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final account = visibleAccounts[index];
                    final supportsUsage = profileProvider(
                      account.profile.toolKey,
                    ).supportsUsage;
                    final usageRefreshStage = supportsUsage
                        ? usageState.stageForProfile(account.profile.id)
                        : UsageProfileRefreshStage.idle;
                    return SizedBox(
                          width: extent,
                          child: AccountCard(
                            account: account,
                            quotaNow: quotaNow,
                            refreshing:
                                accountsState.authRefreshingProfileIds.contains(
                                  account.profile.id,
                                ) ||
                                heartbeatState.isRunningProfile(
                                  account.profile.id,
                                ) ||
                                usageRefreshStage ==
                                    UsageProfileRefreshStage.running,
                            usageRefreshStage: usageRefreshStage,
                            usageFailureMessage: usageState
                                .failureForProfile(account.profile.id)
                                ?.message,
                            usageActionsDisabled:
                                accountsState.authRefreshingProfileIds.contains(
                                  account.profile.id,
                                ) ||
                                usageState.isRefreshingAll ||
                                usageState.isSynchronizing,
                            compact: cardLayout.compactCards,
                            accountBusy:
                                accountsState.authRefreshingProfileIds.contains(
                                  account.profile.id,
                                ) ||
                                accountsState.operationProfileId ==
                                    account.profile.id,
                            profileMutationBusy:
                                profilesBusy ||
                                accountsState.authRefreshingProfileIds.contains(
                                  account.profile.id,
                                ),
                            onEditAccount: () => showEditAccountDialog(
                              context,
                              accountsController,
                              () => ref.read(accountsControllerProvider),
                              account,
                            ),
                            onHeartbeat: (account) async {
                              final profileId = account.profile.id;
                              final completed = await ref
                                  .read(heartbeatControllerProvider.notifier)
                                  .run(
                                    profileId: profileId,
                                    expectedWindowMinutes:
                                        _heartbeatWindowMinutes(account),
                                  );
                              if (!completed) {
                                final state = ref.read(
                                  heartbeatControllerProvider,
                                );
                                throw StateError(
                                  state.failureForProfile(profileId)?.message ??
                                      state
                                          .resultForProfile(profileId)
                                          ?.message ??
                                      'No se pudo completar el heartbeat.',
                                );
                              }
                              if (!context.mounted) return;
                              final message = ref
                                  .read(heartbeatControllerProvider)
                                  .resultForProfile(profileId)
                                  ?.message;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    message ?? 'Heartbeat completado.',
                                  ),
                                ),
                              );
                            },
                            onRefresh: (account) async {
                              await ref
                                  .read(usageRefreshCoordinatorProvider)
                                  .refreshOne(account.profile.id);
                            },
                            onDeviceAuth: (account) =>
                                _showDeviceAuth(context, ref, account),
                            onRenameProfile: (account) =>
                                _renameProfileFlow(context, ref, account),
                            onDeleteProfile: (account) =>
                                _deleteProfileFlow(context, ref, account),
                            onLaunchAgent: (profileId) =>
                                _openLaunchAgentDialog(
                                  context,
                                  ref,
                                  initialProfileId: profileId,
                                ),
                          ),
                        )
                        .animate(delay: (index * 45).ms)
                        .fadeIn(duration: 260.ms)
                        .moveY(begin: 10, end: 0, curve: Curves.easeOutCubic);
                  }, childCount: visibleAccounts.length),
                );
              },
            ),
          ),
      ],
    );
  }
}

double _accountCardExtent({
  required Iterable<Account> accounts,
  required bool compact,
  required double densityScale,
}) {
  var maximumWindowCount = 0;
  for (final account in accounts) {
    final count = account.visibleWindows.length;
    if (count > maximumWindowCount) maximumWindowCount = count;
  }
  // Compact mode reduces secondary details; it must never hide a limiting quota.
  final baseExtent = compact ? 142.0 : 154.0;
  // Buttons, padding and quota bars retain their size when only text shrinks.
  final fixedExtent = 2 * 38 + 2 * (compact ? 7 : 8) + maximumWindowCount * 9;
  final textExtent = baseExtent + maximumWindowCount * 32 - fixedExtent;
  return fixedExtent + textExtent * densityScale;
}

int? _heartbeatWindowMinutes(Account account) {
  final windows = account.visibleWindows
      .where(
        (window) =>
            window.windowDurationMinutes != null &&
            window.windowDurationMinutes! > 0,
      )
      .toList();
  for (final preferred in const [
    HeartbeatPolicy.primaryMinutes,
    HeartbeatPolicy.weeklyMinutes,
  ]) {
    for (final window in windows) {
      final duration = window.windowDurationMinutes!;
      if ((duration - preferred).abs() <= 60) return duration;
    }
  }
  final codexWindows = windows
      .where((window) => window.limitId.toLowerCase() == 'codex')
      .toList();
  final fallback = codexWindows.isEmpty ? windows : codexWindows;
  fallback.sort(
    (left, right) =>
        left.windowDurationMinutes!.compareTo(right.windowDurationMinutes!),
  );
  return fallback.isEmpty ? null : fallback.first.windowDurationMinutes;
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({
    required this.total,
    required this.statusCounts,
    required this.recent,
  });

  final int total;
  final Map<AccountStatus, int> statusCounts;
  final DateTime? recent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Text('$total perfiles', style: theme.textTheme.bodySmall),
        for (final status in AccountStatus.values)
          if ((statusCounts[status] ?? 0) > 0)
            Text(
              '${statusCounts[status]} ${_statusLabel(status, plural: statusCounts[status] != 1).toLowerCase()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _statusColor(context, status),
              ),
            ),
        Tooltip(
          message: 'Última consulta: ${formatDateTime(recent)}',
          child: Text(
            relativeTime(recent),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountFilters extends StatelessWidget {
  const _AccountFilters({required this.controller, required this.state});
  final AccountsController controller;
  final AccountsState state;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final search = TextFormField(
        initialValue: state.query.search,
        onChanged: controller.setSearch,
        decoration: const InputDecoration(
          hintText: 'Buscar perfil o correo',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
      );
      final filters = Wrap(
        spacing: 5,
        runSpacing: 4,
        children: [
          for (final filter in AccountStatusFilter.values)
            _FilterItem(
              label: filter.accountStatus == null
                  ? 'Todos'
                  : _statusLabel(filter.accountStatus!, plural: true),
              color: filter.accountStatus == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : _statusColor(context, filter.accountStatus!),
              selected: state.query.status == filter,
              onTap: () => controller.setStatusFilter(filter),
            ),
        ],
      );
      final sort = DropdownButtonFormField<AccountSortMode>(
        initialValue: state.query.sort,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Ordenar por',
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: const [
          DropdownMenuItem(value: AccountSortMode.name, child: Text('Nombre')),
          DropdownMenuItem(
            value: AccountSortMode.availability,
            child: Text('Disponibilidad'),
          ),
          DropdownMenuItem(
            value: AccountSortMode.renewal,
            child: Text('Renovación'),
          ),
          DropdownMenuItem(
            value: AccountSortMode.reset,
            child: Text('Próximo reinicio'),
          ),
        ],
        onChanged: (value) {
          if (value != null) controller.setSort(value);
        },
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              SizedBox(width: 180, child: sort),
            ],
          ),
          const SizedBox(height: 8),
          filters,
        ],
      );
    },
  );
}

class _FilterItem extends StatelessWidget {
  const _FilterItem({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      labelPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(
        color: selected
            ? color.withValues(alpha: .55)
            : theme.colorScheme.outline,
      ),
      selectedColor: color.withValues(alpha: .1),
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class AccountCard extends StatefulWidget {
  const AccountCard({
    required this.account,
    this.quotaNow,
    required this.refreshing,
    required this.compact,
    required this.accountBusy,
    required this.profileMutationBusy,
    required this.onEditAccount,
    required this.onHeartbeat,
    required this.onRefresh,
    required this.onDeviceAuth,
    required this.onRenameProfile,
    required this.onDeleteProfile,
    required this.onLaunchAgent,
    this.usageRefreshStage = UsageProfileRefreshStage.idle,
    this.usageFailureMessage,
    this.usageActionsDisabled = false,
    super.key,
  });

  final Account account;
  final DateTime? quotaNow;
  final bool refreshing;
  final UsageProfileRefreshStage usageRefreshStage;
  final String? usageFailureMessage;
  final bool usageActionsDisabled;
  final bool compact;
  final bool accountBusy;
  final bool profileMutationBusy;
  final Future<void> Function() onEditAccount;
  final Future<void> Function(Account account) onHeartbeat;
  final Future<void> Function(Account account) onRefresh;
  final Future<void> Function(Account account) onDeviceAuth;
  final Future<void> Function(Account account) onRenameProfile;
  final Future<void> Function(Account account) onDeleteProfile;
  final ValueChanged<String> onLaunchAgent;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool hovered = false;

  Future<void> _guard(Future<void> future) async {
    try {
      await future;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _startHeartbeat() async {
    final confirmed = await showCodexHeartbeatConfirmation(
      context,
      widget.account,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.onHeartbeat(widget.account);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = widget.account;
    final quotaNow = widget.quotaNow ?? DateTime.now();
    final provider = profileProvider(account.profile.toolKey);
    final launchable = _canLaunchAccount(account, provider);
    final stateColor = _stateColor(context, account);
    final allWindows = account.visibleWindows;
    final shownWindowCount = allWindows.length;
    final windows = allWindows.take(shownWindowCount).toList();
    final windowTitles = _quotaWindowTitles(
      allWindows,
    ).take(shownWindowCount).toList();
    final hiddenWindowCount = allWindows.length - shownWindowCount;
    return Theme(
      data: theme,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: hovered
                ? theme.colorScheme.surfaceContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: hovered
                  ? theme.colorScheme.primary.withValues(alpha: .42)
                  : theme.colorScheme.outline,
            ),
            boxShadow: hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          padding: EdgeInsets.all(widget.compact ? 7 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(color: stateColor, size: 7),
                  const SizedBox(width: 8),
                  ProfileProviderIcon(
                    toolKey: account.profile.toolKey,
                    size: 24,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _profileTitle(account),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            if (account.profile.isFavorite) ...[
                              const SizedBox(width: 5),
                              Icon(
                                Icons.star,
                                size: 13,
                                color: theme.colorScheme.tertiary,
                              ),
                            ],
                            const SizedBox(width: 7),
                            _StateBadge(account: account, color: stateColor),
                          ],
                        ),
                        ...[
                          const SizedBox(height: 1),
                          Tooltip(
                            message:
                                account.profile.commandName ??
                                provider.executable,
                            child: Row(
                              children: [
                                Text(
                                  provider.displayName,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '·',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    account.profile.source ==
                                            ProfileSource.defaultProfile
                                        ? 'Sesión habitual'
                                        : accountProfileConfigurationLabel(
                                            account.profile,
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Editar datos de la cuenta',
                    onPressed: widget.accountBusy
                        ? null
                        : () => unawaited(widget.onEditAccount()),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: PopupMenuButton<String>(
                      tooltip: 'Más acciones',
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      position: PopupMenuPosition.under,
                      menuPadding: const EdgeInsets.symmetric(vertical: 4),
                      constraints: const BoxConstraints.tightFor(width: 196),
                      onSelected: (value) {
                        if (value == 'device-auth') {
                          unawaited(widget.onDeviceAuth(account));
                        } else if (value == 'rename') {
                          unawaited(widget.onRenameProfile(account));
                        } else if (value == 'delete') {
                          unawaited(widget.onDeleteProfile(account));
                        } else if (value == 'heartbeat') {
                          unawaited(_startHeartbeat());
                        }
                      },
                      itemBuilder: (context) => [
                        if (!account.isDeactivated &&
                            account.profile.hasAuthFile &&
                            provider.supportsDeviceAuth)
                          PopupMenuItem(
                            value: 'device-auth',
                            enabled:
                                account.profile.isAvailable &&
                                !widget.accountBusy,
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Row(
                              children: [
                                Icon(Icons.link, size: 15),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Revincular cuenta',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (account.profile.toolKey == 'codex')
                          PopupMenuItem(
                            value: 'heartbeat',
                            enabled:
                                account.profile.isAvailable &&
                                account.profile.hasAuthFile &&
                                !widget.refreshing &&
                                !widget.usageActionsDisabled,
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Row(
                              children: [
                                Icon(Icons.monitor_heart_outlined, size: 15),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Iniciar ciclo',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'rename',
                          enabled:
                              !widget.profileMutationBusy &&
                              account.profile.isManagedByMultiCli &&
                              !account.isDeactivated,
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: const Row(
                            children: [
                              Icon(Icons.drive_file_rename_outline, size: 15),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Cambiar identificador',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          enabled:
                              !widget.profileMutationBusy &&
                              account.profile.isManagedByMultiCli,
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 15,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Eliminar perfil',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (account.isDeactivated ||
                          account.currentCheck?.state !=
                              AccountUsageState.success) ...[
                        const SizedBox(height: 2),
                        _StateLine(
                          account: account,
                          color: stateColor,
                          showBadge: false,
                        ),
                      ],
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: _InlineInfo(
                              icon: Icons.workspace_premium_outlined,
                              value: account.displayPlan.isEmpty
                                  ? 'No detectado'
                                  : account.displayPlan,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InlineInfo(
                              icon: Icons.alternate_email,
                              value: account.displayEmail.isEmpty
                                  ? 'Sin correo observado'
                                  : account.displayEmail,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (windows.isEmpty)
                        _NoUsageData(account: account)
                      else
                        for (var index = 0; index < windows.length; index++)
                          _QuotaBar(
                            window: windows[index],
                            blockingWindow: account.blockingWindowFor(
                              windows[index],
                            ),
                            historical: !account.hasCurrentQuota,
                            title: windowTitles[index],
                            now: quotaNow,
                            resetConfidence: account.resetAnchorConfidence(
                              windows[index],
                            ),
                          ),
                      if (provider.supportsUsage)
                        _ResetCreditsLine(account: account, now: quotaNow),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child:
                        account.metadata?.nextRenewalOn == null &&
                            account.costShares.isEmpty
                        ? const SizedBox.shrink()
                        : _BillingLine(account: account),
                  ),
                  if (!account.isDeactivated &&
                      !account.profile.hasAuthFile &&
                      provider.supportsDeviceAuth)
                    AppIconButton(
                      icon: Icons.link,
                      tooltip: 'Vincular cuenta',
                      onPressed: widget.accountBusy
                          ? null
                          : () => unawaited(widget.onDeviceAuth(account)),
                    ),
                  AppIconButton(
                    icon: Icons.terminal_rounded,
                    tooltip: 'Lanzar agente con ${account.profile.displayName}',
                    color: launchable
                        ? theme.colorScheme.primary
                        : theme.disabledColor,
                    onPressed: launchable
                        ? () => widget.onLaunchAgent(account.profile.id)
                        : null,
                  ),
                  if (provider.supportsUsage &&
                      account.currentCheck?.state == AccountUsageState.success)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _QuotaSnapshotAge(
                        profileId: account.profile.id,
                        checkedAt: account.currentCheck!.startedAt,
                        hiddenWindowCount: hiddenWindowCount,
                      ),
                    ),
                  if (provider.supportsUsage &&
                      widget.usageRefreshStage != UsageProfileRefreshStage.idle)
                    _UsageRefreshIndicator(
                      profileId: account.profile.id,
                      stage: widget.usageRefreshStage,
                      failureMessage: widget.usageFailureMessage,
                    )
                  else if (widget.refreshing && provider.supportsUsage)
                    const SizedBox(
                      width: 38,
                      height: 38,
                      child: Center(
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                    )
                  else if (provider.supportsUsage)
                    AppIconButton(
                      icon: Icons.refresh,
                      tooltip: 'Consultar sólo esta cuenta',
                      onPressed: widget.usageActionsDisabled
                          ? null
                          : () => _guard(widget.onRefresh(account)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageRefreshIndicator extends StatelessWidget {
  const _UsageRefreshIndicator({
    required this.profileId,
    required this.stage,
    required this.failureMessage,
  });

  final String profileId;
  final UsageProfileRefreshStage stage;
  final String? failureMessage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (message, child) = switch (stage) {
      UsageProfileRefreshStage.queued => (
        'En cola para consultar',
        Icon(Icons.schedule_rounded, size: 17, color: colors.onSurfaceVariant),
      ),
      UsageProfileRefreshStage.running => (
        'Consultando cuotas',
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.8),
        ),
      ),
      UsageProfileRefreshStage.completed => (
        'Cuotas actualizadas',
        Icon(Icons.check_circle_outline, size: 18, color: colors.primary),
      ),
      UsageProfileRefreshStage.failed => (
        failureMessage ?? 'No se pudo actualizar esta cuenta',
        Icon(Icons.error_outline, size: 18, color: colors.error),
      ),
      UsageProfileRefreshStage.idle => ('', const SizedBox.shrink()),
    };
    return Tooltip(
      message: message,
      child: SizedBox(
        key: ValueKey('usage-refresh-${stage.name}-$profileId'),
        width: 38,
        height: 38,
        child: Center(child: child),
      ),
    );
  }
}

class _StateLine extends StatelessWidget {
  const _StateLine({
    required this.account,
    required this.color,
    this.showBadge = true,
  });

  final Account account;
  final Color color;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = account.currentCheck;
    return Row(
      children: [
        if (showBadge) ...[
          _StateBadge(account: account, color: color),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            _stateDetail(account),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          relativeTime(
            current?.startedAt ?? account.lastSuccessfulCheck?.startedAt,
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.account, required this.color});

  final Account account;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Text(
      _stateLabel(account),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _NoUsageData extends StatelessWidget {
  const _NoUsageData({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = profileProvider(account.profile.toolKey);
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        !provider.supportsUsage
            ? 'Cuotas no disponibles para ${provider.productName}.'
            : account.currentCheck == null
            ? 'Actualiza para consultar límites oficiales.'
            : 'La fuente no devolvió ventanas de cuota.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

List<String> _quotaWindowTitles(List<AccountQuotaWindow> windows) {
  final baseTitles = [
    for (final window in windows)
      formatQuotaWindowLabel(window.windowDurationMinutes, window.windowType),
  ];
  final limitIds = windows
      .map((window) => window.limitId.trim().toLowerCase())
      .where((limitId) => limitId.isNotEmpty)
      .toSet();
  final hasMultipleLimits = limitIds.length > 1;

  return [
    for (var index = 0; index < windows.length; index++)
      if (hasMultipleLimits)
        '${_quotaLimitQualifier(windows[index], windows)} · ${baseTitles[index]}'
      else if (baseTitles.where((title) => title == baseTitles[index]).length ==
          1)
        baseTitles[index]
      else
        '${_quotaWindowQualifier(windows[index], windows, baseTitles[index], baseTitles)} · ${baseTitles[index]}',
  ];
}

String _quotaLimitQualifier(
  AccountQuotaWindow window,
  List<AccountQuotaWindow> windows,
) {
  final labelByLimitId = <String, String>{};
  for (final item in windows) {
    final limitId = item.limitId.trim();
    if (limitId.isEmpty || labelByLimitId.containsKey(limitId.toLowerCase())) {
      continue;
    }
    labelByLimitId[limitId.toLowerCase()] = _quotaLimitLabel(item);
  }
  final preferredLabels = labelByLimitId.values.toList();
  if (_areDistinct(preferredLabels)) return _quotaLimitLabel(window);
  return window.limitId.trim().isEmpty
      ? window.windowType
      : window.limitId.trim();
}

String _quotaLimitLabel(AccountQuotaWindow window) {
  final limitName = _nonEmpty(window.limitName);
  if (limitName != null) return limitName;
  final limitId = window.limitId.trim();
  return limitId.toLowerCase() == 'codex' ? 'Codex' : limitId;
}

String _quotaWindowQualifier(
  AccountQuotaWindow window,
  List<AccountQuotaWindow> windows,
  String baseTitle,
  List<String> baseTitles,
) {
  final colliding = [
    for (var index = 0; index < windows.length; index++)
      if (baseTitles[index] == baseTitle) windows[index],
  ];
  String source(AccountQuotaWindow item) =>
      _nonEmpty(item.limitName) ?? _nonEmpty(item.limitId) ?? '';
  final preferredSources = colliding.map(source).toList();
  if (_areDistinct(preferredSources)) return source(window);

  final limitIds = colliding.map((item) => item.limitId.trim()).toList();
  if (_areDistinct(limitIds)) return window.limitId.trim();

  final sourceLabel = source(window);
  if (sourceLabel.isEmpty) return window.windowType;
  final windowTypeLabel = formatQuotaWindowLabel(null, window.windowType);
  return '$sourceLabel · $windowTypeLabel';
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

bool _areDistinct(List<String> values) =>
    values.every((value) => value.isNotEmpty) &&
    values.map((value) => value.toLowerCase()).toSet().length == values.length;

class _QuotaBar extends StatelessWidget {
  const _QuotaBar({
    required this.window,
    required this.title,
    required this.now,
    required this.resetConfidence,
    this.blockingWindow,
    this.historical = false,
  });
  final AccountQuotaWindow window;
  final AccountQuotaWindow? blockingWindow;
  final String title;
  final DateTime now;
  final QuotaResetAnchorConfidence resetConfidence;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = window.remainingPercent;
    final blocked = blockingWindow != null;
    final color = historical || remaining == null
        ? theme.colorScheme.onSurfaceVariant
        : blocked || remaining <= 10
        ? theme.colorScheme.error
        : remaining <= 25
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    final resetAt = window.resetsAt;
    final reset = resetAt == null
        ? 'Reinicio sin información'
        : !resetAt.isAfter(now)
        ? 'Reinicio pendiente de confirmar'
        : resetConfidence == QuotaResetAnchorConfidence.confirmed
        ? 'Reinicia en ${formatTimeRemaining(resetAt, from: now)}'
        : 'Estimado en ${formatTimeRemaining(resetAt, from: now)}';
    final blockingLabel = blockingWindow?.windowDurationMinutes == 10080
        ? 'límite semanal'
        : blockingWindow?.windowDurationMinutes == 300
        ? 'límite de 5 horas'
        : 'límite de ${formatQuotaWindowLabel(blockingWindow?.windowDurationMinutes, blockingWindow?.windowType ?? '')}';
    final blockingStatus = 'Bloqueada por $blockingLabel';
    final status = remaining == null
        ? 'Sin porcentaje'
        : '${remaining.toStringAsFixed(0)}% ${historical
              ? 'registrado'
              : blocked
              ? 'restante'
              : 'disponible'}';
    final observed = remaining == null
        ? 'Porcentaje no informado'
        : '${remaining.toStringAsFixed(0)}% registrado en esta ventana';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Semantics(
        label: '$title. $status. ${blocked ? '$blockingStatus. ' : ''}$reset',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Tooltip(
                    message: title,
                    child: Text(
                      title,
                      key: ValueKey(
                        'quota-title-${window.limitId}-${window.windowType}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: Tooltip(
                    message:
                        '${historical ? 'Último dato válido. ' : ''}$observed. '
                        '${resetAt == null ? 'El proveedor no informó una fecha.' : formatDateTime(resetAt)}',
                    child: Text(
                      reset,
                      key: ValueKey(
                        'quota-reset-${window.limitId}-${window.windowType}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 3,
                  child: Tooltip(
                    message: '$status · $observed',
                    child: Text(
                      status,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            LinearProgressIndicator(
              key: ValueKey(
                'quota-progress-${window.limitId}-${window.windowType}',
              ),
              value: remaining == null ? 0 : remaining / 100,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  blockingStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResetCreditsLine extends StatelessWidget {
  const _ResetCreditsLine({required this.account, required this.now});
  final Account account;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final credits = account.resetCredits;
    final expiry = credits?.nextExpiresAt;
    // A passed expiry cannot tell us how many credits remain; request fresh data.
    final historical =
        account.currentCheck?.state != AccountUsageState.success ||
        (expiry != null && !expiry.isAfter(now));
    final count = credits?.availableCount;
    final label = count == null
        ? 'Resets: sin información'
        : historical
        ? 'Último registro: $count resets'
        : count == 0
        ? 'Sin resets'
        : '$count ${count == 1 ? 'reset disponible' : 'resets disponibles'}';
    final detail = expiry == null
        ? 'Vencimiento no informado'
        : 'Próximo vencimiento: ${formatDateTime(expiry)}';
    return Tooltip(
      message: '$label\n$detail',
      child: Row(
        children: [
          Icon(
            Icons.restart_alt,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              key: ValueKey('reset-credits-${account.profile.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (expiry != null)
            Flexible(
              child: Text(
                expiry.isAfter(now)
                    ? 'Vence ${formatDate(expiry)}'
                    : 'Consultar vencimiento',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuotaSnapshotAge extends StatelessWidget {
  const _QuotaSnapshotAge({
    required this.profileId,
    required this.checkedAt,
    required this.hiddenWindowCount,
  });

  final String profileId;
  final DateTime checkedAt;
  final int hiddenWindowCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = relativeTime(checkedAt);
    final hiddenLabel = hiddenWindowCount == 0 ? '' : ' · +$hiddenWindowCount';
    final hiddenDescription = hiddenWindowCount == 0
        ? ''
        : '\n$hiddenWindowCount ${hiddenWindowCount == 1 ? 'límite adicional' : 'límites adicionales'} ocultos por el modo compacto.';
    return Tooltip(
      message:
          'Cuotas actualizadas: ${formatDateTime(checkedAt)}$hiddenDescription',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.update,
            size: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 3),
          Text(
            '$age$hiddenLabel',
            key: ValueKey('quota-snapshot-age-$profileId'),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingLine extends StatelessWidget {
  const _BillingLine({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = account.metadata;
    final shares = account.costShares;
    final pending = shares.where((item) => item.paymentStatus != 'paid').length;
    return Row(
      children: [
        Icon(
          Icons.event_repeat,
          size: 13,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            metadata?.nextRenewalOn == null
                ? 'Renovación no registrada'
                : 'Renueva ${formatDate(metadata!.nextRenewalOn)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (shares.isNotEmpty)
          Text(
            pending == 0
                ? '${shares.length} pagos al día'
                : '$pending pagos pendientes',
            style: theme.textTheme.labelSmall?.copyWith(
              color: pending == 0
                  ? const Color(0xFF58E2AD)
                  : theme.colorScheme.tertiary,
            ),
          ),
      ],
    );
  }
}

Color _statusColor(BuildContext context, AccountStatus status) {
  final theme = Theme.of(context);
  return switch (status) {
    AccountStatus.available =>
      theme.brightness == Brightness.dark
          ? const Color(0xFF58E2AD)
          : const Color(0xFF006B4C),
    AccountStatus.quotaExhausted ||
    AccountStatus.unavailable => theme.colorScheme.error,
    AccountStatus.authRequired ||
    AccountStatus.quotaUnconfirmed ||
    AccountStatus.offline ||
    AccountStatus.queryError => theme.colorScheme.tertiary,
    AccountStatus.deactivated ||
    AccountStatus.unlinked ||
    AccountStatus.unchecked => theme.colorScheme.onSurfaceVariant,
  };
}

String _statusLabel(AccountStatus status, {bool plural = false}) =>
    switch (status) {
      AccountStatus.available => plural ? 'Disponibles' : 'Disponible',
      AccountStatus.quotaExhausted => 'Cuota agotada',
      AccountStatus.authRequired =>
        plural ? 'Requieren acceso' : 'Requiere acceso',
      AccountStatus.deactivated => plural ? 'Desactivadas' : 'Desactivada',
      AccountStatus.unlinked => 'Sin vincular',
      AccountStatus.unchecked => 'Sin consultar',
      AccountStatus.quotaUnconfirmed => 'Cuota sin confirmar',
      AccountStatus.offline => 'Sin conexión',
      AccountStatus.queryError => 'Error de consulta',
      AccountStatus.unavailable => plural ? 'No disponibles' : 'No disponible',
    };

Color _stateColor(BuildContext context, Account account) =>
    _statusColor(context, account.status);

String _stateLabel(Account account) => switch (account.currentIssue) {
  AccountUsageIssue.credentialExpired => 'Credencial expirada',
  AccountUsageIssue.credentialInvalidated => 'Credencial revocada',
  AccountUsageIssue.network when account.status == AccountStatus.queryError =>
    'Sin conexión',
  _ => _statusLabel(account.status),
};

String _stateDetail(Account account) {
  final provider = profileProvider(account.profile.toolKey);
  final check = account.currentCheck;
  if (account.isDeactivated) {
    return 'Este perfil no está activo en el equipo';
  }
  if (!account.profile.isAvailable) return 'La carpeta del perfil ya no existe';
  if (!account.profile.hasAuthFile) {
    return 'Vincula tu cuenta para empezar a usar este perfil';
  }
  if (!provider.supportsUsage) {
    return '${provider.productName} disponible para abrir';
  }
  if (check == null) return 'Consulta la cuenta para conocer su disponibilidad';
  if (account.hasWeeklyLimitReached) {
    return 'Sin cuota semanal · espera el reinicio';
  }
  if (account.hasExhaustedQuota) return 'Se alcanzó un límite de uso';
  final issueDetail = switch (account.currentIssue) {
    AccountUsageIssue.network =>
      account.currentWindows.isNotEmpty
          ? 'Cuotas actualizadas; falló otra consulta de Codex'
          : account.lastSuccessfulWindows.isNotEmpty
          ? 'Sin conexión; se muestra el último dato válido y se reintentará'
          : 'No se pudo conectar con ChatGPT',
    AccountUsageIssue.credentialExpired =>
      'La credencial expiró; vuelve a iniciar sesión',
    AccountUsageIssue.credentialInvalidated =>
      'ChatGPT revocó la credencial; vuelve a vincularla',
    AccountUsageIssue.partialMetadata =>
      account.currentWindows.isNotEmpty
          ? 'Se obtuvieron cuotas, pero faltan datos complementarios'
          : account.lastSuccessfulWindows.isNotEmpty
          ? 'Sin cuotas nuevas; se muestra el último dato válido'
          : 'Codex no devolvió ventanas de cuota',
    null => null,
  };
  if (issueDetail != null) return issueDetail;
  if (account.currentIsUsable) {
    final count = account.visibleWindows.length;
    return '$count ${count == 1 ? 'ventana oficial' : 'ventanas oficiales'}';
  }
  final lastGood = account.lastSuccessfulCheck;
  if (lastGood != null) {
    return 'Último dato válido ${relativeTime(lastGood.startedAt)}';
  }
  return check.errorMessage ?? 'No se obtuvo una respuesta válida';
}
