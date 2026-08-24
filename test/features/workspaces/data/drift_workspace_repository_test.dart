import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_cli_ai/core/database/app_database.dart';
import 'package:multi_cli_ai/features/workspaces/data/drift_workspace_repository.dart';
import 'package:multi_cli_ai/features/workspaces/data/drift_workspace_selection_store.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace_failure.dart';

void main() {
  late AppDatabase database;
  late DriftWorkspaceRepository repository;
  late DriftWorkspaceSelectionStore selectionStore;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftWorkspaceRepository(database);
    selectionStore = DriftWorkspaceSelectionStore(database);
  });

  tearDown(() => database.close());

  test('maps workspace rows and preserves history operations', () async {
    final root = await Directory.systemTemp.createTemp('workspace-data-');
    addTearDown(() => root.delete(recursive: true));
    final firstDirectory = Directory('${root.path}/first');
    final secondDirectory = Directory('${root.path}/second');
    await firstDirectory.create();
    await secondDirectory.create();

    final first = await repository.add('${firstDirectory.path}/.');
    await repository.recordOpened(firstDirectory.path);
    final opened = await repository.recordOpened('${firstDirectory.path}/.');
    final second = await repository.add(secondDirectory.path);

    expect(first.id, opened.id);
    expect(opened.openCount, 2);
    expect(opened.createdAt.isUtc, isTrue);
    expect(opened.lastUsedAt.isUtc, isTrue);
    expect(await repository.findById(first.id), isNotNull);
    expect(await repository.findById('missing'), isNull);

    final beforeSelect = opened;
    await repository.select(first.id);
    await repository.rename(workspaceId: first.id, name: '  Principal  ');
    final workspaces = await repository.loadAll();
    final selected = workspaces.singleWhere((item) => item.id == first.id);
    expect(workspaces.first.id, first.id);
    expect(selected.name, 'Principal');
    expect(selected.openCount, beforeSelect.openCount);
    expect(selected.lastUsedAt.isAfter(beforeSelect.lastUsedAt), isTrue);
    expect(workspaces.singleWhere((item) => item.id == second.id).openCount, 0);

    await repository.remove(second.id);
    expect(await repository.findById(second.id), isNull);
  });

  test('translates expected path and name failures', () async {
    final root = await Directory.systemTemp.createTemp('workspace-failure-');
    addTearDown(() => root.delete(recursive: true));
    final workspace = await repository.add(root.path);

    await expectLater(
      repository.add('${root.path}/missing'),
      throwsA(isA<InvalidWorkspacePathFailure>()),
    );
    await expectLater(
      repository.rename(workspaceId: workspace.id, name: '   '),
      throwsA(isA<InvalidWorkspaceNameFailure>()),
    );
  });

  test('reads existing workspace rows without rewriting stored data', () async {
    final createdAt = DateTime.utc(2025, 1, 2, 3, 4, 5);
    final lastUsedAt = createdAt.add(const Duration(days: 1));
    await database
        .into(database.workspaces)
        .insert(
          WorkspacesCompanion.insert(
            id: 'existing-workspace',
            path: '/persisted/workspace',
            pathKey: '/persisted/workspace',
            name: 'Persistido',
            openCount: const Value(7),
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
          ),
        );

    final workspace = await repository.findById('existing-workspace');

    expect(workspace, isNotNull);
    expect(workspace!.path, '/persisted/workspace');
    expect(workspace.name, 'Persistido');
    expect(workspace.openCount, 7);
    expect(workspace.createdAt, createdAt);
    expect(workspace.lastUsedAt, lastUsedAt);
    expect(workspace.createdAt.isUtc, isTrue);
    expect(workspace.lastUsedAt.isUtc, isTrue);
  });

  test(
    'deduplicates workspace path casing on Windows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'workspace-windows-case-',
      );
      addTearDown(() => directory.delete(recursive: true));

      final original = await repository.add(directory.path);
      final caseVariant = await repository.add(directory.path.toUpperCase());

      expect(caseVariant.id, original.id);
      expect(await repository.loadAll(), hasLength(1));
    },
    skip: Platform.isWindows ? false : 'Requires a Windows runtime.',
  );

  test('stores nullable selection with legacy empty-string encoding', () async {
    expect(await selectionStore.loadCurrentWorkspaceId(), isNull);

    await database.saveSetting('current_workspace_id', '   ');
    expect(await selectionStore.loadCurrentWorkspaceId(), isNull);

    await selectionStore.saveCurrentWorkspaceId(' workspace-id ');
    expect(await selectionStore.loadCurrentWorkspaceId(), ' workspace-id ');

    await selectionStore.saveCurrentWorkspaceId(null);
    expect(await database.setting('current_workspace_id'), '');
    expect(await selectionStore.loadCurrentWorkspaceId(), isNull);
  });
}
