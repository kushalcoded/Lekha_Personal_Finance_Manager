import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/recurring/recurring_expense_template.dart';
import '../../../providers/budget/budget_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../expenses/providers/recurring_expenses_providers.dart';
import '../models/analytics_models.dart';
import '../../../utils/formatters/formatters.dart';

final recurringObligationSummaryProvider =
    Provider.family<RecurringObligationSummary, String>((ref, userId) {
      final templates = ref
          .watch(recurringTemplatesProvider)
          .templates
          .where((template) => template.userId == userId && template.isActive)
          .toList();

      final now = DateTime.now();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

      var monthlyTotal = 0.0;
      for (final template in templates) {
        monthlyTotal += _monthlyEquivalent(template, daysInMonth: daysInMonth);
      }

      final annualTotal = monthlyTotal * 12;
      final averageDaily = daysInMonth > 0 ? monthlyTotal / daysInMonth : 0.0;

      final upcoming = ref.watch(upcomingRecurringTemplatesProvider(userId));
      final upcomingTotal = upcoming.fold<double>(
        0.0,
        (sum, template) => sum + template.amount,
      );

      return RecurringObligationSummary(
        monthlyTotal: monthlyTotal,
        annualTotal: annualTotal,
        averageDaily: averageDaily,
        templateCount: templates.length,
        upcomingTotal: upcomingTotal,
        upcomingCount: upcoming.length,
      );
    });

final recurringCategoryStatsProvider =
    Provider.family<List<CategoryStat>, String>((ref, userId) {
      final templates = ref
          .watch(recurringTemplatesProvider)
          .templates
          .where((template) => template.userId == userId && template.isActive)
          .toList();
      final now = DateTime.now();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

      final totals = <String, double>{};
      for (final template in templates) {
        totals[template.category] =
            (totals[template.category] ?? 0) +
            _monthlyEquivalent(template, daysInMonth: daysInMonth);
      }

      final totalSpent = totals.values.fold(0.0, (sum, value) => sum + value);
      final stats =
          totals.entries
              .map(
                (entry) => CategoryStat(
                  category: entry.key,
                  amount: entry.value,
                  percent: totalSpent > 0
                      ? (entry.value / totalSpent) * 100
                      : 0,
                ),
              )
              .toList()
            ..sort((a, b) => b.amount.compareTo(a.amount));
      return stats;
    });

final burnRateForecastProvider = Provider.family<BurnRateForecast, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(expensesProvider).expenses;
  final metrics = ref.watch(budgetMetricsProvider(userId));
  final recurringSummary = ref.watch(
    recurringObligationSummaryProvider(userId),
  );

  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final thirtyDaysAgo = now.subtract(const Duration(days: 30));

  final recentExpenses = expenses.where(
    (expense) =>
        expense.userId == userId && expense.date.isAfter(thirtyDaysAgo),
  );
  final recentTotal = recentExpenses.fold<double>(
    0.0,
    (sum, expense) => sum + expense.amount,
  );
  final actualDaily = recentTotal / 30;

  final recurringDaily = recurringSummary.averageDaily;
  final projectedMonthEnd = (actualDaily + recurringDaily) * daysInMonth;
  final remainingBudget = metrics.hasBudget
      ? metrics.budget - projectedMonthEnd
      : 0.0;

  return BurnRateForecast(
    actualDaily: actualDaily,
    recurringDaily: recurringDaily,
    projectedMonthEnd: projectedMonthEnd,
    budget: metrics.budget,
    remainingBudget: remainingBudget,
  );
});

final recurringFixedObligationInsightsProvider =
  Provider.family<List<SmartFinancialInsight>, String>((ref, userId) {
      final recurringSummary = ref.watch(
        recurringObligationSummaryProvider(userId),
      );
      final metrics = ref.watch(budgetMetricsProvider(userId));
      final forecast = ref.watch(burnRateForecastProvider(userId));
      final insights = <SmartFinancialInsight>[];

      if (recurringSummary.templateCount == 0) {
        insights.add(
          const SmartFinancialInsight(
            title: 'No fixed obligations yet',
            message: 'Create recurring templates to track fixed monthly costs.',
            icon: Icons.repeat_rounded,
            severity: InsightSeverity.info,
          ),
        );
        return insights;
      }

      insights.add(
        SmartFinancialInsight(
          title: 'Fixed obligations total',
          message:
              '${recurringSummary.templateCount} templates total '
              '${AppFormatters.formatCurrency(recurringSummary.monthlyTotal)} per month.',
          icon: Icons.lock_rounded,
          severity: InsightSeverity.info,
        ),
      );

      if (metrics.hasBudget &&
          recurringSummary.monthlyTotal > metrics.budget * 0.6) {
        insights.add(
          const SmartFinancialInsight(
            title: 'Fixed costs are heavy',
            message: 'Recurring obligations take a large share of your budget.',
            icon: Icons.warning_amber_rounded,
            severity: InsightSeverity.warning,
          ),
        );
      }

      if (metrics.hasBudget && forecast.projectedMonthEnd > metrics.budget) {
        insights.add(
          const SmartFinancialInsight(
            title: 'Projected burn rate is above budget',
            message: 'Recurring costs plus daily spend exceed budget forecast.',
            icon: Icons.trending_up_rounded,
            severity: InsightSeverity.danger,
          ),
        );
      }

      return insights.take(3).toList();
    });

double _monthlyEquivalent(
  RecurringExpenseTemplate template, {
  required int daysInMonth,
}) {
  switch (template.frequency) {
    case RecurringFrequency.daily:
      return template.amount * daysInMonth;
    case RecurringFrequency.weekly:
      return template.amount * (daysInMonth / 7);
    case RecurringFrequency.monthly:
      return template.amount;
    case RecurringFrequency.yearly:
      return template.amount / 12;
  }
}
