import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../models/category/category_kinds.dart';
import '../../../models/category/expense_category.dart';
import '../../../providers/categories/category_providers.dart';
import '../../../models/expense/expense_model.dart';
import '../../../providers/budget/budget_providers.dart';
import '../../../providers/cycle/cycle_providers.dart';
import '../../../providers/spread/spread_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../services/storage/hive_service.dart';
import '../../expenses/utils/expense_helpers.dart';
import '../models/analytics_models.dart';

/// What span of money the Insights screen is describing. The user picks this
/// once, at the top, and every scoped panel obeys it — the old design hid a
/// 7D/30D/12M selector inside one section's header while it silently drove the
/// summary cards, the pie and the payment panel three sections away.
enum AnalyticsScope {
  /// The salary cycle, matching the dashboard exactly.
  cycle,
  days30,
  months12;

  String get label => switch (this) {
    AnalyticsScope.cycle => 'This cycle',
    AnalyticsScope.days30 => 'Last 30 days',
    AnalyticsScope.months12 => '12M',
  };

  /// Narrow screens can't fit the full labels side by side.
  String get shortLabel => switch (this) {
    AnalyticsScope.cycle => 'Cycle',
    AnalyticsScope.days30 => '30 days',
    AnalyticsScope.months12 => '12M',
  };
}

/// Analytics state
class AnalyticsState {
  final Map<String, double> categoryBreakdown;
  final Map<String, double> monthlyTrend;
  final double totalSpent;
  final double averageDaily;
  final bool isLoading;
  final String? error;

  const AnalyticsState({
    this.categoryBreakdown = const {},
    this.monthlyTrend = const {},
    this.totalSpent = 0.0,
    this.averageDaily = 0.0,
    this.isLoading = false,
    this.error,
  });

  AnalyticsState copyWith({
    Map<String, double>? categoryBreakdown,
    Map<String, double>? monthlyTrend,
    double? totalSpent,
    double? averageDaily,
    bool? isLoading,
    String? error,
  }) {
    return AnalyticsState(
      categoryBreakdown: categoryBreakdown ?? this.categoryBreakdown,
      monthlyTrend: monthlyTrend ?? this.monthlyTrend,
      totalSpent: totalSpent ?? this.totalSpent,
      averageDaily: averageDaily ?? this.averageDaily,
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
}

/// The chosen scope, remembered across launches like the last open tab.
final analyticsScopeProvider =
    StateNotifierProvider<AnalyticsScopeNotifier, AnalyticsScope>(
      (ref) => AnalyticsScopeNotifier(),
    );

class AnalyticsScopeNotifier extends StateNotifier<AnalyticsScope> {
  AnalyticsScopeNotifier() : super(_restore());

  static const _key = 'analyticsScope';

  static AnalyticsScope _restore() {
    try {
      final saved = Hive.box(kLocalPrefsBox).get(_key)?.toString();
      return AnalyticsScope.values.firstWhere(
        (scope) => scope.name == saved,
        orElse: () => AnalyticsScope.cycle,
      );
    } catch (_) {
      return AnalyticsScope.cycle; // box not open (tests, early startup)
    }
  }

  void setScope(AnalyticsScope scope) {
    state = scope;
    try {
      Hive.box(kLocalPrefsBox).put(_key, scope.name);
    } catch (_) {
      // Preference only — losing it costs a tap, not data.
    }
  }
}

/// Cycle-only expenses. Kept for the panels that are cycle-bound whatever the
/// scope says — a budget is defined per cycle, so Budget Health must not drift
/// when you glance at 12M.
final analyticsExpensesProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  final expenses = ref.watch(cycleExpensesProvider);
  return expenses.where((expense) => expense.userId == userId).toList();
});

/// Every expense for this user, ignoring the cycle. The scoped windows that
/// reach back further than the current cycle need this — reading the cycle list
/// is what left the 6-month chart with five permanently empty bars.
final allUserExpensesProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  return ref
      .watch(expensesProvider)
      .expenses
      .where((expense) => expense.userId == userId)
      .toList();
});

