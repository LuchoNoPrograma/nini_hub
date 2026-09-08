import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/core/theme/app_theme.dart';

void main() {
  for (final buildTheme in [AppTheme.dark, AppTheme.light]) {
    final brightness = buildTheme('cyan').brightness.name;
    test('$brightness: every text role responds to every size step', () {
      final normal = _sizes(buildTheme('cyan', fontScale: 1));
      var previous = <String, double>{};
      for (var step = 0; step <= 8; step++) {
        final scale = .8 + step * .05;
        final sizes = _sizes(buildTheme('cyan', fontScale: scale));
        for (final entry in sizes.entries) {
          expect(
            entry.value,
            closeTo(normal[entry.key]! * scale, .00001),
            reason: '${entry.key} at $scale',
          );
          if (previous.isNotEmpty) {
            expect(entry.value, greaterThan(previous[entry.key]!));
          }
        }
        previous = sizes;
      }
    });

    test('$brightness: compact typography preserves hierarchy and targets', () {
      for (final scale in [.8, .9, 1.2]) {
        final theme = buildTheme('cyan', fontScale: scale);
        final text = theme.textTheme;
        expect(
          text.titleLarge!.fontSize,
          greaterThan(text.bodyLarge!.fontSize!),
        );
        expect(
          text.bodyLarge!.fontSize,
          greaterThan(text.bodyMedium!.fontSize!),
        );
        expect(
          text.bodyMedium!.fontSize,
          greaterThan(text.bodySmall!.fontSize!),
        );
        expect(
          text.labelLarge!.fontSize,
          greaterThan(text.labelSmall!.fontSize!),
        );
        expect(
          theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
          38,
        );
        expect(
          theme.iconButtonTheme.style!.minimumSize!.resolve({})!.height,
          38,
        );
      }
      expect(
        buildTheme('cyan', fontScale: .8).textTheme.bodyMedium!.fontSize,
        closeTo(9.6, .00001),
      );
      expect(
        _sizes(buildTheme('cyan', fontScale: .5)),
        _sizes(buildTheme('cyan', fontScale: .8)),
      );
      expect(
        _sizes(buildTheme('cyan', fontScale: 2)),
        _sizes(buildTheme('cyan', fontScale: 1.2)),
      );
    });
  }
}

Map<String, double> _sizes(ThemeData theme) {
  final text = theme.textTheme;
  return {
    'displayLarge': text.displayLarge!.fontSize!,
    'displayMedium': text.displayMedium!.fontSize!,
    'displaySmall': text.displaySmall!.fontSize!,
    'headlineLarge': text.headlineLarge!.fontSize!,
    'headlineMedium': text.headlineMedium!.fontSize!,
    'headlineSmall': text.headlineSmall!.fontSize!,
    'titleLarge': text.titleLarge!.fontSize!,
    'titleMedium': text.titleMedium!.fontSize!,
    'titleSmall': text.titleSmall!.fontSize!,
    'bodyLarge': text.bodyLarge!.fontSize!,
    'bodyMedium': text.bodyMedium!.fontSize!,
    'bodySmall': text.bodySmall!.fontSize!,
    'labelLarge': text.labelLarge!.fontSize!,
    'labelMedium': text.labelMedium!.fontSize!,
    'labelSmall': text.labelSmall!.fontSize!,
    'dialogTitle': theme.dialogTheme.titleTextStyle!.fontSize!,
    'dialogContent': theme.dialogTheme.contentTextStyle!.fontSize!,
    'popup': theme.popupMenuTheme.labelTextStyle!.resolve({})!.fontSize!,
    'tab': theme.tabBarTheme.labelStyle!.fontSize!,
    'unselectedTab': theme.tabBarTheme.unselectedLabelStyle!.fontSize!,
    'listTitle': theme.listTileTheme.titleTextStyle!.fontSize!,
    'listSubtitle': theme.listTileTheme.subtitleTextStyle!.fontSize!,
    'inputLabel': theme.inputDecorationTheme.labelStyle!.fontSize!,
    'tooltip': theme.tooltipTheme.textStyle!.fontSize!,
    'filledButton': theme.filledButtonTheme.style!.textStyle!
        .resolve({})!
        .fontSize!,
    'outlinedButton': theme.outlinedButtonTheme.style!.textStyle!
        .resolve({})!
        .fontSize!,
    'textButton': theme.textButtonTheme.style!.textStyle!
        .resolve({})!
        .fontSize!,
    'segmentedButton': theme.segmentedButtonTheme.style!.textStyle!
        .resolve({})!
        .fontSize!,
  };
}
