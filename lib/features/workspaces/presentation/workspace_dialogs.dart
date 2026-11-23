import 'package:flutter/material.dart';
import 'package:nini_hub/features/workspaces/domain/workspace.dart';
import 'package:nini_hub/features/workspaces/presentation/controllers/workspace_controller.dart';

Future<void> renameWorkspace(
  BuildContext context,
  WorkspaceController controller,
  Workspace workspace,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameWorkspaceDialog(initialName: workspace.name),
  );
  if (name == null) return;
  await controller.rename(workspaceId: workspace.id, name: name);
}

class _RenameWorkspaceDialog extends StatefulWidget {
  const _RenameWorkspaceDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameWorkspaceDialog> createState() => _RenameWorkspaceDialogState();
}

// The dialog owns its text controller, so the controller lives exactly as long
// as the field that uses it, including the closing animation.
class _RenameWorkspaceDialogState extends State<_RenameWorkspaceDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _name.text.trim();
    if (value.isEmpty) {
      // Rejected here: once the dialog is closed the failure had no visible
      // place to appear.
      setState(() => _error = 'El nombre no puede quedar vacío.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Renombrar workspace'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 80,
      decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar')),
    ],
  );
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
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              workspace.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(workspace.path, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            const Text(
              'Solo se quita de esta lista. La carpeta no se borra del disco.',
            ),
          ],
        ),
      ),
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
