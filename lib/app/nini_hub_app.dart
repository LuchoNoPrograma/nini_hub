import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nini_hub/app/app_startup.dart';
import 'package:nini_hub/app/providers.dart';
import 'package:nini_hub/core/theme/app_theme.dart';
import 'package:nini_hub/core/widgets/app_primitives.dart';
import 'package:nini_hub/features/dashboard/presentation/dashboard_shell.dart';

class NiniHubApp extends ConsumerWidget {
  const NiniHubApp({super.key, this.startupFailure});

  final AppStartupFailure? startupFailure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (startupFailure case final failure?) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Nini Hub',
        theme: AppTheme.light('cyan'),
        darkTheme: AppTheme.dark('cyan'),
        themeMode: ThemeMode.dark,
        home: _DatabaseStartupFailure(failure: failure),
      );
    }

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
      title: 'Nini Hub',
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

class _DatabaseStartupFailure extends StatelessWidget {
  const _DatabaseStartupFailure({required this.failure});

  final AppStartupFailure failure;

  @override
  Widget build(BuildContext context) {
    final icon = switch (failure.kind) {
      AppStartupFailureKind.updateRequired => Icons.system_update_alt,
      AppStartupFailureKind.databaseInUse => Icons.lock_outline,
      AppStartupFailureKind.databaseConflict => Icons.warning_amber_outlined,
      AppStartupFailureKind.invalidDatabase => Icons.storage_outlined,
      AppStartupFailureKind.databaseUnavailable ||
      AppStartupFailureKind.unexpected => Icons.error_outline,
    };
    return Scaffold(
      key: const ValueKey('database-startup-failure'),
      body: EmptyState(
        icon: icon,
        title: failure.title,
        message: failure.message,
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
