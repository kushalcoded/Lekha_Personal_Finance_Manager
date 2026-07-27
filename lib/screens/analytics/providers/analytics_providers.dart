import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/expense/expense_model.dart';
import '../../../providers/budget/budget_providers.dart';
import '../../../providers/cycle/cycle_providers.dart';
import '../models/analytics_models.dart';

/// Analytics state
class AnalyticsState {
  final Map<String, double> categoryBreakdown;
  final Map<String, double> monthlyTrend;
  final double totalSpent;
  final double averageDaily;
  final String selectedPeriod; // 'week', 'month', 'year'
  final bool isLoading;
  final String? error;

  const AnalyticsState({
    this.categoryBreakdown = const {},
    this.monthlyTrend = const {},
    this.totalSpent = 0.0,
    this.averageDaily = 0.0,
    this.selectedPeriod = 'month',
    this.isLoading = false,
    this.error,
  });

  AnalyticsState copyWith({
    Map<String, double>? categoryBreakdown,
    Map<String, double>? monthlyTrend,
    double? totalSpent,
    double? averageDaily,
    String? selectedPeriod,
    bool? isLoading,
    String? error,
  }) {
    return AnalyticsState(
      categoryBreakdown: categoryBreakdown ?? this.categoryBreakdown,
      monthlyTrend: monthlyTrend ?? this.monthlyTrend,
      totalSpent: totalSpent ?? this.totalSpent,
      averageDaily: averageDaily ?? this.averageDaily,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Analytics provider
final analyticsProvider =
    StateNotifierProvider<AnalyticsNotifier, AnalyticsState>(
      (ref) => AnalyticsNotifier(),
    );

class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  AnalyticsNotifier() : super(const AnalyticsState());

  /// Fetch analytics data
  Future<void> fetchAnalytics(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      // TODO: Fetch analytics data based on period
      await Future.delayed(const Duration(milliseconds: 500));
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Change period
  void setPeriod(String period) {
    state = state.copyWith(selectedPeriod: period);
  }
}

final analyticsPeriodProvider = Provider<String>((ref) {
  return ref.watch(analyticsProvider).selectedPeriod;
});

final analyticsExpensesProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(cycleExpensesProvider);
  return expenses.where((expense) => expense.userId == userId).toList();
});

final analyticsPeriodExpensesProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(analyticsExpensesProvider(userId));
  final period = ref.watch(analyticsPeriodProvider);
  final now = _startOfDay(DateTime.now());
  final start = _startOfDay(_periodStart(now, period));
  return expenses
      .where(
        (expense) =>
            !expense.date.isBefore(start) && !expense.date.isAfter(now),
      )
      .toList();
});

final analyticsCategoryStatsProvider =
    Provider.family<List<CategoryStat>, String>((ref, userId) {
      final expenses = ref.watch(analyticsPeriodExpensesProvider(userId));
      final totals = <String, double>{};
      for (final expense in expenses) {
        totals[expense.category] =
            (totals[expense.category] ?? 0) + expense.amount;
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

final analyticsSummaryProvider = Provider.family<AnalyticsSummary, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(analyticsPeriodExpensesProvider(userId));
  final totalSpent = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
  final period = ref.watch(analyticsPeriodProvider);
  final now = _startOfDay(DateTime.now());
  final start = _startOfDay(_periodStart(now, period));
  final days = now.difference(start).inDays + 1;
  final averageDaily = days > 0 ? totalSpent / days : 0.0;
  final categoryStats = ref.watch(analyticsCategoryStatsProvider(userId));
  final topCategory = categoryStats.isNotEmpty ? categoryStats.first : null;
  return AnalyticsSummary(
    totalSpent: totalSpent,
    averageDaily: averageDaily,
    topCategory: topCategory,
  );
});

final analyticsMonthlyTotalsProvider =
    Provider.family<List<MonthlyTotal>, String>((ref, userId) {
      final expenses = ref.watch(analyticsExpensesProvider(userId));
      final now = DateTime.now();
      final anchor = DateTime(now.year, now.month, 1);
      final months = List.generate(6, (index) {
        return _shiftMonth(anchor, index - 5);
      });

      return months.map((monthStart) {
        final monthEnd = _shiftMonth(monthStart, 1);
        final total = _sumForRange(expenses, monthStart, monthEnd);
        return MonthlyTotal(month: monthStart, total: total);
      }).toList();
    });

final analyticsTrendProvider = Provider.family<List<TrendPoint>, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(analyticsPeriodExpensesProvider(userId));
  final period = ref.watch(analyticsPeriodProvider);
  final now = _startOfDay(DateTime.now());

  if (period == 'week') {
    final start = now.subtract(const Duration(days: 6));
    return List.generate(7, (index) {
      final dayStart = start.add(Duration(days: index));
      final dayEnd = dayStart.add(const Duration(days: 1));
      return TrendPoint(
        date: dayStart,
        total: _sumForRange(expenses, dayStart, dayEnd),
      );
    });
  }

  if (period == 'year') {
    final anchor = DateTime(now.year, now.month, 1);
    return List.generate(12, (index) {
      final monthStart = _shiftMonth(anchor, index - 11);
      final monthEnd = _shiftMonth(monthStart, 1);
      return TrendPoint(
        date: monthStart,
        total: _sumForRange(expenses, monthStart, monthEnd),
      );
    });
  }

  final start = now.subtract(const Duration(days: 34));
  return List.generate(5, (index) {
    final weekStart = start.add(Duration(days: index * 7));
    final weekEnd = weekStart.add(const Duration(days: 7));
    return TrendPoint(
      date: weekStart,
      total: _sumForRange(expenses, weekStart, weekEnd),
    );
  });
});

