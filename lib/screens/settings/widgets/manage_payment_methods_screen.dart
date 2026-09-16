import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../providers/payment/payment_method_providers.dart';
import '../../../widgets/common/glass.dart';
import '../../../widgets/common/top_notice.dart';

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
    final notifier = ref.read(paymentMethodsProvider.notifier);
    final controller = TextEditingController(text: existing ?? '');
    final stored = existing == null ? null : notifier.cardConfig(existing);
    var isCard = stored != null;
    var statementDay = stored?['statementDay'];
    var dueDay = stored?['dueDay'];

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add method' : 'Edit method'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'UPI, Amex, Wallet…',
                  ),
                  onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
                ),
                const SizedBox(height: 8),
                // Off by default, and the statement fields stay hidden until
                // it is on: most methods are not cards, and two extra day
                // pickers on every one of them is noise.
                SwitchListTile(
                  value: isCard,
                  onChanged: (value) => setLocal(() => isCard = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Credit card'),
                  subtitle: const Text('Track a bill and what is still owed'),
                ),
                if (isCard) ...[
                  const SizedBox(height: 4),
                  _DayPicker(
                    label: 'Statement closes on',
                    value: statementDay,
                    onChanged: (value) => setLocal(() => statementDay = value),
                  ),
                  const SizedBox(height: 8),
                  _DayPicker(
                    label: 'Payment due on',
                    value: dueDay,
                    onChanged: (value) => setLocal(() => dueDay = value),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Optional. Without them the balance still works — you just '
                    "won't see what this month's bill comes to.",
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    final name = controller.text.trim();
    if (saved != true || name.isEmpty) return;

    final ok = existing == null
        ? await notifier.add(name)
        : await notifier.rename(existing, name);
    // rename returns false when the name did not change, which is not a
    // failure — only a genuine clash is.
    if (existing == null && !ok) {
      if (context.mounted) showNotice('That method already exists.');
      return;
    }
    await notifier.setCard(
      name,
      isCard: isCard,
      statementDay: statementDay,
      dueDay: dueDay,
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

/// A day of the month, 1-31. A dropdown rather than a field because there is
/// nothing to validate and nothing to mistype.
class _DayPicker extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _DayPicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        DropdownButton<int?>(
          value: value,
          hint: const Text('—'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (var day = 1; day <= 31; day++)
              DropdownMenuItem<int?>(value: day, child: Text('$day')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
