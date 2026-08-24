import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_cli_ai/app/providers.dart';
import 'package:multi_cli_ai/core/theme/app_theme.dart';
import 'package:multi_cli_ai/core/widgets/app_primitives.dart';
import 'package:multi_cli_ai/features/dashboard/presentation/dashboard_shell.dart';

class MultiCliAiApp extends ConsumerWidget {
  const MultiCliAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(settingsBootstrapProvider);
    final preferences = ref.watch(
      settingsControllerProvider.select((state) => state.preferences),
    );
    final settingsErrorMessage = ref.watch(
      settingsControllerProvider.select((state) => state.errorMessage),
    );
    final mode = switch (preferences.theme) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MultiCLI AI',
      theme: AppTheme.light(
        preferences.accent,
        fontScale: preferences.fontScale,
        fontFamily: preferences.fontFamily,
      ),
      darkTheme: AppTheme.dark(
        preferences.accent,
        fontScale: preferences.fontScale,
        fontFamily: preferences.fontFamily,
      ),
      themeMode: mode,
      home: bootstrap.when(
        skipLoadingOnReload: false,
        data: (loaded) => loaded
            ? const DashboardShell()
            : _SettingsStartupFailure(
                message:
                    settingsErrorMessage ??
                    'No se pudo cargar la configuración.',
                onRetry: () => ref.invalidate(settingsBootstrapProvider),
              ),
        error: (_, _) => _SettingsStartupFailure(
          message: 'No se pudo cargar la configuración.',
          onRetry: () => ref.invalidate(settingsBootstrapProvider),
        ),
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              key: ValueKey('settings-startup-loading'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsStartupFailure extends StatelessWidget {
  const _SettingsStartupFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('settings-startup-failure'),
      body: EmptyState(
        icon: Icons.settings_outlined,
        title: 'No se pudo iniciar',
        message: message,
        action: FilledButton.icon(
          key: const ValueKey('settings-startup-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ),
    );
  }
}
