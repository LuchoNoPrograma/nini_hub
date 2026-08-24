import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_cli_ai/core/currency_catalog.dart';
import 'package:multi_cli_ai/core/formatters.dart';
import 'package:multi_cli_ai/features/accounts/application/account_management.dart';
import 'package:multi_cli_ai/features/accounts/domain/account.dart';
import 'package:multi_cli_ai/features/accounts/domain/account_device_auth.dart';
import 'package:multi_cli_ai/features/accounts/presentation/controllers/accounts_controller.dart';
import 'package:multi_cli_ai/features/accounts/presentation/state/accounts_state.dart';
import 'package:multi_cli_ai/features/profiles/domain/profile_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

Future<void> showEditAccountDialog(
  BuildContext context,
  AccountsController controller,
  AccountsState Function() readState,
  Account account,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _EditAccountDialog(
    controller: controller,
    readState: readState,
    account: account,
  ),
);

Future<bool> showCodexHeartbeatConfirmation(
  BuildContext context,
  Account account,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.monitor_heart_outlined),
        title: Text('Enviar heartbeat a ${account.profile.displayName}'),
        content: const SizedBox(
          width: 430,
          child: Text(
            'Codex procesará una consulta mínima real. Esto consume una pequeña '
            'parte de la cuota y luego se verificará el ancla de reinicio.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Enviar'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showDeviceAuthDialog(
  BuildContext context,
  Account account, {
  required Future<AccountDeviceAuthSession> Function(Account account) start,
  required Future<void> Function(Account account, bool success) complete,
}) async {
  AccountDeviceAuthSession session;
  try {
    session = await start(account);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    return;
  }
  if (!context.mounted) {
    await session.close();
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeviceAuthDialog(
      account: account,
      session: session,
      complete: complete,
    ),
  );
}

class _EditAccountDialog extends StatefulWidget {
  const _EditAccountDialog({
    required this.controller,
    required this.readState,
    required this.account,
  });

  final AccountsController controller;
  final AccountsState Function() readState;
  final Account account;

  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  final formKey = GlobalKey<FormState>();
  late final displayName = TextEditingController(
    text: widget.account.profile.displayName,
  );
  late final email = TextEditingController(text: widget.account.displayEmail);
  late final accountName = TextEditingController(
    text: widget.account.metadata?.accountDisplayName ?? '',
  );
  late final plan = TextEditingController(text: widget.account.displayPlan);
  late final notes = TextEditingController(
    text: widget.account.metadata?.notes ?? '',
  );
  late String currencyCode = currencyByCode(
    widget.account.metadata?.currencyCode,
  ).code;
  late final amount = TextEditingController(
    text:
        widget.account.metadata?.expectedAmountMinor == null ||
            widget.account.metadata!.expectedAmountMinor == 0
        ? ''
        : _majorUnits(
            widget.account.metadata!.expectedAmountMinor,
            currencyCode,
          ),
  );
  late final purchasedFrom = TextEditingController(
    text: widget.account.metadata?.purchasedFrom ?? '',
  );
  late final paymentMethod = TextEditingController(
    text: widget.account.metadata?.paymentMethodLabel ?? '',
  );
  late bool favorite = widget.account.profile.isFavorite;
  late bool autoRenew = widget.account.metadata?.autoRenew ?? true;
  late String interval = widget.account.metadata?.billingInterval ?? 'monthly';
  late String subscriptionStatus =
      widget.account.metadata?.subscriptionStatus ?? 'active';
  late DateTime? purchasedOn = widget.account.metadata?.purchasedOn;
  late DateTime? renewalOn = widget.account.metadata?.nextRenewalOn;
  late final List<_ShareEditor> shares = widget.account.costShares
      .map(_ShareEditor.fromStored)
      .toList();
  bool saving = false;
  String? error;

  List<TextEditingController> get _controllers => [
    displayName,
    email,
    accountName,
    plan,
    notes,
    amount,
    purchasedFrom,
    paymentMethod,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final share in shares) {
      share.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool renewal}) async {
    final value = renewal ? renewalOn : purchasedOn;
    final selected = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: renewal ? 'PRÓXIMA RENOVACIÓN' : 'FECHA DE COMPRA',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (selected == null) return;
    setState(() {
      if (renewal) {
        renewalOn = selected;
      } else {
        purchasedOn = selected;
      }
    });
  }

  Future<void> _pickCurrency() async {
    final selected = await showDialog<AppCurrency>(
      context: context,
      builder: (_) => _CurrencyPickerDialog(selectedCode: currencyCode),
    );
    if (selected == null || !mounted) return;
    setState(() => currencyCode = selected.code);
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final updated = await widget.controller.update(
        UpdateAccountCommand(
          profileId: widget.account.profile.id,
          displayName: displayName.text,
          isFavorite: favorite,
          metadata: AccountMetadata(
            accountEmail: email.text,
            accountDisplayName: accountName.text,
            planName: plan.text,
            notes: notes.text,
            purchasedOn: purchasedOn,
            nextRenewalOn: renewalOn,
            billingInterval: interval,
            expectedAmountMinor: _minorUnits(amount.text, currencyCode),
            currencyCode: currencyCode,
            autoRenew: autoRenew,
            subscriptionStatus: subscriptionStatus,
            purchasedFrom: purchasedFrom.text,
            paymentMethodLabel: paymentMethod.text,
          ),
          costShares: shares.map((item) => item.draft(currencyCode)),
        ),
      );
      if (updated != null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (mounted) {
        setState(() {
          error =
              widget.readState().errorMessage ??
              'No se pudieron guardar los datos de la cuenta.';
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = _cleanError(exception));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availableHeight = MediaQuery.sizeOf(context).height - 160;
    final dialogHeight = availableHeight.clamp(340.0, 440.0);
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 10, 0),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Editar perfil "${widget.account.profile.displayName}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: saving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        content: SizedBox(
          width: 700,
          height: dialogHeight,
          child: Form(
            key: formKey,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(
                      height: 38,
                      child: _DialogTab(
                        icon: Icons.person_outline,
                        label: 'Cuenta',
                      ),
                    ),
                    Tab(
                      height: 38,
                      child: _DialogTab(
                        icon: Icons.event_repeat,
                        label: 'Renovación',
                      ),
                    ),
                    Tab(
                      height: 38,
                      child: _DialogTab(
                        icon: Icons.group_outlined,
                        label: 'Pagos',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _accountTab(theme),
                      _subscriptionTab(theme),
                      _sharesTab(theme),
                    ],
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: saving ? null : submit,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }

  Widget _accountTab(ThemeData theme) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 9, 0, 4),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: displayName,
              decoration: const InputDecoration(labelText: 'Nombre visible'),
              validator: (value) =>
                  value?.trim().isEmpty == true ? 'Escribe un nombre.' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: widget.account.profile.commandName ?? 'codex',
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Comando',
                prefixIcon: Icon(Icons.terminal, size: 18),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: email,
              decoration: const InputDecoration(
                labelText: 'Correo de la cuenta',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: accountName,
              decoration: const InputDecoration(
                labelText: 'Usuario o propietario',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: plan,
        decoration: InputDecoration(
          labelText: 'Plan declarado',
          helperText:
              'Se muestra aparte del plan observado por ${profileProvider(widget.account.profile.toolKey).productName}.',
        ),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: notes,
        minLines: 4,
        maxLines: 6,
        decoration: const InputDecoration(labelText: 'Notas'),
      ),
      const SizedBox(height: 8),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: favorite,
        onChanged: (value) => setState(() => favorite = value),
        title: const Text('Fijar como favorita'),
        secondary: Icon(Icons.star_outline, color: theme.colorScheme.tertiary),
      ),
    ],
  );

  Widget _subscriptionTab(ThemeData theme) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 9, 0, 4),
    children: [
      Row(
        children: [
          Expanded(
            child: _DateButton(
              fieldKey: const Key('purchase-date-field'),
              label: 'Fecha de compra',
              value: purchasedOn,
              onTap: () => _pickDate(renewal: false),
              onClear: () => setState(() => purchasedOn = null),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DateButton(
              fieldKey: const Key('next-renewal-date-field'),
              label: 'Fecha de próxima renovación',
              value: renewalOn,
              onTap: () => _pickDate(renewal: true),
              onClear: () => setState(() => renewalOn = null),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: interval,
              decoration: const InputDecoration(
                labelText: 'Ciclo de facturación',
              ),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                DropdownMenuItem(value: 'yearly', child: Text('Anual')),
                DropdownMenuItem(value: 'one_time', child: Text('Pago único')),
                DropdownMenuItem(value: 'unknown', child: Text('Sin definir')),
              ],
              onChanged: (value) =>
                  setState(() => interval = value ?? 'monthly'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: subscriptionStatus,
              decoration: InputDecoration(
                labelText: 'Estado de la suscripción',
                helperText: _subscriptionStatusDescription(subscriptionStatus),
              ),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Activa')),
                DropdownMenuItem(
                  value: 'trial',
                  child: Text('En periodo de prueba'),
                ),
                DropdownMenuItem(value: 'paused', child: Text('Pausada')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelada')),
                DropdownMenuItem(value: 'expired', child: Text('Vencida')),
              ],
              onChanged: (value) {
                setState(() {
                  subscriptionStatus = value ?? 'active';
                  if (subscriptionStatus == 'cancelled' ||
                      subscriptionStatus == 'expired') {
                    autoRenew = false;
                  }
                });
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: amount,
              decoration: InputDecoration(
                labelText: 'Precio por renovación',
                helperText: 'Total que esperas pagar en cada cobro.',
                suffixText: currencyCode,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              validator: (value) => _validateMoney(value, currencyCode),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _CurrencyField(
              fieldKey: const Key('currency-field'),
              value: currencyByCode(currencyCode),
              onTap: _pickCurrency,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: purchasedFrom,
              decoration: const InputDecoration(
                labelText: 'Tienda o canal de compra',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: paymentMethod,
              decoration: const InputDecoration(labelText: 'Método de pago'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: autoRenew,
        onChanged:
            subscriptionStatus == 'cancelled' || subscriptionStatus == 'expired'
            ? null
            : (value) => setState(() => autoRenew = value),
        title: const Text('Se renueva automáticamente'),
        subtitle: Text(
          subscriptionStatus == 'cancelled' || subscriptionStatus == 'expired'
              ? 'No aplica a una suscripción cancelada o vencida.'
              : 'Dato administrativo; no cambia la suscripción real.',
        ),
        secondary: Icon(Icons.autorenew, color: theme.colorScheme.primary),
      ),
    ],
  );

  Widget _sharesTab(ThemeData theme) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Registra quién participa del costo y qué monto pagó.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => shares.add(_ShareEditor.empty())),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Agregar persona'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Expanded(
        child: shares.isEmpty
            ? Center(
                child: Text(
                  'No hay participantes registrados.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: shares.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final share = shares[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: share.name,
                                decoration: const InputDecoration(
                                  labelText: 'Persona',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: share.expected,
                                decoration: const InputDecoration(
                                  labelText: 'Debe',
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: share.paid,
                                decoration: const InputDecoration(
                                  labelText: 'Pagó',
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 135,
                              child: DropdownButtonFormField<String>(
                                initialValue: share.status,
                                decoration: const InputDecoration(
                                  labelText: 'Estado',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'pending',
                                    child: Text('Pendiente'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'partial',
                                    child: Text('Parcial'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'paid',
                                    child: Text('Pagado'),
                                  ),
                                ],
                                onChanged: (value) =>
                                    share.status = value ?? 'pending',
                              ),
                            ),
                            IconButton(
                              tooltip: 'Quitar persona',
                              onPressed: () {
                                setState(() {
                                  shares.removeAt(index);
                                  share.dispose();
                                });
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: share.notes,
                          decoration: const InputDecoration(
                            labelText: 'Nota del pago',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class _DialogTab extends StatelessWidget {
  const _DialogTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 15),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final Key fieldKey;
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: value == null
          ? '$label, sin fecha'
          : '$label, ${formatDate(value)}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          key: fieldKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              suffixIcon: value == null
                  ? const Icon(Icons.arrow_drop_down)
                  : IconButton(
                      tooltip: 'Quitar fecha',
                      onPressed: onClear,
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
            child: Text(
              formatDate(value, empty: 'Seleccionar fecha'),
              style: value == null
                  ? theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({
    required this.fieldKey,
    required this.value,
    required this.onTap,
  });

  final Key fieldKey;
  final AppCurrency value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Moneda, ${value.code}, ${value.name}',
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        key: fieldKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Moneda',
            suffixIcon: Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            '${value.code} · ${value.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ),
  );
}

class _CurrencyPickerDialog extends StatefulWidget {
  const _CurrencyPickerDialog({required this.selectedCode});

  final String selectedCode;

  @override
  State<_CurrencyPickerDialog> createState() => _CurrencyPickerDialogState();
}

class _CurrencyPickerDialogState extends State<_CurrencyPickerDialog> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<AppCurrency> get filteredCurrencies {
    final normalizedQuery = _normalizeSearch(query.trim());
    if (normalizedQuery.isEmpty) return currencies;
    return currencies
        .where(
          (currency) =>
              _normalizeSearch(currency.searchText).contains(normalizedQuery),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = filteredCurrencies;
    final availableHeight = MediaQuery.sizeOf(context).height - 210;
    return AlertDialog(
      title: const Text('Seleccionar moneda'),
      content: SizedBox(
        width: 500,
        height: availableHeight.clamp(300.0, 510.0),
        child: Column(
          children: [
            TextField(
              key: const Key('currency-search-field'),
              controller: search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o código',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          search.clear();
                          setState(() => query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: options.isEmpty
                  ? Center(
                      child: Text(
                        'No se encontró esa moneda.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final currency = options[index];
                        final selected = currency.code == widget.selectedCode;
                        return ListTile(
                          selected: selected,
                          leading: SizedBox(
                            width: 48,
                            child: Text(
                              currency.code,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          title: Text(currency.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currency.displaySymbol,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.check,
                                  size: 19,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          onTap: () => Navigator.pop(context, currency),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _DeviceAuthDialog extends StatefulWidget {
  const _DeviceAuthDialog({
    required this.account,
    required this.session,
    required this.complete,
  });

  final Account account;
  final AccountDeviceAuthSession session;
  final Future<void> Function(Account account, bool success) complete;

  @override
  State<_DeviceAuthDialog> createState() => _DeviceAuthDialogState();
}

class _DeviceAuthDialogState extends State<_DeviceAuthDialog> {
  bool waiting = true;
  bool closing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openBrowser());
    });
    unawaited(_wait());
  }

  Future<void> _openBrowser() async {
    try {
      await launchUrl(
        Uri.parse(widget.session.verificationUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // The dialog keeps an explicit browser button as a reliable fallback.
    }
  }

  Future<void> _copy(String value, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(confirmation)));
  }

  Future<void> _wait() async {
    try {
      final success = await widget.session.waitForCompletion();
      await widget.complete(widget.account, success);
      if (!mounted) return;
      if (success) {
        Navigator.pop(context);
      } else {
        setState(() {
          waiting = false;
          error = 'Codex no confirmó el acceso.';
        });
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        waiting = false;
        error = _cleanError(exception);
      });
    }
  }

  Future<void> _cancel() async {
    if (closing) return;
    setState(() => closing = true);
    await widget.session.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text('Vincular ${widget.account.profile.displayName}'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phonelink_lock_outlined,
              size: 38,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Código de dispositivo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 9),
            SelectableText(
              widget.session.userCode,
              style: theme.textTheme.headlineLarge?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.security_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Primero, en ChatGPT abre Configuración > Seguridad y habilita el acceso mediante código de dispositivo.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '1. Copia el código.  2. Inicia sesión con la cuenta que quieres vincular.  '
              '3. Ingresa el código, confirma el acceso y regresa aquí.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '¿No se abrió el navegador? Copia el enlace:',
                style: theme.textTheme.labelMedium,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 7, 3, 7),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.session.verificationUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar enlace',
                    onPressed: () => _copy(
                      widget.session.verificationUrl,
                      'Enlace copiado.',
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _copy(widget.session.userCode, 'Código copiado.'),
                  icon: const Icon(Icons.copy, size: 17),
                  label: const Text('Copiar código'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _openBrowser,
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('Abrir navegador'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (waiting)
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Esperando confirmación de Codex…'),
                ],
              ),
            if (error != null)
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: closing ? null : _cancel,
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _ShareEditor {
  _ShareEditor({
    required this.id,
    required this.name,
    required this.expected,
    required this.paid,
    required this.notes,
    required this.status,
  });

  factory _ShareEditor.empty() => _ShareEditor(
    id: const Uuid().v4(),
    name: TextEditingController(),
    expected: TextEditingController(),
    paid: TextEditingController(),
    notes: TextEditingController(),
    status: 'pending',
  );

  factory _ShareEditor.fromStored(AccountCostShare item) => _ShareEditor(
    id: item.id,
    name: TextEditingController(text: item.personName),
    expected: TextEditingController(
      text: _majorUnits(item.expectedAmountMinor, item.currencyCode),
    ),
    paid: TextEditingController(
      text: _majorUnits(item.paidAmountMinor, item.currencyCode),
    ),
    notes: TextEditingController(text: item.notes),
    status: item.paymentStatus,
  );

  final String id;
  final TextEditingController name;
  final TextEditingController expected;
  final TextEditingController paid;
  final TextEditingController notes;
  String status;

  AccountCostShare draft(String currency) => AccountCostShare(
    id: id,
    personName: name.text,
    expectedAmountMinor: _minorUnits(expected.text, currency),
    paidAmountMinor: _minorUnits(paid.text, currency),
    currencyCode: currency,
    paymentStatus: status,
    paidOn: status == 'paid' ? DateTime.now() : null,
    notes: notes.text,
  );

  void dispose() {
    name.dispose();
    expected.dispose();
    paid.dispose();
    notes.dispose();
  }
}

int _minorUnits(String value, String currencyCode) {
  final parsed = double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  return (parsed * currencyMinorFactor(currencyCode)).round();
}

String? _validateMoney(String? value, String currencyCode) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return null;
  final currency = currencyByCode(currencyCode);
  final decimalPart = currency.decimalDigits == 0
      ? ''
      : r'(?:[.,][0-9]{1,' + currency.decimalDigits.toString() + r'})?';
  if (!RegExp('^[0-9]+$decimalPart\$').hasMatch(input)) {
    return currency.decimalDigits == 0
        ? '${currency.code} no usa decimales.'
        : 'Escribe un precio válido.';
  }
  return null;
}

String _majorUnits(int value, String currencyCode) {
  final currency = currencyByCode(currencyCode);
  final amount = value / currencyMinorFactor(currency.code);
  return amount.toStringAsFixed(currency.decimalDigits);
}

String _subscriptionStatusDescription(String status) => switch (status) {
  'trial' => 'El plan está dentro de su periodo de prueba.',
  'paused' => 'Los cobros o el servicio están temporalmente pausados.',
  'cancelled' => 'No esperas que vuelva a renovarse.',
  'expired' => 'El periodo pagado ya terminó.',
  _ => 'El plan está vigente y puede volver a renovarse.',
};

String _normalizeSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[áàäâ]'), 'a')
    .replaceAll(RegExp('[éèëê]'), 'e')
    .replaceAll(RegExp('[íìïî]'), 'i')
    .replaceAll(RegExp('[óòöô]'), 'o')
    .replaceAll(RegExp('[úùüû]'), 'u')
    .replaceAll('ñ', 'n');

String _cleanError(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('FormatException: ', '');
