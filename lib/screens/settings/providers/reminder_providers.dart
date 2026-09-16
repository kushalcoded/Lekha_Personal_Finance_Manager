import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/reminder/reminder_model.dart';
import '../../../providers/budget/budget_providers.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/payment/card_providers.dart';
import '../../expenses/providers/recurring_expenses_providers.dart';
import '../../receivables/providers/receivables_providers.dart';
import 'settings_providers.dart';
import '../../../utils/formatters/formatters.dart';

final upcomingRemindersProvider = Provider<List<AppReminder>>((ref) {
  final settings = ref.watch(settingsProvider);
  if (!settings.remindersEnabled) {
    return [];
  }

  final userId = ref.watch(currentUserIdProvider) ?? '';
  final now = DateTime.now();
  final reminders = <AppReminder>[];

  if (settings.budgetWarningReminderEnabled) {
    final budgetMetrics = ref.watch(budgetMetricsProvider(userId));
    if (budgetMetrics.hasBudget && budgetMetrics.isNearLimit) {
      reminders.add(
        AppReminder(
          id: 'budget_near_limit',
          type: ReminderType.budgetWarning,
          title: 'Budget warning',
          message: 'You are nearing your monthly budget limit.',
          dueAt: now,
          severity: ReminderSeverity.warning,
        ),
      );
    }
    if (budgetMetrics.hasBudget && budgetMetrics.isOverBudget) {
      reminders.add(
        AppReminder(
          id: 'budget_over_limit',
          type: ReminderType.budgetWarning,
          title: 'Budget exceeded',
          message: 'You have crossed your monthly budget.',
          dueAt: now,
          severity: ReminderSeverity.danger,
        ),
      );
    }
  }

  if (settings.cardBillReminderEnabled) {
    for (final card in ref.watch(cardsProvider)) {
      if (!card.hasCycle) continue;
      final outstanding = ref.watch(cardOutstandingProvider(card.method));
      if (outstanding <= 0.005) continue;
      final due = cardStatementPeriod(
        statementDay: card.statementDay!,
        dueDay: card.dueDay!,
        now: now,
      ).dueDate;
      final days = due
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      // Three days is enough warning to move money and not so much that the
      // nudge is background noise for a fortnight.
      if (days > 3) continue;
      reminders.add(
        AppReminder(
          id: 'card_bill_${card.method}',
          type: ReminderType.cardBillDue,
          title: '${card.method} bill',
          message: days < 0
              ? '${AppFormatters.formatCurrency(outstanding)} was due '
                    '${AppFormatters.formatDate(due)}.'
              : days == 0
              ? '${AppFormatters.formatCurrency(outstanding)} due today.'
              : '${AppFormatters.formatCurrency(outstanding)} due in $days '
                    '${days == 1 ? 'day' : 'days'}.',
          dueAt: due,
          severity: days < 0
              ? ReminderSeverity.danger
              : ReminderSeverity.warning,
        ),
      );
    }
  }

  if (settings.overdueReceivableReminderEnabled) {
    final overdue = ref.watch(overdueRecurringTemplatesProvider(userId)).length;
    final overdueReceivables = ref
        .watch(receivablesStatsProvider(userId))
        .overdueCount;
    if (overdueReceivables > 0) {
      reminders.add(
        AppReminder(
          id: 'overdue_receivables',
          type: ReminderType.overdueReceivable,
          title: 'Overdue receivables',
          message:
              '$overdueReceivables '
              '${AppFormatters.plural(overdueReceivables, 'receivable', 'receivables')} '
              '${AppFormatters.plural(overdueReceivables, 'is', 'are')} overdue.',
          dueAt: now,
          severity: ReminderSeverity.warning,
        ),
      );
    }
    if (overdue > 0) {
      reminders.add(
        AppReminder(
          id: 'overdue_recurring',
          type: ReminderType.upcomingRecurringExpense,
          title: 'Recurring templates overdue',
          message:
              '$overdue recurring '
              '${AppFormatters.plural(overdue, 'template', 'templates')} '
              '${AppFormatters.plural(overdue, 'is', 'are')} past due.',
          dueAt: now,
          severity: ReminderSeverity.info,
        ),
      );
    }
  }

  if (settings.recurringDueReminderEnabled) {
    final dueRecurring = ref.watch(dueRecurringTemplatesProvider(userId));
    if (dueRecurring.isNotEmpty) {
      reminders.add(
        AppReminder(
          id: 'due_recurring',
          type: ReminderType.upcomingRecurringExpense,
          title: 'Recurring expenses due',
          message:
              '${dueRecurring.length} recurring '
              '${AppFormatters.plural(dueRecurring.length, 'expense', 'expenses')} '
              '${AppFormatters.plural(dueRecurring.length, 'is', 'are')} due today.',
          dueAt: now,
          severity: ReminderSeverity.info,
        ),
      );
    }
  }

  if (settings.monthlyBudgetReminderEnabled) {
    final day = now.day;
    if (day <= 3) {
      reminders.add(
        AppReminder(
          id: 'monthly_budget_prompt',
          type: ReminderType.monthlyBudgetPrompt,
          title: 'Monthly budget check-in',
          message: 'Review and update your monthly budget goals.',
          dueAt: now,
          severity: ReminderSeverity.success,
        ),
      );
    }
  }

  reminders.sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return reminders;
});

/// The single line the daily notification carries, or null when nothing is
/// worth waking someone's phone for. The most severe reminder leads — they
/// arrive sorted — and the rest are a count, because a notification nobody
/// finishes reading is one they learn to swipe away.
({String title, String body})? reminderDigest(List<AppReminder> reminders) {
  if (reminders.isEmpty) return null;
  final first = reminders.first;
  final others = reminders.length - 1;
  return (
    title: first.title,
    body: others > 0 ? '${first.message} · $others more' : first.message,
  );
}
