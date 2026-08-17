import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/category_styles.dart';
import '../../../providers/budget/category_budget_providers.dart';
import '../../../utils/amount_expression.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/glass.dart';
import '../../expenses/providers/expenses_providers.dart';
import '../../expenses/utils/expense_helpers.dart';

/// A spending limit per category, for the current cycle. Categories without
/// one are simply uncapped — the add sheet only draws a bar for the ones set
/// here, and only warns on save when a limit would actually be crossed.
class ManageCategoryBudgetsScreen extends ConsumerWidget {
  const ManageCategoryBudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final categories = ref.watch(orderedCategoriesProvider).all;
    final budgets = ref.watch(categoryBudgetsProvider);
    final capped = budgets.values.fold<double>(0, (sum, v) => sum + v);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Category budgets'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            capped > 0
                ? 'Capped categories add up to '
                      '${AppFormatters.formatCurrency(capped)} a cycle. '
                      'Everything else is uncapped.'
                : 'Set a limit on the categories that get away from you. '
                      'The add-expense sheet then shows where you stand, and '
                      'asks before a spend takes you over.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            radius: 12,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final category in categories)
                  _BudgetRow(
                    category: category,
                    status: ref.watch(categoryBudgetStatusProvider(category)),
                    onTap: () => _editLimit(context, ref, category),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLimit(
    BuildContext context,
    WidgetRef ref,
    String category,
  ) async {
    final current = ref.read(categoryBudgetsProvider)[category] ?? 0;
    final controller = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(0) : '',
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$category budget'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: '₹ ',
            hintText: 'Leave empty for no limit',
          ),
          onSubmitted: (value) => Navigator.of(
            dialogContext,
          ).pop(parseAmountExpression(value.trim()) ?? 0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          if (current > 0)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(0),
              child: const Text('Remove'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(parseAmountExpression(controller.text.trim()) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    await ref.read(categoryBudgetsProvider.notifier).setLimit(category, amount);
  }
}

class _BudgetRow extends StatelessWidget {
  final String category;
  final CategoryBudgetStatus status;
  final VoidCallback onTap;

  const _BudgetRow({
    required this.category,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = CategoryStyles.of(category);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: style.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (status.isCapped) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${AppFormatters.formatCurrency(status.spent)} spent '
                      'this cycle',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.isOver ? cs.error : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              status.isCapped
                  ? AppFormatters.formatCurrency(status.limit)
                  : 'No limit',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: status.isCapped ? cs.onSurface : cs.onSurfaceVariant,
                fontWeight: status.isCapped ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
