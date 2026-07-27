import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/category_styles.dart';
import '../../models/category/expense_category.dart';
import '../../services/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../storage/storage_providers.dart';

/// Single source of truth for the user's expense categories.
///
/// Loads from Hive (seeding the defaults on first run), keeps the
/// [CategoryStyles] overlay in sync so every render site reflects changes,
/// and migrates existing records when a category is renamed or deleted.
final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, List<ExpenseCategory>>((ref) {
      return CategoriesNotifier(ref);
    });

class CategoriesNotifier extends StateNotifier<List<ExpenseCategory>> {
  final Ref _ref;

  CategoriesNotifier(this._ref) : super(const []) {
    _load();
  }

  HiveService get _hive => _ref.read(hiveServiceProvider);
  String get _userId => _ref.read(currentUserIdProvider) ?? localUserId;

  void _load() {
    var categories = _hive.getCustomCategories(_userId);
    if (categories.isEmpty) {
      categories = List.of(defaultExpenseCategories);
      _hive.saveCustomCategories(_userId, categories);
    }
    _apply(categories);
  }

  void _apply(List<ExpenseCategory> categories) {
    CategoryStyles.applyCustom(categories);
    state = categories;
  }

  Future<void> _persist(List<ExpenseCategory> categories) async {
    await _hive.saveCustomCategories(_userId, categories);
    _apply(categories);
  }

  bool exists(String name) {
    final target = name.trim().toLowerCase();
    return state.any((c) => c.name.toLowerCase() == target);
  }

  Future<void> addCategory({
    required String name,
    required String iconKey,
    required String colorHex,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || exists(trimmed)) return;
    await _persist([
      ...state,
      ExpenseCategory(name: trimmed, iconKey: iconKey, colorHex: colorHex),
    ]);
  }

  Future<void> updateStyle(
    String name, {
    required String iconKey,
    required String colorHex,
  }) async {
    final next = [
      for (final c in state)
        if (c.name == name)
          c.copyWith(iconKey: iconKey, colorHex: colorHex)
        else
          c,
    ];
    await _persist(next);
  }

  Future<void> renameCategory(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || oldName == kProtectedCategoryName) return;
    if (trimmed.toLowerCase() != oldName.toLowerCase() && exists(trimmed)) {
      return;
    }
    final next = [
      for (final c in state)
        if (c.name == oldName) c.copyWith(name: trimmed) else c,
    ];
    await _persist(next);
    await _migrateCategory(from: oldName, to: trimmed);
  }

  /// Number of records that would be reassigned if [name] is deleted.
  int usageCount(String name) {
    final userId = _userId;
    final expenses = _hive
        .getAllExpenses(userId)
        .where((e) => e.category == name)
        .length;
    final payables = _hive
        .getAllPayables(userId)
        .where((p) => p.category == name)
        .length;
    final recurring = _hive
        .getRecurringTemplates(userId)
        .where((t) => t.category == name)
        .length;
    return expenses + payables + recurring;
  }

  Future<void> deleteCategory(String name) async {
    if (name == kProtectedCategoryName) return;
    final next = state.where((c) => c.name != name).toList();
    await _persist(next);
    await _migrateCategory(from: name, to: kProtectedCategoryName);
  }

  /// Re-point every stored expense, payable, and recurring template from the
  /// [from] category string to [to], then refresh the in-memory providers so
  /// the UI updates. History snapshots are intentionally left frozen.
  Future<void> _migrateCategory({
    required String from,
    required String to,
  }) async {
    if (from == to) return;
    final userId = _userId;
    final now = DateTime.now();

    for (final expense in _hive.getAllExpenses(userId)) {
      if (expense.category != from) continue;
      await _hive.updateExpense(
        expense.id,
        expense.copyWith(category: to, updatedAt: now),
      );
    }
    for (final payable in _hive.getAllPayables(userId)) {
      if (payable.category != from) continue;
      await _hive.updatePayable(
        payable.id,
        payable.copyWith(category: to, updatedAt: now),
      );
    }
    for (final template in _hive.getRecurringTemplates(userId)) {
      if (template.category != from) continue;
      await _hive.updateRecurringTemplate(
        template.id,
        template.copyWith(category: to, updatedAt: now),
      );
    }

    _ref.read(expensesProvider.notifier).refresh(userId);
    _ref.read(payablesProvider.notifier).fetchPayables(userId);
    _ref.read(recurringTemplatesProvider.notifier).fetchTemplates(userId);
  }
}
