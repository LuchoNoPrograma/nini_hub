import 'package:flutter/material.dart';
import 'package:multi_cli_ai/features/workspaces/domain/workspace.dart';
import 'package:multi_cli_ai/features/workspaces/presentation/controllers/workspace_controller.dart';

Future<void> renameWorkspace(
  BuildContext context,
  WorkspaceController controller,
  Workspace workspace,
) async {
  final nameController = TextEditingController(text: workspace.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Renombrar workspace'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Nombre'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(nameController.text),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  nameController.dispose();
  if (name == null) return;
  await controller.rename(workspaceId: workspace.id, name: name);
}

Future<void> forgetWorkspace(
  BuildContext context,
  WorkspaceController controller,
  Workspace workspace,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Quitar del historial'),
      content: Text(workspace.name),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Quitar'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.forget(workspace.id);
}
