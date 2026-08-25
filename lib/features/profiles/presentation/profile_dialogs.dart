import 'package:flutter/material.dart';
import 'package:nini_hub/features/profiles/application/profile_management.dart';
import 'package:nini_hub/features/profiles/domain/profile.dart';
import 'package:nini_hub/features/profiles/domain/profile_failure.dart';
import 'package:nini_hub/features/profiles/domain/profile_provider.dart';
import 'package:nini_hub/features/profiles/presentation/controllers/profiles_controller.dart';
import 'package:nini_hub/features/profiles/presentation/profile_provider_icon.dart';
import 'package:nini_hub/features/profiles/presentation/state/profiles_state.dart';

typedef ProfilesStateReader = ProfilesState Function();

Future<Profile?> showCreateProfileDialog(
  BuildContext context, {
  required ProfilesController controller,
  required ProfilesStateReader readState,
}) {
  controller.clearFailure();
  return showDialog<Profile>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _CreateProfileDialog(controller: controller, readState: readState),
  );
}

Future<Profile?> showRenameProfileDialog(
  BuildContext context, {
  required ProfilesController controller,
  required ProfilesStateReader readState,
  required String profileId,
  required String toolKey,
  required String profileName,
}) {
  controller.clearFailure();
  return showDialog<Profile>(
    context: context,
    builder: (_) => _RenameProfileDialog(
      controller: controller,
      readState: readState,
      profileId: profileId,
      toolKey: toolKey,
      profileName: profileName,
    ),
  );
}

Future<bool> showDeleteProfileDialog(
  BuildContext context, {
  required ProfilesController controller,
  required ProfilesStateReader readState,
  required String profileId,
  required String displayName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.delete_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text('Eliminar $displayName'),
      content: const SizedBox(
        width: 430,
        child: Text(
          'Multi CLI eliminará el perfil físico y su credencial local. El historial '
          'de esta aplicación también se borrará. Esta acción no cierra ni cancela '
          'ninguna suscripción.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Eliminar perfil'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  controller.clearFailure();
  final deleted = await controller.delete(DeleteProfileCommand(profileId));
  if (!deleted && context.mounted) {
    final message = readState().errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'Ya hay una operación de perfiles en curso.'),
      ),
    );
  }
  return deleted;
}

class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog({
    required this.controller,
    required this.readState,
  });

  final ProfilesController controller;
  final ProfilesStateReader readState;

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final displayName = TextEditingController();
  String toolKey = 'codex';
  ProfileSetupMode setupMode = ProfileSetupMode.shared;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    displayName.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    final created = await widget.controller.create(
      CreateProfileCommand(
        toolKey: toolKey,
        name: name.text,
        displayName: displayName.text,
        setupMode: setupMode,
        seedFromBase: false,
      ),
    );
    if (!mounted) return;
    if (created != null) {
      Navigator.pop(context, created);
      return;
    }
    setState(() {
      saving = false;
      error =
          widget.readState().errorMessage ??
          'Ya hay una operación de perfiles en curso.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = profileProvider(toolKey);
    final alias = name.text.trim().isEmpty ? 'alias' : name.text.trim();
    return AlertDialog(
      scrollable: true,
      title: const Text('Nuevo perfil'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: toolKey,
                decoration: const InputDecoration(labelText: 'Herramienta'),
                items: supportedProfileProviders
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.toolKey,
                        child: Row(
                          children: [
                            ProfileProviderIcon(
                              toolKey: item.toolKey,
                              size: 22,
                            ),
                            const SizedBox(width: 9),
                            Text('${item.displayName} · ${item.productName}'),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() => toolKey = value ?? toolKey),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Alias físico',
                  prefixText: provider.commandPrefix,
                  helperText: 'Nombre del perfil en multi-cli y del comando.',
                ),
                validator: _validateProfileName,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: displayName,
                decoration: const InputDecoration(
                  labelText: 'Nombre visible',
                  hintText: 'Nexo',
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Cómo empezar',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              RadioGroup<ProfileSetupMode>(
                groupValue: setupMode,
                onChanged: saving
                    ? (_) {}
                    : (value) {
                        if (value != null) setState(() => setupMode = value);
                      },
                child: const Column(
                  children: [
                    RadioListTile<ProfileSetupMode>(
                      value: ProfileSetupMode.shared,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      title: Text('Compartir ajustes'),
                      subtitle: Text(
                        'Usa las reglas, skills y configuración principal. La cuenta y el historial quedan separados.',
                      ),
                    ),
                    RadioListTile<ProfileSetupMode>(
                      value: ProfileSetupMode.full,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      title: Text('Independiente'),
                      subtitle: Text(
                        'Crea un perfil independiente, sin historial ni ajustes anteriores.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: Border(
                    left: BorderSide(
                      width: 3,
                      color: provider.supportsDeviceAuth
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      provider.supportsDeviceAuth
                          ? Icons.phonelink_lock_outlined
                          : Icons.login,
                      size: 19,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.supportsDeviceAuth
                                ? 'Acceso mediante Codex Device Auth'
                                : 'Acceso de Claude Code',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            provider.supportsDeviceAuth
                                ? 'Antes de continuar, abre Configuración > Seguridad en ChatGPT y habilita el acceso mediante código de dispositivo. Después de crear el perfil se abrirá el navegador y aparecerá el código para vincular la cuenta.'
                                : 'La vinculación automática todavía no está disponible para Claude. Después de crear el perfil, ábrelo y completa el acceso desde Claude Code.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'multi-cli new ${provider.profileSpec(alias)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
              : const Icon(Icons.add, size: 18),
          label: Text(
            provider.supportsDeviceAuth
                ? 'Crear y vincular'
                : 'Crear en ${provider.displayName}',
          ),
        ),
      ],
    );
  }
}

class _RenameProfileDialog extends StatefulWidget {
  const _RenameProfileDialog({
    required this.controller,
    required this.readState,
    required this.profileId,
    required this.toolKey,
    required this.profileName,
  });

  final ProfilesController controller;
  final ProfilesStateReader readState;
  final String profileId;
  final String toolKey;
  final String profileName;

  @override
  State<_RenameProfileDialog> createState() => _RenameProfileDialogState();
}

class _RenameProfileDialogState extends State<_RenameProfileDialog> {
  late final TextEditingController name = TextEditingController(
    text: widget.profileName,
  );
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      saving = true;
      error = null;
    });
    final renamed = await widget.controller.rename(
      RenameProfileCommand(profileId: widget.profileId, name: name.text),
    );
    if (!mounted) return;
    if (renamed != null) {
      Navigator.pop(context, renamed);
      return;
    }
    setState(() {
      saving = false;
      error =
          widget.readState().errorMessage ??
          'Ya hay una operación de perfiles en curso.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = profileProvider(widget.toolKey);
    return AlertDialog(
      title: const Text('Renombrar alias físico'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(prefixText: provider.commandPrefix),
              onSubmitted: (_) => saving ? null : submit(),
            ),
            const SizedBox(height: 12),
            Text(
              'Multi CLI moverá el directorio y creará el comando nuevo. La credencial '
              'local no se modifica, por lo que la cuenta vinculada conserva su acceso.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: saving ? null : submit,
          child: const Text('Renombrar'),
        ),
      ],
    );
  }
}

String? _validateProfileName(String? value) {
  try {
    ProfileName(value ?? '');
    return null;
  } on InvalidProfileNameFailure {
    return 'Usa entre 1 y 48 caracteres: letras, números, guion o guion bajo.';
  }
}
