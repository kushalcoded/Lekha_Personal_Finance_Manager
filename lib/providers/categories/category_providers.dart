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

/// Category names your records still use that are no longer in the list.
///
/// This is the fingerprint of data loss, not of ordinary use: deleting a
/// category reassigns its records to Miscellaneous first, so an intentional
/// delete leaves nothing behind carrying the old name. A name that survives in
/// records while missing from the list can only have disappeared without that
/// migration — which is exactly what the settings-wipe bug did.
///
/// Comparison is case-insensitive and keeps the first spelling seen, so
/// "gifts" on an expense doesn't report "Gifts" as missing.
List<String> missingCategoryNames(
  Iterable<String> configured,
  Iterable<String> used,
) {
  final known = configured
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();

  final missing = <String, String>{};
  for (final raw in used) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if (known.contains(key)) continue;
    missing.putIfAbsent(key, () => name);
  }

  final names = missing.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
}

/// Categories the user's records reference but that no longer exist, so
/// Manage Categories can offer to restore them.
final orphanCategoriesProvider = Provider<List<String>>((ref) {
  final configured = ref.watch(categoriesProvider).map((c) => c.name);
  // Re-runs after a restore, and after any expense edit.
  ref.watch(expensesProvider);
  final hive = ref.read(hiveServiceProvider);
  final userId = ref.watch(currentUserIdProvider) ?? localUserId;

  // The same three record types usageCount consults.
  return missingCategoryNames(configured, [
    ...hive.getAllExpenses(userId).map((e) => e.category),
    ...hive.getAllPayables(userId).map((p) => p.category),
    ...hive.getRecurringTemplates(userId).map((t) => t.category),
  ]);
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
