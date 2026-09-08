import 'package:flutter/material.dart';

class AppTheme {
  static const Color cyan = Color(0xFF37D9F3);
  static const Color mint = Color(0xFF58E2AD);
  static const Color amber = Color(0xFFFFB84D);

  static Color accent(String value) => switch (value) {
    'mint' => mint,
    'amber' => amber,
    _ => cyan,
  };

  static ThemeData dark(
    String accentName, {
    double fontScale = .9,
    String fontFamily = 'system',
  }) => _theme(
    brightness: Brightness.dark,
    accent: accent(accentName),
    fontScale: fontScale,
    fontFamily: fontFamily,
    background: const Color(0xFF090D12),
    surface: const Color(0xFF10161D),
    elevated: const Color(0xFF151D26),
    border: const Color(0xFF26313C),
  );

  static ThemeData light(
    String accentName, {
    double fontScale = .9,
    String fontFamily = 'system',
  }) => _theme(
    brightness: Brightness.light,
    accent: accent(accentName),
    fontScale: fontScale,
    fontFamily: fontFamily,
    background: const Color(0xFFF3F6F7),
    surface: const Color(0xFFFFFFFF),
    elevated: const Color(0xFFEBF0F2),
    border: const Color(0xFFD5DEE2),
  );

  static ThemeData _theme({
    required Brightness brightness,
    required Color accent,
    required double fontScale,
    required String fontFamily,
    required Color background,
    required Color surface,
    required Color elevated,
    required Color border,
  }) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: dark
          ? accent
          : accent == mint
          ? const Color(0xFF006B4C)
          : accent == amber
          ? const Color(0xFF855000)
          : const Color(0xFF006878),
      onPrimary: dark ? const Color(0xFF051014) : Colors.white,
      secondary: dark ? const Color(0xFF9EB2C3) : const Color(0xFF45606E),
      onSecondary: dark ? Colors.black : Colors.white,
      error: dark ? const Color(0xFFFF8585) : const Color(0xFFB42332),
      onError: dark ? const Color(0xFF240609) : Colors.white,
      surface: surface,
      onSurface: dark ? const Color(0xFFEAF2F5) : const Color(0xFF12212A),
      outline: border,
      outlineVariant: border.withValues(alpha: .6),
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: elevated,
      surfaceContainerHigh: dark
          ? const Color(0xFF1A242E)
          : const Color(0xFFE3EAED),
      surfaceContainerHighest: dark
          ? const Color(0xFF202B35)
          : const Color(0xFFDCE5E8),
      onSurfaceVariant: dark
          ? const Color(0xFFB3C1CC)
          : const Color(0xFF465A66),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? Colors.white : const Color(0xFF172128),
      onInverseSurface: dark ? Colors.black : Colors.white,
      inversePrimary: accent,
      tertiary: dark ? const Color(0xFFFFC46B) : const Color(0xFF855000),
      onTertiary: dark ? const Color(0xFF211300) : Colors.white,
    );
    final scale = fontScale.clamp(.8, 1.2).toDouble();
    // Scale every role proportionally, including the smallest labels.
    double size(double value) => value * scale;
    final resolvedFamily = switch (fontFamily) {
      'ubuntu' => 'Ubuntu',
      'noto' => 'Noto Sans',
      _ => null,
    };
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: resolvedFamily,
      fontFamilyFallback: const ['Noto Sans', 'Segoe UI', 'sans-serif'],
      visualDensity: VisualDensity.compact,
      dividerColor: border,
      iconTheme: IconThemeData(size: 16, color: scheme.onSurfaceVariant),
      primaryIconTheme: IconThemeData(size: 16, color: scheme.onPrimary),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: size(32),
          fontWeight: FontWeight.w600,
        ),
        displayMedium: TextStyle(
          fontSize: size(28),
          fontWeight: FontWeight.w600,
        ),
        displaySmall: TextStyle(
          fontSize: size(26),
          fontWeight: FontWeight.w600,
        ),
        headlineLarge: TextStyle(
          fontSize: size(21),
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: TextStyle(
          fontSize: size(18),
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: TextStyle(
          fontSize: size(16),
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(fontSize: size(15), fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: size(13), fontWeight: FontWeight.w500),
        titleSmall: TextStyle(fontSize: size(12), fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontSize: size(13), height: 1.35),
        bodyMedium: TextStyle(fontSize: size(12), height: 1.35),
        bodySmall: TextStyle(fontSize: size(11), height: 1.3),
        labelLarge: TextStyle(fontSize: size(12), fontWeight: FontWeight.w500),
        labelMedium: TextStyle(fontSize: size(11), fontWeight: FontWeight.w500),
        labelSmall: TextStyle(fontSize: size(10), fontWeight: FontWeight.w500),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: size(15),
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: size(12),
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 5,
        shadowColor: Colors.black.withValues(alpha: dark ? .42 : .18),
        iconColor: scheme.onSurfaceVariant,
        iconSize: 15,
        textStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: size(12),
          fontWeight: FontWeight.w400,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final disabled = states.contains(WidgetState.disabled);
          return TextStyle(
            color: disabled
                ? scheme.onSurfaceVariant.withValues(alpha: .45)
                : scheme.onSurface,
            fontSize: size(12),
            fontWeight: FontWeight.w400,
          );
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: border),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        dividerColor: border,
        dividerHeight: 1,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: TextStyle(fontSize: size(12), fontWeight: FontWeight.w500),
        unselectedLabelStyle: TextStyle(
          fontSize: size(12),
          fontWeight: FontWeight.w400,
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: size(12),
          fontWeight: FontWeight.w400,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: size(11),
          fontWeight: FontWeight.w400,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        isDense: true,
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: size(12),
        ),
        helperMaxLines: 3,
        errorMaxLines: 3,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        prefixIconConstraints: const BoxConstraints.tightFor(width: 34),
        suffixIconConstraints: const BoxConstraints.tightFor(width: 34),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF25303A) : const Color(0xFF1B2A32),
          borderRadius: BorderRadius.circular(5),
        ),
        textStyle: TextStyle(color: Colors.white, fontSize: size(11)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(
            alpha: .38,
          ),
          minimumSize: const Size(38, 38),
          maximumSize: const Size(38, 38),
          padding: EdgeInsets.zero,
          iconSize: 18,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          disabledForegroundColor: scheme.onSurfaceVariant,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          textStyle: TextStyle(fontSize: size(11), fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(
            alpha: .45,
          ),
          side: BorderSide(color: border),
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          textStyle: TextStyle(fontSize: size(11), fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(
            alpha: .45,
          ),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: TextStyle(fontSize: size(11), fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          ),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: size(11), fontWeight: FontWeight.w500),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ),
    );
  }
}
