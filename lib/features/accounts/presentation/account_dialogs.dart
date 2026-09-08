import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nini_hub/core/currency_catalog.dart';
import 'package:nini_hub/core/formatters.dart';
import 'package:nini_hub/features/accounts/application/account_management.dart';
import 'package:nini_hub/features/accounts/domain/account.dart';
import 'package:nini_hub/features/accounts/domain/account_device_auth.dart';
import 'package:nini_hub/features/accounts/presentation/controllers/accounts_controller.dart';
import 'package:nini_hub/features/accounts/presentation/state/accounts_state.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

String accountProfileConfigurationLabel(Profile profile) {
  if (profile.source == ProfileSource.defaultProfile) return 'Perfil principal';
  return switch (profile.kind) {
    ProfileKind.shared => 'Configuración compartida',
    ProfileKind.full || ProfileKind.isolated => 'Configuración propia',
    ProfileKind.deactivated => 'Perfil desactivado',
    ProfileKind.base || ProfileKind.cli => 'Perfil de herramienta',
  };
}

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
        title: Text('Iniciar ciclo de ${account.profile.displayName}'),
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
            label: const Text('Iniciar'),
          ),
        ],
      ),
    ) ??
    false;

Future<AccountAuthMethod?> showAccountAuthMethodDialog(
  BuildContext context, {
  String title = 'Vincular con ChatGPT',
}) {
  return showDialog<AccountAuthMethod>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Elige cómo iniciar sesión en la página oficial de OpenAI.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(context, AccountAuthMethod.browser),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Continuar en el navegador'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, AccountAuthMethod.deviceCode),
              icon: const Icon(Icons.phonelink_lock_outlined),
              label: const Text('Usar código de dispositivo'),
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
    ),
  );
}

Future<bool> showPendingAccountAuthDialog(
  BuildContext context,
  Profile profile,
  AccountDeviceAuthSession session,
  AccountAuthMethod method,
) async {
  final completion = Completer<Object?>();
  final route = showDialog<Object>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeviceAuthDialog(
      account: Account(
        profile: profile,
        metadata: null,
        costShares: const [],
        currentCheck: null,
        currentWindows: const [],
        lastSuccessfulCheck: null,
        lastSuccessfulWindows: const [],
        resetCredits: null,
      ),
      session: session,
      browser: method == AccountAuthMethod.browser,
      isNewProfile: true,
      externallyOwnedSession: true,
      onDisposed: () {
        if (!completion.isCompleted) completion.complete(false);
      },
      complete: (_, _) async {},
    ),
  );
  unawaited(
    route.then(
      (value) {
        if (!completion.isCompleted) completion.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!completion.isCompleted) completion.complete(error);
      },
    ),
  );
  final result = await completion.future;
  if (result == null || result == false) return false;
  if (result == true) return true;
  throw result;
}

