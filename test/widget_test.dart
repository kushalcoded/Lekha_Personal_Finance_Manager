import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/core/navigation/navigation_models.dart';
import 'package:personal_expanse_tracker/models/history/cycle_history_snapshot.dart';
import 'package:personal_expanse_tracker/screens/cycle_history_detail_screen.dart';
import 'package:personal_expanse_tracker/screens/dashboard/widgets/budget_progress_card.dart';

void main() {
  test('bottom navigation is the consolidated 4-tab set', () {
    final ids = navigationItems.map((item) => item.id).toList();
    expect(ids, ['dashboard', 'expenses', 'insights', 'debts']);
    // History and the receivables/payables split are no longer bottom tabs.
    expect(ids.contains('history'), isFalse);
    expect(ids.contains('receivables'), isFalse);
  });

  testWidgets('budget progress card shows salary and savings metrics', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BudgetProgressCard(
            title: 'Cycle Plan',
            spent: 6500,
            budget: 10000,
            salary: 18000,
            accentColor: Colors.blue,
          ),
        ),
      ),
    );

    expect(find.text('Cycle Plan'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Salary - Budget'), findsOneWidget);
    expect(find.text('Salary - Spend'), findsOneWidget);
  });

  testWidgets('cycle history detail screen renders snapshot content', (
    WidgetTester tester,
  ) async {
    final snapshot = CycleHistorySnapshot(
      id: 'cycle_1',
      userId: 'user_1',
      cycleStartDate: DateTime(2026, 6, 1),
      cycleEndDate: DateTime(2026, 6, 30),
      archivedAt: DateTime(2026, 7, 1),
      totalExpenses: 7200,
      cycleBudget: 10000,
      cycleSalary: 18000,
      categoryBreakdown: {'Food': 3200, 'Travel': 4000},
      expenses: [
        CycleHistoryExpenseEntry(
          id: 'expense_1',
          category: 'Food',
          description: 'Groceries',
          amount: 3200,
          date: DateTime(2026, 6, 10),
        ),
        CycleHistoryExpenseEntry(
          id: 'expense_2',
          category: 'Travel',
          description: 'Fuel',
          amount: 4000,
          date: DateTime(2026, 6, 18),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CycleHistoryDetailScreen(snapshot: snapshot),
      ),
    );

    expect(find.text('Cycle Details'), findsOneWidget);
    expect(find.text('Category Breakdown'), findsOneWidget);
    expect(find.text('Cycle Expenses'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Fuel'), findsOneWidget);
  });
}