/// The expenses the scoped panels describe.
///
/// Every scope is a LOWER BOUND ONLY. An upper bound is what made this screen
/// lie: it used to clamp to the start of today, so anything added today was
/// invisible until tomorrow — the dashboard counted it, Insights didn't, and
/// the two totals disagreed by exactly that amount.
///
/// Everyday spending only — the part of the money the user actually decides
/// about week to week.
///
/// Rent is the largest expense most months, so including bills made it the top
/// category, the biggest slice and the tallest bar every single time, and the
/// screen told you the same thing forever. Bills have their own section now,
/// where the whole division is the point.
///
/// This is the single upstream of the category, summary, trend and
/// payment-method panels: they must filter identically, or the pie percentages
/// stop matching the total printed above them.
final analyticsScopedExpensesProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  return ref
      .watch(analyticsScopedAllProvider(userId))
      .ofKind(ref.watch(categoryKindsProvider), CategoryKind.everyday)
      .toList();
});

/// The same window, every kind included. Only the section that describes the
/// split itself wants this — everything else means "spending" when it says
/// totals.
///
/// Spread payments arrive here already cut into monthly slices, and only here
/// and in the monthly bars: Insights draws them over time, while Home and the
/// budget still count the full payment in the month it was made.
final analyticsScopedAllProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  final scope = ref.watch(analyticsScopeProvider);
  final now = DateTime.now();
  // Expanded before the window is applied, never after. Filtering first would
  // drop a payment made before this cycle whose later slices fall inside it —
  // which is why the cycle scope no longer reads analyticsExpensesProvider.
  final expanded = spreadForCharts(
    ref.watch(allUserExpensesProvider(userId)),
    ref.watch(spreadExpensesProvider),
    now: now,
  );
  final start = scope == AnalyticsScope.cycle
      ? ref.watch(cycleStartProvider)
      : analyticsScopeStart(scope, now);
  return expanded.where((expense) => !expense.date.isBefore(start)).toList();
});

/// How the window's money divides by what it was for.
///
/// The question behind it is "how much of this did I actually choose?" — a
/// cycle that is four-fifths rent reads very differently from one that is
/// four-fifths eating out, and the category pie cannot show that because it
/// ranks categories rather than grouping them.
final analyticsKindStatsProvider = Provider.family<KindSplit, String>((
  ref,
  userId,
) {
  final kinds = ref.watch(categoryKindsProvider);
  final expenses = ref.watch(analyticsScopedAllProvider(userId));
  double of(CategoryKind kind) => expenses.ofKind(kinds, kind).total;
  return KindSplit(
    everyday: of(CategoryKind.everyday),
    committed: of(CategoryKind.committed),
    invested: of(CategoryKind.investment),
    moved: of(CategoryKind.transfer),
    income: of(CategoryKind.income),
  );
});

final analyticsCategoryStatsProvider =
    Provider.family<List<CategoryStat>, String>((ref, userId) {
      final expenses = ref.watch(analyticsScopedExpensesProvider(userId));
      final totals = <String, double>{};
      for (final expense in expenses) {
        totals[expense.category] =
            (totals[expense.category] ?? 0) + expense.amount;
      }
      // A refund is a negative expense, so a category can net out to zero or
      // below. Those are not slices of anything — drop them rather than draw a
      // negative arc. The cycle total above still counts them.
      totals.removeWhere((_, value) => value <= 0);
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
  final expenses = ref.watch(analyticsScopedExpensesProvider(userId));
  final totalSpent = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
  // Days actually elapsed in the scope, not the scope's nominal length: on day
  // 6 of a cycle the average must divide by 6, not by 30.
  final days = ref.watch(analyticsScopeDaysProvider);
  final averageDaily = days > 0 ? totalSpent / days : 0.0;
  final categoryStats = ref.watch(analyticsCategoryStatsProvider(userId));
  final topCategory = categoryStats.isNotEmpty ? categoryStats.first : null;
  return AnalyticsSummary(
    totalSpent: totalSpent,
    averageDaily: averageDaily,
    topCategory: topCategory,
  );
});

