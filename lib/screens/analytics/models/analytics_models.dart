class CategoryStat {
  final String category;
  final double amount;
  final double percent;

  const CategoryStat({
    required this.category,
    required this.amount,
    required this.percent,
  });
}

class MonthlyTotal {
  final DateTime month;
  final double total;

  const MonthlyTotal({required this.month, required this.total});
}

class TrendPoint {
  final DateTime date;
  final double total;

  const TrendPoint({required this.date, required this.total});
}

class PaymentMethodStat {
  final String method;
  final double amount;
  final double share;

  const PaymentMethodStat({
    required this.method,
    required this.amount,
    required this.share,
  });
}

class BudgetInsight {
  final double baseline;
  final double budget;
  final double current;
  final double projected;
  final double remaining;
  final int healthScore;

  const BudgetInsight({
    required this.baseline,
    this.budget = 0,
    required this.current,
    required this.projected,
    this.remaining = 0,
    this.healthScore = 0,
  });

  double get progress {
    final target = budget > 0 ? budget : baseline;
    if (target <= 0) {
      return 0;
    }
    final value = current / target;
    return value.clamp(0.0, 1.2);
  }
}

class AnalyticsSummary {
  final double totalSpent;
  final double averageDaily;
  final CategoryStat? topCategory;

  const AnalyticsSummary({
    required this.totalSpent,
    required this.averageDaily,
    required this.topCategory,
  });
}

class RecurringObligationSummary {
  final double monthlyTotal;
  final double annualTotal;
  final double averageDaily;
  final int templateCount;
  final double upcomingTotal;
  final int upcomingCount;

  const RecurringObligationSummary({
    required this.monthlyTotal,
    required this.annualTotal,
    required this.averageDaily,
    required this.templateCount,
    required this.upcomingTotal,
    required this.upcomingCount,
  });
}

class BurnRateForecast {
  final double actualDaily;
  final double recurringDaily;
  final double projectedMonthEnd;
  final double budget;
  final double remainingBudget;

  const BurnRateForecast({
    required this.actualDaily,
    required this.recurringDaily,
    required this.projectedMonthEnd,
    required this.budget,
    required this.remainingBudget,
  });
}
