import 'package:flutter/material.dart';

import '../../../models/reminder/reminder_model.dart';
import '../providers/productivity_providers.dart';
import '../../../utils/formatters/formatters.dart';

class ReminderCard extends StatelessWidget {
  final AppReminder reminder;

  const ReminderCard({super.key, required this.reminder});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _severityColor(colorScheme);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  reminder.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon() {
    switch (reminder.type) {
      case ReminderType.budgetWarning:
        return Icons.warning_amber_rounded;
      case ReminderType.overdueReceivable:
        return Icons.priority_high_rounded;
      case ReminderType.upcomingRecurringExpense:
        return Icons.repeat_rounded;
      case ReminderType.monthlyBudgetPrompt:
        return Icons.flag_rounded;
    }
  }

  Color _severityColor(ColorScheme scheme) {
    switch (reminder.severity) {
      case ReminderSeverity.info:
        return scheme.primary;
      case ReminderSeverity.warning:
        return scheme.secondary;
      case ReminderSeverity.danger:
        return scheme.error;
      case ReminderSeverity.success:
        return scheme.tertiary;
    }
  }
}

class BackupCard extends StatelessWidget {
  final BackupMetadata backup;
  final VoidCallback onRestore;

  const BackupCard({super.key, required this.backup, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backup.backupId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppFormatters.formatDateTime(backup.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${backup.expenseCount} ${AppFormatters.plural(backup.expenseCount, 'expense', 'expenses')}'
                  ' · ${backup.receivableCount} ${AppFormatters.plural(backup.receivableCount, 'receivable', 'receivables')}'
                  ' · ${backup.payableCount} ${AppFormatters.plural(backup.payableCount, 'payable', 'payables')}'
                  ' · ${backup.recurringTemplateCount} recurring',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onRestore, child: const Text('Restore')),
        ],
      ),
    );
  }
}
