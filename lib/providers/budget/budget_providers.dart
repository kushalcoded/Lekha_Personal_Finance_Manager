import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category/category_kinds.dart';
import '../../models/category/expense_category.dart';
import '../../providers/cycle/cycle_providers.dart';
import '../../providers/storage/storage_providers.dart';
import '../../screens/expenses/providers/recurring_expenses_providers.dart';
import '../../screens/settings/providers/settings_providers.dart';
import '../categories/category_providers.dart';
import 'committed_planned.dart';

class MonthlyBudgetState {
  final double amount;

  const MonthlyBudgetState({this.amount = 0.0});

  MonthlyBudgetState copyWith({double? amount}) {
    return MonthlyBudgetState(amount: amount ?? this.amount);
  }
}

final monthlyBudgetProvider = Provider.family<MonthlyBudgetState, String>((
  ref,
  userId,
) {
  final settings = ref.watch(settingsProvider);
  return MonthlyBudgetState(amount: settings.currentCycleBudget);
});

class CycleSalaryState {
  final double amount;

  const CycleSalaryState({this.amount = 0.0});
}

final cycleSalaryProvider = Provider.family<CycleSalaryState, String>((
  ref,
  userId,
) {
  final settings = ref.watch(settingsProvider);
  return CycleSalaryState(amount: settings.currentCycleSalary);
});

class BudgetMetrics {
  final double budget;

  /// Money consumed this cycle: [everydaySpent] + [committedSpent]. Investments
  /// and transfers left the account but were not spent, so they are not here.
  final double spent;
  final double remaining;
  final double percentSpent;
  final double salary;
  final double plannedSavings;
  final double actualSavings;
  final bool hasBudget;
  final bool hasSalary;
  final bool isOverBudget;
  final bool isNearLimit;

  /// The part of spending the user actually chooses week to week.
  final double everydaySpent;

  /// Rent, bills, EMIs — spending, but not a choice.
  final double committedSpent;

  /// Bills of this cycle still to come, from the recurring templates.
  final double committedPlanned;

  /// Paid plus still to pay. What the budget has to hold back for bills.
  final double committedReserved;

  /// Budget minus [committedReserved] — what is genuinely free to spend.
  final double everydayAllowance;

  /// The headline figure on Home: allowance minus everyday spending.
  final double everydayLeft;

  /// Money that left but was not consumed, kept apart so it can be shown
  /// without distorting anything.
  final double invested;
  final double transfers;
  final double income;

  /// Bills alone already exceed the budget — the allowance is zero and saying
  /// "you have X left" would be a lie.
  final bool isOverCommitted;

  /// Everyday spending has passed its allowance, even if the whole budget has
  /// not. Distinct from [isOverBudget], which the reminders fire on.
  final bool isOverAllowance;

  const BudgetMetrics({
    required this.budget,
    required this.spent,
    required this.remaining,
    required this.percentSpent,
    required this.salary,
    required this.plannedSavings,
    required this.actualSavings,
    required this.hasBudget,
    required this.hasSalary,
    required this.isOverBudget,
    required this.isNearLimit,
    this.everydaySpent = 0.0,
    this.committedSpent = 0.0,
    this.committedPlanned = 0.0,
    this.committedReserved = 0.0,
    this.everydayAllowance = 0.0,
    this.everydayLeft = 0.0,
    this.invested = 0.0,
    this.transfers = 0.0,
    this.income = 0.0,
    this.isOverCommitted = false,
    this.isOverAllowance = false,
  });
}

