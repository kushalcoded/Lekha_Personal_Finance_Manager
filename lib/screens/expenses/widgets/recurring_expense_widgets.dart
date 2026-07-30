import 'package:flutter/material.dart';

import '../../../models/recurring/recurring_expense_template.dart';
import '../../../utils/formatters/formatters.dart';
import '../providers/recurring_expenses_providers.dart';

class RecurringExpensesSectionHeader extends StatelessWidget {
  final VoidCallback onCreate;

  const RecurringExpensesSectionHeader({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recurring Expenses',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Manage templates and generate due expenses',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Template'),
        ),
      ],
    );
  }
}

class RecurringTemplateCard extends StatelessWidget {
  final RecurringExpenseTemplate template;
  final bool isDue;
  final bool isOverdue;
  final VoidCallback onGenerate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const RecurringTemplateCard({
    super.key,
    required this.template,
    required this.isDue,
    required this.isOverdue,
    required this.onGenerate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dueColor = isOverdue
        ? colorScheme.error
        : isDue
        ? colorScheme.secondary
        : colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue
              ? colorScheme.error.withValues(alpha: 0.35)
              : colorScheme.outline.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  template.category,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                AppFormatters.formatCurrency(template.amount),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, template.frequency.label, colorScheme.primary),
              _chip(
                context,
                isOverdue
                    ? 'Overdue'
                    : isDue
                    ? 'Due now'
                    : 'Upcoming',
                dueColor,
              ),
              _chip(context, template.paymentMethod, colorScheme.tertiary),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Next due: ${AppFormatters.formatDate(template.nextDueDate)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if ((template.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              template.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onGenerate,
                  child: const Text('Generate Expense'),
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Edit',
              ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
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

class RecurringTemplateFilterBar extends StatelessWidget {
  final RecurringTemplateFilter selected;
  final ValueChanged<RecurringTemplateFilter> onChange;

  const RecurringTemplateFilterBar({
    super.key,
    required this.selected,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: RecurringTemplateFilter.values.map((filter) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: filter == selected,
              label: Text(_label(filter)),
              onSelected: (_) => onChange(filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(RecurringTemplateFilter filter) {
    switch (filter) {
      case RecurringTemplateFilter.all:
        return 'All';
      case RecurringTemplateFilter.due:
        return 'Due';
      case RecurringTemplateFilter.upcoming:
        return 'Upcoming';
      case RecurringTemplateFilter.overdue:
        return 'Overdue';
    }
  }
}