/// Six months of real history, deliberately ignoring the scope selector — this
/// is context for whatever else you're looking at. It used to read the cycle
/// list, which meant five of its six bars could only ever be zero.
final analyticsMonthlyTotalsProvider =
    Provider.family<List<MonthlyTotal>, String>((ref, userId) {
      // Everyday too, so the bars compare like with like against the panels
      // above them — and so a rent rise does not flatten every other month.
      final now = DateTime.now();
      // Spread first, so a year's premium is one slice in each bar rather
      // than a single spike in the month it was paid.
      final expenses =
          spreadForCharts(
                ref.watch(allUserExpensesProvider(userId)),
                ref.watch(spreadExpensesProvider),
                now: now,
              )
              .ofKind(ref.watch(categoryKindsProvider), CategoryKind.everyday)
              .toList();
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
  final expenses = ref.watch(analyticsScopedExpensesProvider(userId));
  final scope = ref.watch(analyticsScopeProvider);
  final now = _startOfDay(DateTime.now());

  if (scope == AnalyticsScope.cycle) {
    // Day by day since the cycle began — short enough to read individually.
    final days = ref.watch(analyticsScopeDaysProvider);
    final start = now.subtract(Duration(days: days - 1));
    return List.generate(days, (index) {
      final dayStart = start.add(Duration(days: index));
      final dayEnd = dayStart.add(const Duration(days: 1));
      return TrendPoint(
        date: dayStart,
        total: _sumForRange(expenses, dayStart, dayEnd),
      );
    });
  }

  if (scope == AnalyticsScope.months12) {
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

/// Spend grouped by however it was actually paid.
///
/// Groups by the values present in the data rather than a hardcoded list, so a
/// method the user invented still shows up. Resolution goes through
/// [expensePaymentMethod] like every other surface — the private copy this used
/// to keep skipped its `trim()` guard, so a blank method became its own bucket
/// that counted toward the denominator while never being drawn, quietly
/// shrinking every percentage on screen.
final analyticsPaymentMethodStatsProvider =
    Provider.family<List<PaymentMethodStat>, String>((ref, userId) {
      final expenses = ref.watch(analyticsScopedExpensesProvider(userId));
      final totals = <String, double>{};

      for (final expense in expenses) {
        final method = expensePaymentMethod(expense);
        if (method == null) continue; // genuinely unknown — not a bucket
        totals[method] = (totals[method] ?? 0) + expense.amount;
      }

      final matchedTotal = totals.values.fold(0.0, (sum, value) => sum + value);
      final stats =
          totals.entries
              .map(
                (entry) => PaymentMethodStat(
                  method: entry.key,
                  amount: entry.value,
                  share: matchedTotal > 0 ? entry.value / matchedTotal : 0.0,
                ),
              )
              .toList()
            ..sort((a, b) => b.amount.compareTo(a.amount));
      return stats;
    });

final analyticsBudgetInsightProvider = Provider.family<BudgetInsight, String>((
  ref,
  userId,
) {
  // Everyday only: these figures are compared against the budget, and the
  // budget is the everyday allowance.
  final expenses = ref
      .watch(analyticsExpensesProvider(userId))
      .ofKind(ref.watch(categoryKindsProvider), CategoryKind.everyday)
      .toList();
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

/// The scope a swipe lands on, or the same scope when there is nowhere left
/// to go — which is the signal to hand the gesture on to the tabs.
///
/// Stops at the ends rather than wrapping: coming back round to "this cycle"
/// after 12M would feel like a glitch, not a move.
AnalyticsScope adjacentScope(AnalyticsScope from, {required bool forward}) {
  final order = AnalyticsScope.values;
  final next = order.indexOf(from) + (forward ? 1 : -1);
  if (next < 0 || next >= order.length) return from;
  return order[next];
}

/// First day included by a rolling scope. Cycle scope has no formula — its
/// start comes from settings — so callers handle it separately.
DateTime analyticsScopeStart(AnalyticsScope scope, DateTime now) {
  final today = _startOfDay(now);
  return switch (scope) {
    AnalyticsScope.cycle => today,
    AnalyticsScope.days30 => today.subtract(const Duration(days: 29)),
    AnalyticsScope.months12 => today.subtract(const Duration(days: 364)),
  };
}

/// Days elapsed in the active scope, counting today. Drives Average Daily and
/// the cycle trend chart.
final analyticsScopeDaysProvider = Provider<int>((ref) {
  final scope = ref.watch(analyticsScopeProvider);
  final today = _startOfDay(DateTime.now());
  final start = scope == AnalyticsScope.cycle
      ? _startOfDay(ref.watch(cycleStartProvider))
      : analyticsScopeStart(scope, today);
  // A cycle start in the future (someone reset it forward) would otherwise
  // yield zero or negative days and blow up the average.
  return today.difference(start).inDays + 1 < 1
      ? 1
      : today.difference(start).inDays + 1;
});

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
