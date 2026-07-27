import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/expense/expense_model.dart';
import '../../../providers/categories/category_providers.dart';
import '../../../providers/cycle/cycle_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../models/expense_view_models.dart';

/// Expenses filter and sort state
class ExpensesListState {
  static const Object _noChange = Object();

  final List<String> selectedFilters;
  final DateTimeRange? dateRange;
  final double? minAmount;
  final double? maxAmount;
  final String sortBy; // newest, oldest, highest, lowest
  final String searchQuery;

  const ExpensesListState({
    this.selectedFilters = const [],
    this.dateRange,
    this.minAmount,
    this.maxAmount,
    this.sortBy = 'newest',
    this.searchQuery = '',
  });

  bool get hasActiveFilters {
    return selectedFilters.isNotEmpty ||
        dateRange != null ||
        minAmount != null ||
        maxAmount != null;
  }

  ExpensesListState copyWith({
    List<String>? selectedFilters,
    Object? dateRange = _noChange,
    Object? minAmount = _noChange,
    Object? maxAmount = _noChange,
    String? sortBy,
    String? searchQuery,
  }) {
    return ExpensesListState(
      selectedFilters: selectedFilters ?? this.selectedFilters,
      dateRange: dateRange == _noChange
          ? this.dateRange
          : dateRange as DateTimeRange?,
      minAmount: minAmount == _noChange ? this.minAmount : minAmount as double?,
      maxAmount: maxAmount == _noChange ? this.maxAmount : maxAmount as double?,
      sortBy: sortBy ?? this.sortBy,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// Expenses list provider
final expensesListProvider =
    StateNotifierProvider<ExpensesListNotifier, ExpensesListState>(
      (ref) => ExpensesListNotifier(),
    );

class ExpensesListNotifier extends StateNotifier<ExpensesListState> {
  ExpensesListNotifier() : super(const ExpensesListState());

  /// Filter expenses by category
  void filterByCategory(String category) {
    final filters = List<String>.from(state.selectedFilters);
    if (filters.contains(category)) {
      filters.remove(category);
    } else {
      filters.add(category);
    }
    state = state.copyWith(selectedFilters: filters);
  }

  void setCategories(List<String> categories) {
    state = state.copyWith(selectedFilters: categories);
  }

  /// Clear category filters
  void clearFilters() {
    state = state.copyWith(selectedFilters: const []);
  }

  void clearAllFilters() {
    state = state.copyWith(
      selectedFilters: const [],
      dateRange: null,
      minAmount: null,
      maxAmount: null,
      sortBy: 'newest',
    );
  }

  /// Search expenses by notes or category
  void search(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Sort expenses
  void setSortBy(String sortType) {
    state = state.copyWith(sortBy: sortType);
  }

  void setDateRange(DateTimeRange? range) {
    state = state.copyWith(dateRange: range);
  }

  void setAmountRange(double? minAmount, double? maxAmount) {
    state = state.copyWith(minAmount: minAmount, maxAmount: maxAmount);
  }
}

/// Provider for filtered and sorted expenses
final filteredExpensesProvider = Provider<List<Expense>>((ref) {
  final filterState = ref.watch(expensesListProvider);
  final expenses = ref.watch(cycleExpensesProvider);

  var filtered = List<Expense>.from(expenses);

  if (filterState.searchQuery.isNotEmpty) {
    final query = filterState.searchQuery.toLowerCase();
    filtered = filtered
        .where(
          (expense) =>
              (expense.description ?? '').toLowerCase().contains(query) ||
              expense.category.toLowerCase().contains(query),
        )
        .toList();
  }

  if (filterState.selectedFilters.isNotEmpty) {
    filtered = filtered
        .where(
          (expense) => filterState.selectedFilters.contains(expense.category),
        )
        .toList();
  }

  if (filterState.dateRange != null) {
    final range = filterState.dateRange!;
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );
    filtered = filtered
        .where(
          (expense) =>
              !expense.date.isBefore(start) && !expense.date.isAfter(end),
        )
        .toList();
  }

  if (filterState.minAmount != null) {
    filtered = filtered
        .where((expense) => expense.amount >= filterState.minAmount!)
        .toList();
  }

  if (filterState.maxAmount != null) {
    filtered = filtered
        .where((expense) => expense.amount <= filterState.maxAmount!)
        .toList();
  }

  switch (filterState.sortBy) {
    case 'oldest':
      filtered.sort((a, b) => a.date.compareTo(b.date));
      break;
    case 'highest':
      filtered.sort((a, b) => b.amount.compareTo(a.amount));
      break;
    case 'lowest':
      filtered.sort((a, b) => a.amount.compareTo(b.amount));
      break;
    default:
      filtered.sort((a, b) => b.date.compareTo(a.date));
  }

  return filtered;
});

final groupedExpensesProvider = Provider<List<ExpenseGroup>>((ref) {
  final expenses = ref.watch(filteredExpensesProvider);
  final filterState = ref.watch(expensesListProvider);
  final grouped = <DateTime, List<Expense>>{};

  for (final expense in expenses) {
    final date = DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
    );
    grouped.putIfAbsent(date, () => []).add(expense);
  }

  final entries = grouped.entries.toList()
    ..sort((a, b) {
      if (filterState.sortBy == 'oldest') {
        return a.key.compareTo(b.key);
      }
      return b.key.compareTo(a.key);
    });

  return entries.map((entry) {
    final items = List<Expense>.from(entry.value);
    if (filterState.sortBy == 'highest') {
      items.sort((a, b) => b.amount.compareTo(a.amount));
    } else if (filterState.sortBy == 'lowest') {
      items.sort((a, b) => a.amount.compareTo(b.amount));
    }
    final total = items.fold(0.0, (sum, e) => sum + e.amount);
    return ExpenseGroup(date: entry.key, expenses: items, total: total);
  }).toList();
});

final expenseStatsProvider = Provider<ExpenseStats>((ref) {
  final expenses = ref.watch(filteredExpensesProvider);
  final total = expenses.fold(0.0, (sum, e) => sum + e.amount);
  final count = expenses.length;

  final now = DateTime.now();
  final cycleStart = ref.watch(settingsProvider).currentCycleStartDate;
  final monthly = expenses
      .where(
        (expense) =>
            !expense.date.isBefore(cycleStart) && !expense.date.isAfter(now),
      )
      .fold(0.0, (sum, e) => sum + e.amount);

  final categoryTotals = <String, double>{};
  for (final expense in expenses) {
    categoryTotals[expense.category] =
        (categoryTotals[expense.category] ?? 0.0) + expense.amount;
  }

  String? topCategory;
  double topTotal = 0.0;
  for (final entry in categoryTotals.entries) {
    if (entry.value > topTotal) {
      topCategory = entry.key;
      topTotal = entry.value;
    }
  }

  return ExpenseStats(
    total: total,
    monthly: monthly,
    transactionCount: count,
    topCategory: topCategory,
    topCategoryTotal: topTotal,
  );
});

/// Names of the user's current categories, derived from [categoriesProvider]
/// so the add/edit/filter/export/payable flows all stay in sync.
final expenseCategoriesProvider = Provider<List<String>>((ref) {
  return ref.watch(categoriesProvider).map((c) => c.name).toList();
});

/// Provider for total expenses by category
final expensesByCategoryProvider = Provider<Map<String, double>>((ref) {
  final expenses = ref.watch(filteredExpensesProvider);
  final categoryTotals = <String, double>{};

  for (final expense in expenses) {
    categoryTotals[expense.category] =
        (categoryTotals[expense.category] ?? 0.0) + expense.amount;
  }

  return categoryTotals;
});

/// Provider for total expenses amount
final totalExpensesAmountProvider = Provider<double>((ref) {
  final expenses = ref.watch(filteredExpensesProvider);
  return expenses.fold(0.0, (sum, e) => sum + e.amount);
});
