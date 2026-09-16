import '../expense/expense_model.dart';
import 'expense_category.dart';

/// What each category name means, and the filters every total uses to ask
/// "is this money I actually spent?".
///
/// Lookup is by name because a name is all an [Expense] carries. A name nobody
/// recognises resolves to [CategoryKind.everyday] on purpose: a category can be
/// deleted out from under its expenses (the case `orphanCategoriesProvider`
/// exists to detect), and those expenses must keep counting rather than quietly
/// drop out of the budget.
class CategoryKinds {
  final Map<String, CategoryKind> _byName;

  const CategoryKinds._(this._byName);

  /// Nothing configured — first run, before the defaults are seeded.
  static const empty = CategoryKinds._({});

  factory CategoryKinds.from(Iterable<ExpenseCategory> categories) {
    return CategoryKinds._({
      for (final category in categories) _key(category.name): category.kind,
    });
  }

  /// Names are matched the way the rest of the app matches them — trimmed and
  /// case-insensitively, as `CategoriesNotifier.exists` does.
  static String _key(String name) => name.trim().toLowerCase();

  CategoryKind of(String category) =>
      _byName[_key(category)] ?? CategoryKind.everyday;

  bool spends(String category) => of(category).countsAsSpent;
}

extension ExpenseKindFilters on Iterable<Expense> {
  /// Money consumed: everyday plus committed. This is what every spending
  /// total, average and chart means by "spent".
  Iterable<Expense> spendable(CategoryKinds kinds) =>
      where((expense) => kinds.spends(expense.category));

  Iterable<Expense> ofKind(CategoryKinds kinds, CategoryKind kind) =>
      where((expense) => kinds.of(expense.category) == kind);

  double get total => fold(0.0, (sum, expense) => sum + expense.amount);
}
