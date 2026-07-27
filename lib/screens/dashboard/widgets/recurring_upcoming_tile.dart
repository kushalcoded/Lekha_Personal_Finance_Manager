import 'package:flutter/material.dart';

import '../../../core/constants/category_styles.dart';
import '../../../models/recurring/recurring_expense_template.dart';
import '../../../utils/formatters/formatters.dart';

class UpcomingRecurringTile extends StatelessWidget {
  final RecurringExpenseTemplate template;
  final bool isDue;
  final bool isOverdue;
  final VoidCallback onGenerate;

  const UpcomingRecurringTile({
    super.key,
    required this.template,
    required this.isDue,
    required this.isOverdue,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = CategoryStyles.of(template.category);
    final statusColor = isOverdue
        ? colorScheme.error
        : isDue
        ? colorScheme.secondary
        : colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: style.tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(style.icon, color: style.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        template.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      AppFormatters.formatCurrency(template.amount),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip(
                      context,
                      template.frequency.label,
                      colorScheme.tertiary,
                    ),
                    _chip(
                      context,
                      _statusLabel(),
                      statusColor,
                    ),
                    _chip(context, template.paymentMethod, style.color),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Due ${AppFormatters.formatDate(template.nextDueDate)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: onGenerate,
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  String _statusLabel() {
    if (isOverdue) return 'Overdue';
    if (isDue) return 'Due now';
    return 'Upcoming';
  }

  Widget _chip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
