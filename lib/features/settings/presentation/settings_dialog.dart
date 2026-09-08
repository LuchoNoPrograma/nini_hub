import 'package:nini_hub/features/heartbeat/domain/heartbeat_daily_schedule.dart';
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
  late bool keepTerminalOpenAfterExit;
  final root = TextEditingController();
  final heartbeatTimes = TextEditingController();
  final heartbeatInterval = TextEditingController();
  late Set<int> heartbeatDays;
  late bool repeatHeartbeat;
  String? scheduleError;

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
    keepTerminalOpenAfterExit = preferences.keepTerminalOpenAfterExit;
    root.text = preferences.profilesRoot;
    final schedule = preferences.heartbeatSchedule;
    heartbeatTimes.text = schedule.slots
        .map(
          (minute) =>
              '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}',
        )
        .join(', ');
    heartbeatDays = schedule.weekdays.toSet();
    repeatHeartbeat = schedule.intervalMinutes != null;
    heartbeatInterval.text = '${schedule.intervalMinutes ?? 300}';
  }

  @override
  void dispose() {
    root.dispose();
    heartbeatTimes.dispose();
    heartbeatInterval.dispose();
    super.dispose();
  }

  Future<void> save() async {
    HeartbeatDailySchedule schedule;
    try {
      final minutes = <int>[];
      if (!repeatHeartbeat) {
        for (final raw in heartbeatTimes.text.split(',')) {
          final value = raw.trim();
          if (!RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
            throw const FormatException(
              'Escribe horas como 07:00, 12:30, 17:00.',
            );
          }
          final parts = value.split(':').map(int.parse).toList();
          minutes.add(parts[0] * 60 + parts[1]);
        }
      }
      final interval = repeatHeartbeat
          ? int.tryParse(heartbeatInterval.text.trim())
          : null;
      if (repeatHeartbeat && interval == null) {
        throw const FormatException('Escribe un intervalo en minutos.');
      }
      schedule = HeartbeatDailySchedule(
        minutes: minutes,
        weekdays: heartbeatDays.toList(),
        intervalMinutes: interval,
      ).normalized();
    } catch (error) {
      setState(
        () => scheduleError = error is FormatException
            ? error.message
            : error is ArgumentError
            ? '${error.message}'
            : 'Revisa la programación.',
      );
      return;
    }
    setState(() => scheduleError = null);
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
            keepTerminalOpenAfterExit: keepTerminalOpenAfterExit,
            profilesRoot: root.text,
            heartbeatSchedule: schedule,
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
                key: const ValueKey('settings-font-scale'),
                value: fontScale,
                min: .8,
                max: 1.2,
                divisions: 8,
                label: '${(fontScale * 100).round()}%',
                onChanged: saving
                    ? null
                    : (value) => setState(() => fontScale = value),
              ),
              _TypographyPreview(
                theme: theme,
                accent: accent,
                fontScale: fontScale,
                fontFamily: fontFamily,
              ),
              const SizedBox(height: 6),
              Text(
                'Se aplicará a toda la aplicación al guardar.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
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
                title: const Text(
                  'Iniciar automáticamente los ciclos de Codex',
                ),
                subtitle: const Text(
                  'En cada horario se actualizan las cuentas. Si un ciclo está inactivo, se envía una solicitud mínima y se vuelve a consultar su uso. Nini Hub debe permanecer abierto.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Programación del heartbeat · hora local',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(
                        const [
                          'Lun',
                          'Mar',
                          'Mié',
                          'Jue',
                          'Vie',
                          'Sáb',
                          'Dom',
                        ][day - 1],
                      ),
                      selected: heartbeatDays.contains(day),
                      onSelected: saving
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                heartbeatDays.add(day);
                              } else {
                                heartbeatDays.remove(day);
                              }
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                initialValue: repeatHeartbeat,
                decoration: const InputDecoration(labelText: 'Frecuencia'),
                items: const [
                  DropdownMenuItem(
                    value: false,
                    child: Text('A horas específicas'),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text('Repetir por intervalo'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) =>
                          setState(() => repeatHeartbeat = value ?? false),
              ),
              const SizedBox(height: 12),
              if (repeatHeartbeat)
                TextField(
                  key: const Key('heartbeat-interval'),
                  controller: heartbeatInterval,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Intervalo en minutos',
                    helperText:
                        'De 15 a 1440 minutos, desde las 00:00 de cada día elegido.',
                  ),
                )
              else
                TextField(
                  key: const Key('heartbeat-times'),
                  controller: heartbeatTimes,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Horas separadas por comas',
                    hintText: '07:00, 12:30, 17:00',
                  ),
                ),
              if (scheduleError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    scheduleError!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              const Divider(height: 32),
              _Label('TERMINAL'),
              const SizedBox(height: 9),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: keepTerminalOpenAfterExit,
                onChanged: (value) =>
                    setState(() => keepTerminalOpenAfterExit = value),
                title: const Text('Mantener abierta al finalizar'),
                subtitle: const Text(
                  'Al terminar una sesión, incluso con Ctrl+C, deja la '
                  'terminal disponible. Escribe exit o cierra la ventana '
                  'cuando ya no la necesites.',
                ),
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

class _TypographyPreview extends StatelessWidget {
  const _TypographyPreview({
    required this.theme,
    required this.accent,
    required this.fontScale,
    required this.fontFamily,
  });

  final String theme;
  final String accent;
  final double fontScale;
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    final brightness = switch (theme) {
      'light' => Brightness.light,
      'system' => MediaQuery.platformBrightnessOf(context),
      _ => Brightness.dark,
    };
    final previewTheme = brightness == Brightness.dark
        ? AppTheme.dark(accent, fontScale: fontScale, fontFamily: fontFamily)
        : AppTheme.light(accent, fontScale: fontScale, fontFamily: fontFamily);
    final text = previewTheme.textTheme;
    return Container(
      key: const ValueKey('settings-typography-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: previewTheme.colorScheme.surface,
        border: Border.all(color: previewTheme.colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vista previa', style: text.labelMedium),
          const SizedBox(height: 6),
          Text('Cuenta personal', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Uso disponible y próximas renovaciones.',
            key: const ValueKey('settings-preview-body'),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Actualizado hace un momento',
            key: const ValueKey('settings-preview-label'),
            style: text.labelSmall?.copyWith(
              color: previewTheme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
