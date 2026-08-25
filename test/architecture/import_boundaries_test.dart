import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _packagePrefix = 'package:nini_hub/';

const _approvedViolations = <String>{
  'lib/features/accounts/presentation/accounts_view.dart -> '
      'lib/app/providers.dart',
  'lib/features/activity/presentation/activity_view.dart -> '
      'lib/app/providers.dart',
  'lib/features/dashboard/presentation/dashboard_shell.dart -> '
      'lib/app/app_startup.dart',
  'lib/features/dashboard/presentation/dashboard_shell.dart -> '
      'lib/app/providers.dart',
  'lib/features/usage/presentation/calendar_view.dart -> '
      'lib/app/providers.dart',
};

void main() {
  test('feature dependencies respect architecture boundaries', () {
    final violations = <String>{};
    final dependencyPattern = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );

    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = _normalize(entity.path);
      for (final match in dependencyPattern.allMatches(
        entity.readAsStringSync(),
      )) {
        final uri = match.group(1)!;
        final target = _projectPath(source, uri);
        if (_isForbidden(source, target, uri)) {
          violations.add('$source -> $target');
        }
      }
    }

    final actual = violations.toList()..sort();
    final expected = _approvedViolations.toList()..sort();
    expect(
      actual,
      expected,
      reason:
          'Do not add new exceptions. Remove a baseline entry when its '
          'dependency is migrated.',
    );
  });
}

bool _isForbidden(String source, String target, String uri) {
  final sourceLayer = _layerOf(source)!;
  final targetLayer = _layerOf(target);

  if (uri == 'dart:io' ||
      uri.startsWith('package:drift/') ||
      uri.startsWith('package:drift_flutter/') ||
      uri.startsWith('package:file_selector/') ||
      uri.startsWith('package:path_provider/')) {
    return sourceLayer != _Layer.data;
  }

  if ((sourceLayer == _Layer.domain || sourceLayer == _Layer.application) &&
      (uri.startsWith('package:flutter/') ||
          uri.startsWith('package:flutter_riverpod/') ||
          uri.startsWith('package:url_launcher/') ||
          uri.startsWith('package:window_manager/'))) {
    return true;
  }

  return switch (sourceLayer) {
    _Layer.domain =>
      (targetLayer != null && targetLayer != _Layer.domain) ||
          target.startsWith('lib/app/') ||
          target.startsWith('lib/core/') ||
          target.startsWith('lib/providers/'),
    _Layer.application =>
      (targetLayer != null &&
              targetLayer != _Layer.application &&
              targetLayer != _Layer.domain) ||
          target.startsWith('lib/app/') ||
          target.startsWith('lib/core/') ||
          target.startsWith('lib/providers/'),
    _Layer.data =>
      targetLayer == _Layer.application ||
          targetLayer == _Layer.presentation ||
          target.startsWith('lib/app/'),
    _Layer.presentation =>
      targetLayer == _Layer.data ||
          target.startsWith('lib/app/') ||
          target.startsWith('lib/core/database/') ||
          target.startsWith('lib/core/process/') ||
          target.startsWith('lib/providers/'),
  };
}

String _projectPath(String source, String uri) {
  if (uri.startsWith(_packagePrefix)) {
    return 'lib/${uri.substring(_packagePrefix.length)}';
  }
  if (Uri.parse(uri).hasScheme) {
    return uri;
  }

  final root = _normalize(Directory.current.absolute.path);
  final resolved = _normalize(
    File.fromUri(File(source).absolute.uri.resolve(uri)).path,
  );
  return resolved.startsWith('$root/')
      ? resolved.substring(root.length + 1)
      : uri;
}

_Layer? _layerOf(String path) {
  final segments = _normalize(path).split('/');
  if (segments.length < 5 ||
      segments[0] != 'lib' ||
      segments[1] != 'features') {
    return null;
  }
  return switch (segments[3]) {
    'domain' => _Layer.domain,
    'application' => _Layer.application,
    'data' => _Layer.data,
    'presentation' => _Layer.presentation,
    _ => null,
  };
}

String _normalize(String path) => path.replaceAll('\\', '/');

enum _Layer { domain, application, data, presentation }
