import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/people/people_providers.dart';

/// Pin or hide a name offered by a people picker.
///
/// Long-press rather than a visible control: the pills are a fast path, and
/// hanging an X off each one would make the row read as a list to manage
/// instead of tap. Shared by the split sheet and the add-debt sheet so the
/// gesture means the same thing wherever a name pill appears.
Future<void> showPersonMenu(
  BuildContext context,
  WidgetRef ref,
  String name, {
  required bool isPinned,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            ),
            title: Text(isPinned ? 'Unpin $name' : 'Pin $name to the front'),
            onTap: () => Navigator.of(sheetContext).pop('pin'),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_rounded),
            title: Text('Hide $name'),
            subtitle: const Text('Undo in Settings → People'),
            onTap: () => Navigator.of(sheetContext).pop('hide'),
          ),
        ],
      ),
    ),
  );
  // The picker can be dismissed while this sheet is open; a live context is
  // what makes the ref safe to read.
  if (action == null || !context.mounted) return;
  final notifier = ref.read(peoplePrefsProvider.notifier);
  if (action == 'pin') {
    await notifier.togglePin(name);
  } else {
    await notifier.toggleHide(name);
  }
}