Future<void> showDeviceAuthDialog(
  BuildContext context,
  Account account, {
  required Future<AccountDeviceAuthSession> Function(Account account) start,
  Future<AccountDeviceAuthSession> Function(Account account)? startBrowser,
  required Future<void> Function(Account account, bool success) complete,
  AccountAuthMethod? method,
  bool isNewProfile = false,
}) async {
  var browser = method == AccountAuthMethod.browser;
  if (method == null && startBrowser != null) {
    method = await showAccountAuthMethodDialog(context);
    if (method == null || !context.mounted) return;
    browser = method == AccountAuthMethod.browser;
  }
  AccountDeviceAuthSession session;
  try {
    session = await (browser ? startBrowser! : start)(account);
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
      browser: browser,
      isNewProfile: isNewProfile,
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

class _EditAccountDialogState extends State<_EditAccountDialog>
    with SingleTickerProviderStateMixin {
  late final TabController sections = TabController(length: 3, vsync: this);
  final formKey = GlobalKey<FormState>();
  final _fieldKeys = <TextEditingController, GlobalKey>{};
  final _fieldFocus = <TextEditingController, FocusNode>{};
  final _fieldErrors = <TextEditingController, String>{};
  String get _accountLabel =>
      widget.account.profile.source == ProfileSource.defaultProfile &&
          const [
            'main',
            'principal',
            'codex principal',
            'codex main',
          ].contains(widget.account.profile.displayName.trim().toLowerCase())
      ? 'Perfil principal'
      : widget.account.profile.displayName;
  late final displayName = TextEditingController(text: _accountLabel);
  late final accountName = TextEditingController(
    text: widget.account.metadata?.accountDisplayName ?? '',
  );
  late final plan = TextEditingController(
    text: widget.account.metadata?.planName ?? '',
  );
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

  @override
  void initState() {
    super.initState();
    sections.addListener(_sectionChanged);
  }

  void _sectionChanged() {
    if (mounted) setState(() {});
  }

  List<TextEditingController> get _controllers => [
    displayName,
    accountName,
    plan,
    notes,
    amount,
    purchasedFrom,
    paymentMethod,
  ];

  @override
  void dispose() {
    sections.dispose();
    for (final focus in _fieldFocus.values) {
      focus.dispose();
    }
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
    if (selected == null || !mounted) return;
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
    setState(() {
      currencyCode = selected.code;
      _fieldErrors.clear();
      error = null;
    });
  }

  Future<void> submit() async {
    if (saving) return;
    if (displayName.text.trim().isEmpty) {
      await _revealError(
        0,
        displayName,
        'Escribe un nombre para identificar esta cuenta.',
      );
      return;
    }
    final moneyError = _validateMoney(amount.text, currencyCode);
    if (moneyError != null) {
      await _revealError(
        1,
        amount,
        moneyError,
        summary: 'Precio por renovación: $moneyError',
      );
      return;
    }
    for (final share in shares) {
      if (share.name.text.trim().isEmpty &&
          (share.expected.text.trim().isNotEmpty ||
              share.paid.text.trim().isNotEmpty)) {
        await _revealError(
          2,
          share.name,
          'Escribe el nombre de la persona para registrar su pago.',
        );
        return;
      }
      if (share.name.text.trim().isEmpty) continue;
      for (final field in [share.expected, share.paid]) {
        final invalidAmount = _validateMoney(field.text, currencyCode);
        if (invalidAmount != null) {
          await _revealError(
            2,
            field,
            invalidAmount,
            summary: '${share.name.text}: $invalidAmount',
          );
          return;
        }
      }
    }
    if (!formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
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
          metadata: AccountEditableMetadata(
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
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Datos de la cuenta guardados en Nini Hub.'),
            ),
          );
        }
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

  Future<void> _revealError(
    int tab,
    TextEditingController field,
    String message, {
    String? summary,
  }) async {
    setState(() {
      error = summary ?? message;
      _fieldErrors[field] = message;
      sections.index = tab;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _fieldFocus[field]?.requestFocus();
    final fieldContext = _fieldKeys[field]?.currentContext;
    if (fieldContext != null && fieldContext.mounted) {
      await Scrollable.ensureVisible(
        fieldContext,
        alignment: .3,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    String? helper,
    String? hint,
    bool money = false,
    int? minLines,
    int? maxLines = 1,
  }) => TextFormField(
    key: _fieldKeys.putIfAbsent(controller, GlobalKey.new),
    focusNode: _fieldFocus.putIfAbsent(controller, FocusNode.new),
    controller: controller,
    enabled: !saving,
    minLines: minLines,
    maxLines: maxLines,
    textInputAction: maxLines == 1
        ? TextInputAction.next
        : TextInputAction.newline,
    keyboardType: money
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    inputFormatters: money
        ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
        : null,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      hintText: hint,
      suffixText: money ? currencyCode : null,
      errorText: _fieldErrors[controller],
    ),
    onChanged: (_) {
      if (_fieldErrors.containsKey(controller) || error != null) {
        setState(() {
          _fieldErrors.remove(controller);
          error = null;
        });
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = profileProvider(widget.account.profile.toolKey);
    return PopScope(
      canPop: !saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 760,
          height: (MediaQuery.sizeOf(context).height - 48).clamp(0.0, 560.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Datos de la cuenta',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${provider.displayName} · $_accountLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              AbsorbPointer(
                absorbing: saving,
                child: TabBar(
                  controller: sections,
                  onTap: (_) => FocusScope.of(context).unfocus(),
                  tabs: const [
                    Tab(
                      height: 40,
                      child: _DialogTab(
                        icon: Icons.person_outline,
                        label: 'Cuenta',
                      ),
                    ),
                    Tab(
                      height: 40,
                      child: _DialogTab(
                        icon: Icons.event_repeat,
                        label: 'Suscripción',
                      ),
                    ),
                    Tab(
                      height: 40,
                      child: _DialogTab(
                        icon: Icons.group_outlined,
                        label: 'Pagos compartidos',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AbsorbPointer(
                  absorbing: saving,
                  child: Form(
                    key: formKey,
                    // Keep all fields mounted so a validation error can focus
                    // and reveal any participant, including in another tab.
                    child: IndexedStack(
                      index: sections.index,
                      children: [
                        _accountTab(theme),
                        _subscriptionTab(theme),
                        _sharesTab(theme),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Solo se guarda en Nini Hub.\nNo cambia tu cuenta ni tus cobros.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: saving ? null : submit,
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check, size: 18),
                          label: Text(
                            saving ? 'Guardando…' : 'Guardar cambios',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountTab(ThemeData theme) => SingleChildScrollView(
    primary: false,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      widget.account.displayEmail.isEmpty
                          ? 'Correo aún no reconocido'
                          : widget.account.displayEmail,
                      key: const ValueKey('account-observed-email'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${accountProfileConfigurationLabel(widget.account.profile)} · Plan detectado: ${widget.account.observedPlan.isEmpty ? 'sin información' : widget.account.observedPlan}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Información de consulta; se actualiza al consultar la cuenta.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _FormColumns(
          first: _field(
            displayName,
            label: 'Nombre en Nini Hub *',
            hint: 'Por ejemplo, Cuenta de trabajo',
          ),
          second: _field(accountName, label: 'Propietario (opcional)'),
        ),
        const SizedBox(height: 16),
        _field(
          plan,
          label: 'Nombre del plan (opcional)',
          hint: widget.account.observedPlan,
          helper: 'Déjalo vacío para mostrar el plan detectado.',
        ),
        const SizedBox(height: 16),
        _field(notes, label: 'Notas (opcional)', minLines: 2, maxLines: 4),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          value: favorite,
          onChanged: saving
              ? null
              : (value) => setState(() => favorite = value ?? false),
          title: Text('Fijar como favorita', style: theme.textTheme.bodyMedium),
        ),
      ],
    ),
  );

  Widget _subscriptionTab(ThemeData theme) => SingleChildScrollView(
    primary: false,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormColumns(
          first: _field(amount, label: 'Precio por renovación', money: true),
          second: _CurrencyField(
            fieldKey: const Key('currency-field'),
            value: currencyByCode(currencyCode),
            onTap: _pickCurrency,
          ),
        ),
        const SizedBox(height: 16),
        _FormColumns(
          first: DropdownButtonFormField<String>(
            initialValue: interval,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ciclo de facturación',
            ),
            items: const [
              DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
              DropdownMenuItem(value: 'yearly', child: Text('Anual')),
              DropdownMenuItem(value: 'one_time', child: Text('Pago único')),
              DropdownMenuItem(value: 'unknown', child: Text('Sin definir')),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() => interval = value ?? 'monthly'),
          ),
          second: DropdownButtonFormField<String>(
            initialValue: subscriptionStatus,
            isExpanded: true,
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
            onChanged: saving
                ? null
                : (value) => setState(() {
                    subscriptionStatus = value ?? 'active';
                    if (subscriptionStatus == 'cancelled' ||
                        subscriptionStatus == 'expired') {
                      autoRenew = false;
                    }
                  }),
          ),
        ),
        const SizedBox(height: 16),
        _FormColumns(
          first: _DateButton(
            fieldKey: const Key('purchase-date-field'),
            label: 'Fecha de compra',
            value: purchasedOn,
            onTap: () => _pickDate(renewal: false),
            onClear: () => setState(() => purchasedOn = null),
          ),
          second: _DateButton(
            fieldKey: const Key('next-renewal-date-field'),
            label: 'Fecha de próxima renovación',
            value: renewalOn,
            onTap: () => _pickDate(renewal: true),
            onClear: () => setState(() => renewalOn = null),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: autoRenew,
          onChanged:
              saving ||
                  subscriptionStatus == 'cancelled' ||
                  subscriptionStatus == 'expired'
              ? null
              : (value) => setState(() => autoRenew = value),
          title: Text(
            'Se renueva automáticamente',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            subscriptionStatus == 'cancelled' || subscriptionStatus == 'expired'
                ? 'No aplica a una suscripción cancelada o vencida.'
                : 'Registra aquí cómo se renueva tu suscripción.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 28),
        Text('Datos de compra (opcionales)', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        _FormColumns(
          first: _field(purchasedFrom, label: 'Tienda o canal de compra'),
          second: _field(paymentMethod, label: 'Método de pago'),
        ),
      ],
    ),
  );

  void _addShare() {
    final share = _ShareEditor.empty();
    setState(() => shares.add(share));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fieldFocus[share.name]?.requestFocus();
      final fieldContext = _fieldKeys[share.name]?.currentContext;
      if (fieldContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            fieldContext,
            alignment: .1,
            duration: const Duration(milliseconds: 180),
          ),
        );
      }
    });
  }

  Widget _sharesTab(ThemeData theme) => SingleChildScrollView(
    primary: false,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reparte el costo y registra los pagos en $currencyCode.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (shares.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(
                  Icons.group_outlined,
                  size: 28,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                Text(
                  '¿Compartes el costo de esta cuenta?',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Agrega a cada persona y registra cuánto aporta y cuánto pagó.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving ? null : _addShare,
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('Agregar persona'),
                ),
              ],
            ),
          )
        else ...[
          for (var index = 0; index < shares.length; index++) ...[
            _shareFields(theme, shares[index], index),
            const SizedBox(height: 16),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: saving ? null : _addShare,
              icon: const Icon(Icons.person_add_alt, size: 16),
              label: const Text('Agregar persona'),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _shareFields(ThemeData theme, _ShareEditor share, int index) =>
      Container(
        key: ValueKey(share.id),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Participante ${index + 1}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar persona',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: saving
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            shares.remove(share);
                            for (final field in [
                              share.name,
                              share.expected,
                              share.paid,
                              share.notes,
                            ]) {
                              _fieldErrors.remove(field);
                            }
                            error = null;
                          });
                          share.dispose();
                        },
                ),
              ],
            ),
            _field(share.name, label: 'Persona'),
            const SizedBox(height: 16),
            _FormColumns(
              first: _field(
                share.expected,
                label: 'Aporte acordado',
                money: true,
              ),
              second: _field(share.paid, label: 'Importe pagado', money: true),
            ),
            const SizedBox(height: 16),
            _FormColumns(
              first: DropdownButtonFormField<String>(
                initialValue: share.status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Estado del pago'),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                  DropdownMenuItem(value: 'partial', child: Text('Parcial')),
                  DropdownMenuItem(value: 'paid', child: Text('Pagado')),
                ],
                onChanged: saving
                    ? null
                    : (value) =>
                          setState(() => share.status = value ?? 'pending'),
              ),
              second: _field(share.notes, label: 'Nota del pago (opcional)'),
            ),
          ],
        ),
      );
}

class _FormColumns extends StatelessWidget {
  const _FormColumns({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    final fontSize = Theme.of(context).textTheme.bodyLarge!.fontSize!;
    final textScale = (MediaQuery.textScalerOf(context).scale(fontSize) / 13)
        .clamp(1.0, 2.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 16), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        );
      },
    );
  }
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
    this.browser = false,
    this.isNewProfile = false,
    this.externallyOwnedSession = false,
    this.onDisposed,
    required this.complete,
  });

  final Account account;
  final AccountDeviceAuthSession session;
  final bool browser;
  final bool isNewProfile;
  final bool externallyOwnedSession;
  final VoidCallback? onDisposed;
  final Future<void> Function(Account account, bool success) complete;

  @override
  State<_DeviceAuthDialog> createState() => _DeviceAuthDialogState();
}

class _DeviceAuthDialogState extends State<_DeviceAuthDialog> {
  bool waiting = true;
  bool confirmed = false;
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
    if (!mounted || closing || confirmed) return;
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
      if (!mounted || closing) return;
      if (success) setState(() => confirmed = true);
      await widget.complete(widget.account, success);
      if (!mounted || closing) return;
      if (success) {
        Navigator.pop(context, widget.externallyOwnedSession ? true : null);
      } else if (widget.externallyOwnedSession) {
        Navigator.pop(context, StateError('Codex no confirmó el acceso.'));
      } else {
        setState(() {
          waiting = false;
          error = 'Codex no confirmó el acceso.';
        });
      }
    } catch (exception) {
      if (!mounted || closing) return;
      if (widget.externallyOwnedSession) {
        Navigator.pop(context, exception);
        return;
      }
      setState(() {
        waiting = false;
        error = _cleanError(exception);
      });
    }
  }

  @override
  void dispose() {
    widget.onDisposed?.call();
    if (!widget.externallyOwnedSession) unawaited(widget.session.close());
    super.dispose();
  }

  Future<void> _cancel() async {
    if (closing || confirmed) return;
    setState(() => closing = true);
    if (widget.externallyOwnedSession) {
      Navigator.pop(context, false);
      return;
    }
    await widget.session.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = !widget.isNewProfile && widget.account.profile.hasAuthFile
        ? 'Revincular'
        : 'Vincular';
    return AlertDialog(
      scrollable: true,
      title: Text('$action ${widget.account.profile.displayName}'),
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
            Text(
              widget.browser
                  ? (confirmed
                        ? 'Acceso confirmado'
                        : 'Iniciar sesión en el navegador')
                  : 'Código de dispositivo',
              style: theme.textTheme.titleMedium,
            ),
            if (!widget.browser) ...[
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
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
            ],
            if (widget.browser)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Completa el acceso en la página oficial de OpenAI. Esta ventana se actualizará automáticamente al terminar.',
                  textAlign: TextAlign.center,
                ),
              ),
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
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!widget.browser)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _copy(widget.session.userCode, 'Código copiado.'),
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text('Copiar código'),
                  ),
                FilledButton.icon(
                  onPressed: confirmed ? null : _openBrowser,
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('Abrir navegador'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (waiting)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      confirmed
                          ? 'Acceso confirmado. Guardando la vinculación…'
                          : 'Esperando confirmación de Codex…',
                    ),
                  ),
                ],
              ),
            if (error != null)
              Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: closing
              ? null
              : confirmed
              ? (error == null ? null : () => Navigator.pop(context))
              : _cancel,
          child: Text(confirmed && error != null ? 'Cerrar' : 'Cancelar'),
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
