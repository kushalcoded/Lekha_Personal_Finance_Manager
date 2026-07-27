import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/expense/expense_model.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/cycle/cycle_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../settings/providers/settings_providers.dart';

/// Dashboard state containing summary data
class DashboardState {
  final double totalExpensesThisMonth;
  final double totalReceivables;
  final int totalTransactions;
  final double dailyAverage;
  final bool isLoading;
  final String? error;

  const DashboardState({
    this.totalExpensesThisMonth = 0.0,
    this.totalReceivables = 0.0,
    this.totalTransactions = 0,
    this.dailyAverage = 0.0,
    this.isLoading = false,
    this.error,
  });

  DashboardState copyWith({
    double? totalExpensesThisMonth,
    double? totalReceivables,
    int? totalTransactions,
    double? dailyAverage,
    bool? isLoading,
    String? error,
  }) {
    return DashboardState(
      totalExpensesThisMonth:
          totalExpensesThisMonth ?? this.totalExpensesThisMonth,
      totalReceivables: totalReceivables ?? this.totalReceivables,
      totalTransactions: totalTransactions ?? this.totalTransactions,
      dailyAverage: dailyAverage ?? this.dailyAverage,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Reactive dashboard summary built from live providers.
final dashboardProvider = Provider<DashboardState>((ref) {
  final userId = ref.watch(currentUserIdProvider) ?? '';
  final expensesState = ref.watch(expensesProvider);
  final receivablesState = ref.watch(receivablesProvider);
  final cycleStart = ref.watch(settingsProvider).currentCycleStartDate;

  final expenses = expensesState.expenses;
  final receivables = receivablesState.receivables;
  final now = DateTime.now();
  final thirtyDaysAgo = now.subtract(const Duration(days: 30));

  final currentCycleExpenses = expenses.where(
    (e) =>
        e.userId == userId &&
        !e.date.isBefore(cycleStart) &&
        !e.date.isAfter(now),
  );

  final cycleTotal = currentCycleExpenses.fold<double>(
    0.0,
    (sum, e) => sum + e.amount,
  );

  final unpaidReceivables = receivables
      .where((r) => r.userId == userId && !r.isPaid)
      .fold<double>(0.0, (sum, r) => sum + r.amount);

  final lastThirtyDaysExpenses = expenses.where(
    (e) => e.userId == userId && e.date.isAfter(thirtyDaysAgo),
  );

  final dailyAvg = lastThirtyDaysExpenses.isEmpty
      ? 0.0
      : (lastThirtyDaysExpenses.fold<double>(0.0, (sum, e) => sum + e.amount) /
            30);

  return DashboardState(
    totalExpensesThisMonth: cycleTotal,
    totalReceivables: unpaidReceivables,
    totalTransactions: currentCycleExpenses.length,
    dailyAverage: dailyAvg,
    isLoading: expensesState.isLoading || receivablesState.isLoading,
    error: expensesState.error ?? receivablesState.error,
  );
});

/// Provider for recent expenses on dashboard
final recentExpensesProvider = Provider.family<List<Expense>, String>((
  ref,
  userId,
) {
  return ref
      .watch(cycleExpensesProvider)
      .where((e) => e.userId == userId)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

/// Reactive monthly spend (watches expenses)
final monthlySpendProvider = Provider.family<double, String>((ref, userId) {
  final expenses = ref.watch(expensesProvider).expenses;
  final now = DateTime.now();
  final cycleStart = ref.watch(settingsProvider).currentCycleStartDate;

  final currentCycleExpenses = expenses.where(
    (e) =>
        e.userId == userId &&
        !e.date.isBefore(cycleStart) &&
        !e.date.isAfter(now),
  );

  return currentCycleExpenses.fold<double>(0.0, (sum, e) => sum + e.amount);
});

/// Reactive transaction count (watches expenses)
final transactionCountProvider = Provider.family<int, String>((ref, userId) {
  final expenses = ref.watch(expensesProvider).expenses;
  final now = DateTime.now();
  final cycleStart = ref.watch(settingsProvider).currentCycleStartDate;

  return expenses
      .where(
        (e) =>
            e.userId == userId &&
            !e.date.isBefore(cycleStart) &&
            !e.date.isAfter(now),
      )
      .length;
});

/// Reactive daily average (watches expenses)
final dailyAverageProvider = Provider.family<double, String>((ref, userId) {
  final expenses = ref.watch(expensesProvider).expenses;
  final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

  final lastThirtyDaysExpenses = expenses.where(
    (e) => e.userId == userId && e.date.isAfter(thirtyDaysAgo),
  );

  if (lastThirtyDaysExpenses.isEmpty) return 0.0;

  final total = lastThirtyDaysExpenses.fold<double>(
    0.0,
    (sum, e) => sum + e.amount,
  );
  return total / 30;
});

/// Reactive receivables total (watches receivables)
final receivablesTotalProvider = Provider.family<double, String>((ref, userId) {
  final receivables = ref.watch(receivablesProvider).receivables;
  return receivables
      .where((r) => r.userId == userId)
      .fold<double>(0.0, (sum, r) => sum + r.remaining);
});

/// Provider for spending trend data
final spendingTrendProvider =
    FutureProvider.family<Map<String, double>, String>((ref, userId) async {
      // TODO: Fetch spending trend for chart
      return {};
    });

/// Provider for category breakdown
final categoryBreakdownProvider =
    FutureProvider.family<Map<String, double>, String>((ref, userId) async {
      // TODO: Fetch category breakdown data
      return {};
    });