final analyticsPaymentMethodStatsProvider =
    Provider.family<List<PaymentMethodStat>, String>((ref, userId) {
      final expenses = ref.watch(analyticsPeriodExpensesProvider(userId));
      const methods = [
        'GPay',
        'PhonePe',
        'Paytm',
        'Cash',
        'Card',
        'Bank Transfer',
      ];
      final totals = {for (final method in methods) method: 0.0};

      for (final expense in expenses) {
        final method =
            expense.paymentMethod ?? _inferPaymentMethod(expense.description);
        if (method != null) {
          totals[method] = (totals[method] ?? 0) + expense.amount;
        }
      }

      final matchedTotal = totals.values.fold(0.0, (sum, value) => sum + value);
      return methods
          .map(
            (method) => PaymentMethodStat(
              method: method,
              amount: totals[method] ?? 0.0,
              share: matchedTotal > 0
                  ? (totals[method] ?? 0.0) / matchedTotal
                  : 0.0,
            ),
          )
          .toList();
    });

final analyticsBudgetInsightProvider = Provider.family<BudgetInsight, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(analyticsExpensesProvider(userId));
  final budgetMetrics = ref.watch(budgetMetricsProvider(userId));
  final budgetIntelligence = ref.watch(budgetIntelligenceProvider(userId));
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final monthEnd = DateTime(now.year, now.month + 1, 1);
  final currentMonthTotal = _sumForRange(expenses, monthStart, monthEnd);

  double baselineTotal = 0.0;
  int baselineCount = 0;
  for (var i = 1; i <= 3; i++) {
    final start = _shiftMonth(monthStart, -i);
    final end = _shiftMonth(start, 1);
    final total = _sumForRange(expenses, start, end);
    if (total > 0) {
      baselineTotal += total;
      baselineCount += 1;
    }
  }
  final baseline = baselineCount > 0 ? baselineTotal / baselineCount : 0.0;

  final daysElapsed = now.day;
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final projected = daysElapsed > 0
      ? (currentMonthTotal / daysElapsed) * daysInMonth
      : currentMonthTotal;

  return BudgetInsight(
    baseline: baseline,
    budget: budgetMetrics.budget,
    current: currentMonthTotal,
    projected: budgetIntelligence.projectedMonthEndSpend > 0
        ? budgetIntelligence.projectedMonthEndSpend
        : projected,
    remaining: budgetMetrics.remaining,
    healthScore: budgetIntelligence.budgetHealthScore,
  );
});

/// Top spending categories
final topCategoriesProvider = Provider<List<MapEntry<String, double>>>((ref) {
  final breakdown = ref.watch(analyticsProvider).categoryBreakdown;
  final sorted = breakdown.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(5).toList();
});

/// Year over year comparison
final yoyComparisonProvider =
    FutureProvider.family<Map<String, double>, String>((ref, userId) async {
      // TODO: Fetch YoY data
      return {};
    });

/// Budget vs actual
final budgetVsActualProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
      // TODO: Fetch budget vs actual data
      return {};
    });

DateTime _startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime _periodStart(DateTime now, String period) {
  switch (period) {
    case 'week':
      return now.subtract(const Duration(days: 6));
    case 'year':
      return now.subtract(const Duration(days: 364));
    default:
      return now.subtract(const Duration(days: 29));
  }
}

DateTime _shiftMonth(DateTime date, int months) {
  return DateTime(date.year, date.month + months, 1);
}

double _sumForRange(List<Expense> expenses, DateTime start, DateTime end) {
  return expenses
      .where(
        (expense) =>
            !expense.date.isBefore(start) && expense.date.isBefore(end),
      )
      .fold(0.0, (sum, expense) => sum + expense.amount);
}

String? _inferPaymentMethod(String? description) {
  if (description == null || description.trim().isEmpty) {
    return null;
  }
  final text = description.toLowerCase();
  if (text.contains('gpay')) {
    return 'GPay';
  }
  if (text.contains('phonepe')) {
    return 'PhonePe';
  }
  if (text.contains('paytm')) {
    return 'Paytm';
  }
  if (text.contains('bank') || text.contains('transfer')) {
    return 'Bank Transfer';
  }
  if (text.contains('card')) {
    return 'Card';
  }
  if (text.contains('cash')) {
    return 'Cash';
  }
  return null;
}
