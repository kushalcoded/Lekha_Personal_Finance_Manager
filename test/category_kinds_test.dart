import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/category_kinds.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';

/// Every spending total in the app now asks this one question: did the money
/// get consumed, or did it merely move? Getting the fallback wrong is the
/// dangerous case — money quietly leaving the budget is far worse than money
/// counted twice, because nothing on screen looks broken.
void main() {
  Expense expense(String category, double amount) => Expense(
    id: '$category-$amount',
    userId: 'u1',
    amount: amount,
    category: category,
    date: DateTime(2026, 9, 10),
    createdAt: DateTime(2026, 9, 10),
  );

  ExpenseCategory category(String name, CategoryKind kind) =>
      ExpenseCategory(name: name, iconKey: 'category', colorHex: '#FFFFFF', kind: kind);

  final kinds = CategoryKinds.from([
    category('Food', CategoryKind.everyday),
    category('Rent', CategoryKind.committed),
    category('Investment', CategoryKind.investment),
    category('Card bill', CategoryKind.transfer),
    category('Salary', CategoryKind.income),
  ]);

  group('of', () {
    test('a category nobody configured still counts as spending', () {
      // Deleting a category reassigns its records, but the settings-wipe bug
      // left names behind with no category. Those expenses must keep counting
      // rather than silently drop out of the budget.
      expect(kinds.of('Something Deleted'), CategoryKind.everyday);
      expect(kinds.spends('Something Deleted'), isTrue);
    });

    test('matches the way the rest of the app matches names', () {
      expect(kinds.of('  rent '), CategoryKind.committed);
      expect(kinds.of('INVESTMENT'), CategoryKind.investment);
    });

    test('nothing configured at all is all everyday', () {
      expect(CategoryKinds.empty.of('Food'), CategoryKind.everyday);
      expect(CategoryKinds.empty.spends('Anything'), isTrue);
    });
  });

  group('spendable', () {
    final all = [
      expense('Food', 500),
      expense('Rent', 18000),
      expense('Investment', 20000),
      expense('Card bill', 12000),
      expense('Salary', 52000),
    ];

    test('keeps everyday and committed, drops the rest', () {
      expect(all.spendable(kinds).total, 18500);
    });

    test('each non-spending kind is still reachable on its own', () {
      expect(all.ofKind(kinds, CategoryKind.investment).total, 20000);
      expect(all.ofKind(kinds, CategoryKind.transfer).total, 12000);
      expect(all.ofKind(kinds, CategoryKind.income).total, 52000);
    });

    test('an empty cycle totals zero rather than throwing', () {
      expect(<Expense>[].spendable(kinds).total, 0);
    });
  });
}
