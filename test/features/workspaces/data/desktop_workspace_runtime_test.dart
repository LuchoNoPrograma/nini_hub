import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nini_hub/features/workspaces/data/desktop_workspace_runtime.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desktop-workspace-runtime-');
  });

  tearDown(() => root.delete(recursive: true));

  test('normalizes an existing working directory', () {
    expect(
      DesktopWorkspaceRuntime.validateWorkingDirectory('${root.path}/.'),
      root.absolute.path,
    );
  });

  test('rejects a working directory that no longer exists', () {
    expect(
      () => DesktopWorkspaceRuntime.validateWorkingDirectory(
        '${root.path}/missing',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('resolves the platform home and rejects a missing home', () {
    expect(
      DesktopWorkspaceRuntime.userHomeDirectory(
        environment: {'HOME': root.path},
        isWindows: false,
      ),
      root.absolute.path,
    );
    expect(
      () => DesktopWorkspaceRuntime.userHomeDirectory(
        environment: const {},
        isWindows: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('builds a compact title from the profile and workspace', () {
    expect(
      DesktopWorkspaceRuntime.buildTerminalTitle(
        profileName: 'team',
        workingDirectory: '${root.path}/project',
      ),
      'team · project',
    );
  });
}