final budgetMetricsProvider = Provider.family<BudgetMetrics, String>((
  ref,
  userId,
) {
  final budget = ref.watch(monthlyBudgetProvider(userId)).amount;
  final salary = ref.watch(cycleSalaryProvider(userId)).amount;
  final kinds = ref.watch(categoryKindsProvider);
  // One definition of "spent this cycle", shared with the dashboard's category
  // bars and the Insights cycle total. This used to stop at DateTime.now(),
  // which meant an expense dated later today was counted by the bars beside it
  // but not by this hero figure — two numbers, same money.
  final mine = ref
      .watch(cycleExpensesProvider)
      .where((expense) => expense.userId == userId);

  final everydaySpent = mine.ofKind(kinds, CategoryKind.everyday).total;
  final committedSpent = mine.ofKind(kinds, CategoryKind.committed).total;
  final invested = mine.ofKind(kinds, CategoryKind.investment).total;
  final transfers = mine.ofKind(kinds, CategoryKind.transfer).total;
  final income = mine.ofKind(kinds, CategoryKind.income).total;
  final spent = everydaySpent + committedSpent;

  final templates = ref.watch(userRecurringTemplatesProvider(userId));
  final planned = committedPlanned(
    activeTemplates: templates,
    kinds: kinds,
    cycleEnd: ref.watch(cycleEndProvider),
  );
  // What actually left this cycle for bills that are being spread. Real
  // spending, but already reserved a share at a time, so the allowance must
  // not be charged the lump a second time.
  final spreadIds = {
    for (final t in templates)
      if (t.isSpread) t.id,
  };
  final spreadPaid = spreadIds.isEmpty
      ? 0.0
      : mine.where((e) => spreadIds.contains(e.recurringTemplateId)).total;
  final split = everydayAllowance(
    budget: budget,
    committedSpent: committedSpent,
    committedPlanned: planned,
    everydaySpent: everydaySpent,
    spreadPaid: spreadPaid,
  );

  final hasBudget = budget > 0;
  final hasSalary = salary > 0;
  final remaining = hasBudget ? budget - spent : 0.0;
  final percentSpent = hasBudget ? spent / budget : 0.0;
  // Real income supersedes the planned salary the moment there is any: a
  // number you entered beats a number you estimated in Settings.
  final earned = income > 0 ? income : salary;

  return BudgetMetrics(
    budget: budget,
    spent: spent,
    remaining: remaining,
    percentSpent: percentSpent,
    salary: salary,
    plannedSavings: hasSalary ? salary - budget : 0.0,
    actualSavings: earned > 0 ? earned - spent : 0.0,
    hasBudget: hasBudget,
    hasSalary: hasSalary,
    everydaySpent: everydaySpent,
    committedSpent: committedSpent,
    committedPlanned: planned,
    committedReserved: split.committedReserved,
    everydayAllowance: split.everydayAllowance,
    everydayLeft: split.everydayLeft,
    invested: invested,
    transfers: transfers,
    income: income,
    isOverCommitted: split.isOverCommitted,
    isOverAllowance: hasBudget && split.everydayLeft < -0.005,
    // A paisa of tolerance. Summing two-decimal amounts leaves float
    // residue, so landing exactly on budget could make remaining a tiny
    // negative — which flipped the bar red and printed "Overspent -₹0".
    isOverBudget: hasBudget && spent > budget + 0.005,
    isNearLimit: hasBudget && spent <= budget + 0.005 && percentSpent >= 0.8,
  );
});

enum InsightSeverity { healthy, info, warning, danger }

class SmartFinancialInsight {
  final String title;
  final String message;
  final IconData icon;
  final InsightSeverity severity;

  const SmartFinancialInsight({
    required this.title,
    required this.message,
    required this.icon,
    required this.severity,
  });
}

class BudgetIntelligence {
  final double monthlyBurnRate;
  final double projectedMonthEndSpend;
  final double weeklyAverage;
  final String? highestSpendingCategory;
  final double highestSpendingCategoryAmount;
  final double savingsEstimate;
  final double overspendingRisk;
  final int budgetHealthScore;
  final List<SmartFinancialInsight> insights;

  const BudgetIntelligence({
    required this.monthlyBurnRate,
    required this.projectedMonthEndSpend,
    required this.weeklyAverage,
    required this.highestSpendingCategory,
    required this.highestSpendingCategoryAmount,
    required this.savingsEstimate,
    required this.overspendingRisk,
    required this.budgetHealthScore,
    required this.insights,
  });
}

