import 'package:flutter/material.dart';

import '../../../core/constants/category_styles.dart';
import '../../../models/expense/expense_model.dart';
import '../../../utils/formatters/formatters.dart';
import '../utils/expense_helpers.dart';

Future<void> showExpenseDetailsSheet({
  required BuildContext context,
  required Expense expense,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 900;

  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ExpenseDetailsContent(
              expense: expense,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: ExpenseDetailsContent(
            expense: expense,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
      );
    },
  );
}

class ExpenseDetailsContent extends StatelessWidget {
  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// True when embedded in the desktop master-detail pane: no close button,
  /// and actions don't pop (there is no sheet/dialog to dismiss).
  final bool inline;

  const ExpenseDetailsContent({
    super.key,
    required this.expense,
    required this.onEdit,
    required this.onDelete,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = CategoryStyles.of(expense.category);
    final paymentMethod = formatPaymentMethod(expense);
    final notes = formatNotes(expense.description);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Expense Details',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!inline)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.32,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: style.tint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(style.icon, color: style.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: style.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppFormatters.formatCurrency(expense.amount),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _DetailRow(
            label: 'Date',
            value: AppFormatters.formatDate(
              expense.date,
              format: 'MMM dd, yyyy',
            ),
          ),
          _DetailRow(label: 'Notes', value: notes),
          _DetailRow(label: 'Payment method', value: paymentMethod),
          _DetailRow(
            label: 'Created',
            value: AppFormatters.formatDateTime(expense.createdAt),
          ),
          if (expense.updatedAt != null)
            _DetailRow(
              label: 'Updated',
              value: AppFormatters.formatDateTime(expense.updatedAt!),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  if (!inline) Navigator.of(context).pop();
                  onDelete();
                },
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                child: const Text('Delete'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  if (!inline) Navigator.of(context).pop();
                  onEdit();
                },
                child: const Text('Edit Expense'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
