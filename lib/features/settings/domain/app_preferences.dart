final class AppPreferences {
  const AppPreferences({
    required this.theme,
    required this.accent,
    required this.fontScale,
    required this.fontFamily,
    required this.concurrency,
    required this.timeoutSeconds,
    required this.compactCards,
    required this.weeklyKeepAliveEnabled,
    required this.keepTerminalOpenAfterExit,
    required this.profilesRoot,
  });

  static const defaults = AppPreferences(
    theme: 'dark',
    accent: 'cyan',
    fontScale: .9,
    fontFamily: 'system',
    concurrency: 3,
    timeoutSeconds: 15,
    compactCards: false,
    weeklyKeepAliveEnabled: true,
    keepTerminalOpenAfterExit: true,
    profilesRoot: '',
  );

  final String theme;
  final String accent;
  final double fontScale;
  final String fontFamily;
  final int concurrency;
  final int timeoutSeconds;
  final bool compactCards;
  final bool weeklyKeepAliveEnabled;
  final bool keepTerminalOpenAfterExit;
  final String profilesRoot;

  AppPreferences normalizedForSave() => AppPreferences(
    theme: theme,
    accent: accent,
    fontScale: fontScale.clamp(.8, 1.2).toDouble(),
    fontFamily: fontFamily,
    concurrency: concurrency.clamp(1, 6),
    timeoutSeconds: timeoutSeconds.clamp(5, 60),
    compactCards: compactCards,
    weeklyKeepAliveEnabled: weeklyKeepAliveEnabled,
    keepTerminalOpenAfterExit: keepTerminalOpenAfterExit,
    profilesRoot: profilesRoot.trim(),
  );
}
