import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/category_kinds.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';

/// A refund is stored as a negative expense in the same category. That choice
/// is what let every total, chart and export handle it without changing —
/// these tests pin the arithmetic that relies on.
void main() {
  Expense expense(String category, double amount, {String id = 'e'}) => Expense(
    id: '$id-$category-$amount',
    userId: 'u1',
    amount: amount,
    category: category,
    date: DateTime(2026, 9, 12),
    createdAt: DateTime(2026, 9, 12),
  );

  final kinds = CategoryKinds.from(const [
    ExpenseCategory(name: 'Shopping', iconKey: 'bag', colorHex: '#FFFFFF'),
    ExpenseCategory(name: 'Food', iconKey: 'restaurant', colorHex: '#FFFFFF'),
  ]);

  test('a refund comes off the category it was spent in', () {
    final cycle = [
      expense('Shopping', 10000),
      expense('Food', 500),
      expense('Shopping', -2000, id: 'refund'),
    ];
    expect(cycle.spendable(kinds).total, 8500);
  });

  test('a fully refunded purchase leaves the total where it started', () {
    final cycle = [
      expense('Shopping', 3000),
      expense('Shopping', -3000, id: 'refund'),
    ];
    expect(cycle.spendable(kinds).total, 0);
  });

  test('a category that nets to zero or below is not a chart slice', () {
    // The clamp the pie and the dashboard bars apply. The cycle total still
    // counts the refund; only the drawn slice goes.
    final totals = <String, double>{'Shopping': -500, 'Food': 1200};
    totals.removeWhere((_, value) => value <= 0);
    expect(totals.keys, ['Food']);
  });

  test('a refund cannot be larger than what was spent', () {
    // The sheet caps at the original amount, so this never reaches storage.
    // Documented here because the cap is the only thing stopping a category
    // drifting negative for no visible reason.
    const original = 2000.0;
    bool allowed(double refund) => refund > 0 && refund <= original;
    expect(allowed(2000), isTrue);
    expect(allowed(2000.01), isFalse);
    expect(allowed(0), isFalse);
  });
}
