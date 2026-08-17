import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/expense_helpers.dart';

/// A budget warning fires on money the user is about to spend, so the
/// arithmetic has to be exact at the boundary and silent for uncapped
/// categories — a nag on every expense would be worse than no budget at all.
void main() {
  final day = DateTime(2026, 8, 10);

  Expense expense(String category, double amount, {int dayOfMonth = 10}) =>
      Expense(
        id: '$category-$amount-$dayOfMonth',
        userId: 'u1',
        amount: amount,
        category: category,
        date: DateTime(2026, 8, dayOfMonth),
        createdAt: DateTime(2026, 8, dayOfMonth),
      );

  group('categoryBudgetStatus', () {
    test('adds up only the category asked about', () {
      final status = categoryBudgetStatus(
        category: 'Food',
        budgets: {'Food': 3000},
        cycleExpenses: [
          expense('Food', 800),
          expense('Travel', 2000),
          expense('Food', 400, dayOfMonth: 11),
        ],
      );

      expect(status.spent, 1200);
      expect(status.limit, 3000);
      expect(status.remaining, 1800);
      expect(status.isOver, isFalse);
    });

    test('an uncapped category reports no limit, whatever was spent', () {
      final status = categoryBudgetStatus(
        category: 'Travel',
        budgets: {'Food': 3000},
        cycleExpenses: [expense('Travel', 9000)],
      );

      expect(status.isCapped, isFalse);
      expect(status.spent, 9000);
    });

    test('the bar stops at full rather than running off the card', () {
      final status = categoryBudgetStatus(
        category: 'Food',
        budgets: {'Food': 1000},
        cycleExpenses: [expense('Food', 4000)],
      );

      expect(status.isOver, isTrue);
      expect(status.fraction, 1.0);
      expect(status.remaining, -3000);
    });
  });

  group('detectExpenseWarning over budget', () {
    test('warns when this expense is what crosses the line', () {
      final warning = detectExpenseWarning(
        amount: 500,
        category: 'Food',
        date: day,
        cycleExpenses: [expense('Food', 2600)],
        categoryBudgets: {'Food': 3000},
      );

      expect(warning.kind, ExpenseWarningKind.overBudget);
      expect(warning.spentAfter, 3100);
      expect(warning.budget, 3000);
    });

    test('spending exactly to the limit is not over it', () {
      final warning = detectExpenseWarning(
        amount: 400,
        category: 'Food',
        date: day,
        cycleExpenses: [expense('Food', 2600)],
        categoryBudgets: {'Food': 3000},
      );

      expect(warning.kind, ExpenseWarningKind.none);
    });

    test('says nothing for a category with no limit', () {
      final warning = detectExpenseWarning(
        amount: 50000,
        category: 'Travel',
        date: day,
        cycleExpenses: [expense('Travel', 100)],
        categoryBudgets: {'Food': 3000},
      );

      expect(warning.kind, ExpenseWarningKind.none);
    });

    // A mistyped amount and a duplicate are mistakes; being over a limit you
    // set on purpose is not. Report the mistake first.
    test('a duplicate is reported ahead of the budget', () {
      final warning = detectExpenseWarning(
        amount: 2600,
        category: 'Food',
        date: day,
        cycleExpenses: [expense('Food', 2600)],
        categoryBudgets: {'Food': 3000},
      );

      expect(warning.kind, ExpenseWarningKind.duplicate);
    });

    test('an unusually high amount is reported ahead of the budget', () {
      final warning = detectExpenseWarning(
        amount: 9000,
        category: 'Food',
        date: day,
        cycleExpenses: [
          expense('Food', 100),
          expense('Food', 200, dayOfMonth: 11),
          expense('Food', 300, dayOfMonth: 12),
        ],
        categoryBudgets: {'Food': 500},
      );

      expect(warning.kind, ExpenseWarningKind.anomaly);
    });
  });
}