final budgetIntelligenceProvider = Provider.family<BudgetIntelligence, String>((
  ref,
  userId,
) {
  final metrics = ref.watch(budgetMetricsProvider(userId));
  final expenses = ref.watch(expensesProvider).expenses;
  final now = DateTime.now();
  final cycleStart = ref.watch(settingsProvider).currentCycleStartDate;
  final daysElapsed = now.difference(cycleStart).inDays + 1;
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  // Spending only: otherwise the top-category line reports "Investment" for
  // anyone running a decent SIP, and the burn rate disagrees with the hero.
  final currentMonthExpenses = expenses
      .where(
        (expense) =>
            expense.userId == userId &&
            !expense.date.isBefore(cycleStart) &&
            !expense.date.isAfter(now),
      )
      .spendable(ref.watch(categoryKindsProvider))
      .toList();
  final monthlyBurnRate = metrics.spent / daysElapsed;
  final projected = monthlyBurnRate * daysInMonth;
  final weeklyAverage = monthlyBurnRate * 7;
  final categoryTotals = <String, double>{};

  for (final expense in currentMonthExpenses) {
    categoryTotals[expense.category] =
        (categoryTotals[expense.category] ?? 0) + expense.amount;
  }

  String? highestCategory;
  double highestAmount = 0.0;
  for (final entry in categoryTotals.entries) {
    if (entry.value > highestAmount) {
      highestCategory = entry.key;
      highestAmount = entry.value;
    }
  }

  final savingsEstimate = metrics.hasBudget ? metrics.budget - projected : 0.0;
  final overspendingRisk = metrics.hasBudget
      ? (projected / metrics.budget).clamp(0.0, 2.0)
      : 0.0;
  final budgetHealthScore = _budgetHealthScore(
    hasBudget: metrics.hasBudget,
    percentSpent: metrics.percentSpent,
    projected: projected,
    budget: metrics.budget,
    daysElapsed: daysElapsed,
    daysInMonth: daysInMonth,
  );
  final insights = _buildInsights(
    metrics: metrics,
    projected: projected,
    weeklyAverage: weeklyAverage,
    highestCategory: highestCategory,
    highestAmount: highestAmount,
    healthScore: budgetHealthScore,
  );

  return BudgetIntelligence(
    monthlyBurnRate: monthlyBurnRate,
    projectedMonthEndSpend: projected,
    weeklyAverage: weeklyAverage,
    highestSpendingCategory: highestCategory,
    highestSpendingCategoryAmount: highestAmount,
    savingsEstimate: savingsEstimate,
    overspendingRisk: overspendingRisk,
    budgetHealthScore: budgetHealthScore,
    insights: insights,
  );
});

int _budgetHealthScore({
  required bool hasBudget,
  required double percentSpent,
  required double projected,
  required double budget,
  required int daysElapsed,
  required int daysInMonth,
}) {
  if (!hasBudget) return 0;
  final expectedProgress = daysElapsed / daysInMonth;
  final projectedRatio = budget <= 0 ? 0.0 : projected / budget;
  var score = 100;

  if (percentSpent > expectedProgress + 0.2) score -= 20;
  if (projectedRatio > 1.0) score -= ((projectedRatio - 1.0) * 80).round();
  if (percentSpent > 1.0) score -= 25;

  return score.clamp(0, 100);
}

List<SmartFinancialInsight> _buildInsights({
  required BudgetMetrics metrics,
  required double projected,
  required double weeklyAverage,
  required String? highestCategory,
  required double highestAmount,
  required int healthScore,
}) {
  final insights = <SmartFinancialInsight>[];

  if (!metrics.hasBudget) {
    insights.add(
      const SmartFinancialInsight(
        title: 'Set a monthly budget',
        message: 'Add a budget to unlock spending risk and savings estimates.',
        icon: Icons.flag_rounded,
        severity: InsightSeverity.info,
      ),
    );
    return insights;
  }

  if (projected > metrics.budget) {
    insights.add(
      const SmartFinancialInsight(
        title: "You're likely to exceed your budget",
        message: 'Projected spending is above your monthly budget.',
        icon: Icons.warning_amber_rounded,
        severity: InsightSeverity.danger,
      ),
    );
  } else if (healthScore >= 75) {
    insights.add(
      const SmartFinancialInsight(
        title: 'Spending is healthy this month',
        message: 'Your current pace is tracking within budget.',
        icon: Icons.check_circle_rounded,
        severity: InsightSeverity.healthy,
      ),
    );
  } else {
    insights.add(
      const SmartFinancialInsight(
        title: 'Spending needs attention',
        message: 'Your current pace is close to the monthly limit.',
        icon: Icons.trending_up_rounded,
        severity: InsightSeverity.warning,
      ),
    );
  }

  if (highestCategory != null && highestAmount > 0) {
    insights.add(
      SmartFinancialInsight(
        title: '$highestCategory is your top category',
        message: 'This category is driving the most spend this month.',
        icon: Icons.category_rounded,
        severity: InsightSeverity.info,
      ),
    );
  }

  if (weeklyAverage > metrics.budget / 4 && metrics.budget > 0) {
    insights.add(
      const SmartFinancialInsight(
        title: 'Weekly spend is running hot',
        message: 'You spent more this week than your budget pace allows.',
        icon: Icons.local_fire_department_rounded,
        severity: InsightSeverity.warning,
      ),
    );
  }

  return insights.take(3).toList();
}
