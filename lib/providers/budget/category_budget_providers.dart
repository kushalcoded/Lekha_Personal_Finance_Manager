import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth/auth_provider.dart';
import '../../providers/cycle/cycle_providers.dart';
import '../../providers/storage/storage_providers.dart';
import '../../screens/expenses/utils/expense_helpers.dart';
import '../../services/storage/hive_service.dart';

/// Per-category spending limits for a cycle — category → amount. A category
/// missing from the map is uncapped, which is the default for all of them.
final categoryBudgetsProvider =
    StateNotifierProvider<CategoryBudgetsNotifier, Map<String, double>>((ref) {
      return CategoryBudgetsNotifier(ref);
    });

class CategoryBudgetsNotifier extends StateNotifier<Map<String, double>> {
  final Ref _ref;

  CategoryBudgetsNotifier(this._ref) : super(const {}) {
    state = _hive.getCategoryBudgets(_userId);
  }

  HiveService get _hive => _ref.read(hiveServiceProvider);
  String get _userId => _ref.read(currentUserIdProvider) ?? localUserId;

  /// Pass 0 (or less) to lift a limit rather than store "no limit" as a number.
  Future<void> setLimit(String category, double amount) async {
    final next = Map<String, double>.from(state);
    if (amount > 0) {
      next[category] = amount;
    } else {
      next.remove(category);
    }
    state = next;
    await _hive.saveCategoryBudgets(_userId, next);
  }

  /// Re-read after a sync pull or a restore replaces the settings map.
  void refresh() => state = _hive.getCategoryBudgets(_userId);
}

/// Spend against limit for one category this cycle. Uncapped categories come
/// back with `isCapped == false`, so callers can render nothing.
final categoryBudgetStatusProvider =
    Provider.family<CategoryBudgetStatus, String>((ref, category) {
      final userId = ref.watch(currentUserIdProvider) ?? localUserId;
      return categoryBudgetStatus(
        category: category,
        budgets: ref.watch(categoryBudgetsProvider),
        cycleExpenses: ref
            .watch(cycleExpensesProvider)
            .where((e) => e.userId == userId)
            .toList(),
      );
    });
