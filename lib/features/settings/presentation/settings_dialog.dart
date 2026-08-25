import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/features/settings/domain/app_preferences.dart';
import 'package:nini_hub/features/settings/presentation/controllers/settings_controller.dart';
import 'package:nini_hub/features/settings/presentation/state/settings_state.dart';

Future<bool> showSettingsDialog(
  BuildContext context,
  NotifierProvider<SettingsController, SettingsState> provider,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SettingsDialog(provider: provider),
    ) ??
    false;

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog({required this.provider});

  final NotifierProvider<SettingsController, SettingsState> provider;

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late String theme;
  late String accent;
  late double fontScale;
  late String fontFamily;
  late double concurrency;
  late double timeout;
  late bool compact;
  late bool weeklyKeepAlive;
  final root = TextEditingController();

  @override
  void initState() {
    super.initState();
    final preferences = ref.read(widget.provider).preferences;
    theme = preferences.theme;
    accent = preferences.accent;
    fontScale = preferences.fontScale;
    fontFamily = preferences.fontFamily;
    concurrency = preferences.concurrency.toDouble();
    timeout = preferences.timeoutSeconds.toDouble();
    compact = preferences.compactCards;
    weeklyKeepAlive = preferences.weeklyKeepAliveEnabled;
    root.text = preferences.profilesRoot;
  }

  @override
  void dispose() {
    root.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final saved = await ref
        .read(widget.provider.notifier)
        .save(
          AppPreferences(
            theme: theme,
            accent: accent,
            fontScale: fontScale,
            fontFamily: fontFamily,
            concurrency: concurrency.round(),
            timeoutSeconds: timeout.round(),
            compactCards: compact,
            weeklyKeepAliveEnabled: weeklyKeepAlive,
            profilesRoot: root.text,
          ),
        );
    if (mounted && saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(widget.provider);
    final saving = settingsState.isSaving;
    final error = settingsState.errorMessage;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Configuración'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label('APARIENCIA'),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: theme,
                      decoration: const InputDecoration(labelText: 'Tema'),
                      items: const [
                        DropdownMenuItem(value: 'dark', child: Text('Oscuro')),
                        DropdownMenuItem(value: 'light', child: Text('Claro')),
                        DropdownMenuItem(
                          value: 'system',
                          child: Text('Sistema'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => theme = value ?? 'dark'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: fontFamily,
                      decoration: const InputDecoration(
                        labelText: 'Tipografía',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text('Sistema'),
                        ),
                        DropdownMenuItem(
                          value: 'ubuntu',
                          child: Text('Ubuntu'),
                        ),
                        DropdownMenuItem(
                          value: 'noto',
                          child: Text('Noto Sans'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => fontFamily = value ?? 'system'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(child: Text('Tamaño del texto')),
                  Text('${(fontScale * 100).round()}%'),
                ],
              ),
              Slider(
                value: fontScale,
                min: .8,
                max: 1.2,
                divisions: 8,
                label: '${(fontScale * 100).round()}%',
                onChanged: (value) => setState(() => fontScale = value),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Color de énfasis')),
                  _AccentButton(
                    name: 'cyan',
                    color: AppTheme.cyan,
                    selected: accent == 'cyan',
                    onTap: () => setState(() => accent = 'cyan'),
                  ),
                  const SizedBox(width: 8),
                  _AccentButton(
                    name: 'mint',
                    color: AppTheme.mint,
                    selected: accent == 'mint',
                    onTap: () => setState(() => accent = 'mint'),
                  ),
                  const SizedBox(width: 8),
                  _AccentButton(
                    name: 'amber',
                    color: AppTheme.amber,
                    selected: accent == 'amber',
                    onTap: () => setState(() => accent = 'amber'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: compact,
                onChanged: (value) => setState(() => compact = value),
                title: const Text('Tarjetas compactas'),
                subtitle: const Text('Muestra menos ventanas por cuenta.'),
              ),
              const Divider(height: 32),
              _Label('CONSULTAS'),
              const SizedBox(height: 9),
              Row(
                children: [
                  const Expanded(child: Text('Cuentas en paralelo')),
                  Text('${concurrency.round()}'),
                ],
              ),
              Slider(
                value: concurrency,
                min: 1,
                max: 6,
                divisions: 5,
                label: '${concurrency.round()}',
                onChanged: (value) => setState(() => concurrency = value),
              ),
              Row(
                children: [
                  const Expanded(child: Text('Tiempo máximo por petición')),
                  Text('${timeout.round()} s'),
                ],
              ),
              Slider(
                value: timeout,
                min: 5,
                max: 60,
                divisions: 11,
                label: '${timeout.round()} s',
                onChanged: (value) => setState(() => timeout = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: weeklyKeepAlive,
                onChanged: (value) => setState(() => weeklyKeepAlive = value),
                title: const Text('Iniciar semanas de Codex'),
                subtitle: const Text(
                  'Comprueba una vez al iniciar. Después revisa cada cuenta '
                  'sólo al acercarse a su reinicio, al confirmar un ancla '
                  'ambigua o al reintentar con backoff.',
                ),
              ),
              Text(
                'La concurrencia está acotada para no abrir demasiados app-server '
                'al mismo tiempo. Cada cuenta conserva su propio límite y error.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const Divider(height: 32),
              _Label('MULTI-CLI'),
              const SizedBox(height: 9),
              TextField(
                controller: root,
                enabled: !saving,
                decoration: const InputDecoration(
                  labelText: 'Directorio de perfiles',
                  hintText: '~/MultiCliProfiles',
                  prefixIcon: Icon(Icons.folder_outlined, size: 18),
                  helperText: 'Vacío usa MULTICLI_HOME o ~/MultiCliProfiles.',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error, style: TextStyle(color: colors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      letterSpacing: 0,
    ),
  );
}

class _AccentButton extends StatelessWidget {
  const _AccentButton({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: switch (name) {
      'mint' => 'Menta',
      'amber' => 'Ámbar',
      _ => 'Cian',
    },
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Color(0xFF051014))
            : null,
      ),
    ),
  );
}
