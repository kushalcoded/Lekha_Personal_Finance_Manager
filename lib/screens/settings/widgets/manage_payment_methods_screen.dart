import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../providers/payment/payment_method_providers.dart';
import '../../../widgets/common/glass.dart';

/// Add, rename, reorder and delete the payment methods offered when adding an
/// expense, and pick the one used when nobody can be asked — the notification
/// shade has no picker, and the add sheet preselects it.
class ManagePaymentMethodsScreen extends ConsumerWidget {
  const ManagePaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider);
    final defaultMethod = ref.watch(defaultPaymentMethodProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Payment Methods'), elevation: 0),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add method'),
      ),
      body: SlidableAutoCloseBehavior(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: methods.length,
          onReorder: (oldIndex, newIndex) => ref
              .read(paymentMethodsProvider.notifier)
              .reorder(oldIndex, newIndex),
          header: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'The first method is easiest to reach when adding an expense. '
              'Star one to preselect it and to tag spends you approve from a '
              'notification.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          itemBuilder: (context, index) {
            final method = methods[index];
            return _MethodRow(
              key: ValueKey(method),
              method: method,
              index: index,
              isDefault: method == defaultMethod,
              usageCount: ref
                  .read(paymentMethodsProvider.notifier)
                  .usageCount(method),
              onSetDefault: () => ref
                  .read(paymentMethodsProvider.notifier)
                  .setDefault(method == defaultMethod ? null : method),
              onRename: () => _openEditor(context, ref, existing: method),
              onDelete: () => _confirmDelete(context, ref, method),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    String? existing,
  }) async {
    final controller = TextEditingController(text: existing ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'Add method' : 'Rename method'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'UPI, Amex, Wallet…'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    final notifier = ref.read(paymentMethodsProvider.notifier);
    final ok = existing == null
        ? await notifier.add(name)
        : await notifier.rename(existing, name);
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That method already exists.')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String method,
  ) async {
    final count = ref.read(paymentMethodsProvider.notifier).usageCount(method);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $method?'),
        content: Text(
          count == 0
              ? 'Nothing is tagged with it.'
              : '$count expense${count == 1 ? '' : 's'} keep this label and '
                    'still show in the payment breakdown — you just stop being '
                    'offered it on new expenses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(paymentMethodsProvider.notifier).remove(method);
  }
}

class _MethodRow extends StatelessWidget {
  final String method;
  final int index;
  final bool isDefault;
  final int usageCount;
  final VoidCallback onSetDefault;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _MethodRow({
    super.key,
    required this.method,
    required this.index,
    required this.isDefault,
    required this.usageCount,
    required this.onSetDefault,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.5,
          children: [
            SlidableAction(
              onPressed: (_) => onRename(),
              icon: Icons.edit_rounded,
              label: 'Rename',
              backgroundColor: cs.surfaceContainerHighest,
              foregroundColor: cs.onSurface,
            ),
            SlidableAction(
              onPressed: (_) => onDelete(),
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              backgroundColor: cs.error.withValues(alpha: 0.16),
              foregroundColor: cs.error,
            ),
          ],
        ),
        child: GlassCard(
          radius: 12,
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDefault
                          ? 'Default'
                          : usageCount == 0
                          ? 'Unused'
                          : '$usageCount expense${usageCount == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDefault ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onSetDefault,
                tooltip: isDefault ? 'Clear default' : 'Make default',
                icon: Icon(
                  isDefault ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isDefault ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
