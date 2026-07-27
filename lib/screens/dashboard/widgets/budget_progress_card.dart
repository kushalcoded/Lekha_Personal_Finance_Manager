import 'package:flutter/material.dart';

import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/metric_tile.dart';

class BudgetProgressCard extends StatelessWidget {
  final String title;
  final double spent;
  final double budget;
  final double salary;
  final Color accentColor;
  final VoidCallback? onEditBudget;
  final VoidCallback? onEditSalary;
  final VoidCallback? onResetBudget;
  final VoidCallback? onResetSalary;

  const BudgetProgressCard({
    super.key,
    required this.title,
    required this.spent,
    required this.budget,
    this.salary = 0.0,
    required this.accentColor,
    this.onEditBudget,
    this.onEditSalary,
    this.onResetBudget,
    this.onResetSalary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final remaining = budget - spent;
    final hasBudget = budget > 0;
    final hasSalary = salary > 0;
    final isOverBudget = hasBudget && remaining < 0;
    final progressColor = isOverBudget
        ? colorScheme.error
        : progress >= 0.8
        ? colorScheme.secondary
        : accentColor;
    final plannedSavings = hasSalary ? salary - budget : 0.0;
    final actualSavings = hasSalary ? salary - spent : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.18)),
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
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onEditBudget != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEditSalary != null)
                      IconButton(
                        onPressed: onEditSalary,
                        icon: const Icon(Icons.payments_rounded, size: 18),
                        tooltip: 'Edit salary',
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      onPressed: onEditBudget,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      tooltip: 'Edit budget',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                )
              else
                Text(
                  hasBudget
                      ? '${(spent / budget * 100).toStringAsFixed(0)}% used'
                      : 'No budget set',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (onEditBudget != null) ...[
            const SizedBox(height: 4),
            Text(
              hasBudget
                  ? '${(spent / budget * 100).toStringAsFixed(0)}% used'
                  : 'No budget set',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              MetricTile(label: 'Spent', value: _formatCurrency(spent)),
              MetricTile(
                label: isOverBudget ? 'Overspent' : 'Remaining',
                value: _formatCurrency(remaining.abs()),
                valueColor: isOverBudget ? colorScheme.error : null,
              ),
              MetricTile(label: 'Budget', value: _formatCurrency(budget)),
              if (hasSalary)
                MetricTile(label: 'Salary', value: _formatCurrency(salary)),
              if (hasSalary)
                MetricTile(
                  label: 'Salary - Budget',
                  value: _formatCurrency(plannedSavings),
                  valueColor: plannedSavings < 0 ? colorScheme.error : null,
                ),
              if (hasSalary)
                MetricTile(
                  label: 'Salary - Spend',
                  value: _formatCurrency(actualSavings),
                  valueColor: actualSavings < 0 ? colorScheme.error : null,
                ),
            ],
          ),
          if (isOverBudget ||
              (!hasBudget && onEditBudget != null) ||
              (!hasSalary && onEditSalary != null)) ...[
            const SizedBox(height: 12),
            _BudgetAlert(
              message: isOverBudget
                  ? 'You are over your monthly budget.'
                  : !hasBudget
                  ? 'Set a budget to unlock spending intelligence.'
                  : 'Set salary to track planned and actual savings.',
              color: isOverBudget ? colorScheme.error : colorScheme.primary,
            ),
          ],
          if ((onResetBudget != null && hasBudget) ||
              (onResetSalary != null && hasSalary)) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (onResetSalary != null && hasSalary)
                    TextButton(
                      onPressed: onResetSalary,
                      child: const Text('Reset salary'),
                    ),
                  if (onResetBudget != null && hasBudget)
                    TextButton(
                      onPressed: onResetBudget,
                      child: const Text('Reset budget'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    return AppFormatters.formatCurrency(value);
  }
}


class _BudgetAlert extends StatelessWidget {
  final String message;
  final Color color;

  const _BudgetAlert({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
