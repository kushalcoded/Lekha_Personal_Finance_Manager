import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/expense_helpers.dart';

Expense _expense({
  required String category,
  required double amount,
  required DateTime date,
}) {
  return Expense(
    id: '$category-$amount-${date.millisecondsSinceEpoch}',
    userId: 'u',
    amount: amount,
    category: category,
    date: date,
    createdAt: date,
  );
}

void main() {
  group('Feature 5: detectExpenseWarning', () {
    final today = DateTime(2026, 7, 15);

    test('flags same-day same-amount same-category as duplicate', () {
      final warning = detectExpenseWarning(
        amount: 200,
        category: 'Food',
        date: today,
        cycleExpenses: [_expense(category: 'Food', amount: 200, date: today)],
      );
      expect(warning.kind, ExpenseWarningKind.duplicate);
    });

    test('flags an amount far above the category median as anomaly', () {
      final warning = detectExpenseWarning(
        amount: 1000,
        category: 'Food',
        date: today,
        cycleExpenses: [
          _expense(category: 'Food', amount: 100, date: today),
          _expense(category: 'Food', amount: 120, date: today),
          _expense(category: 'Food', amount: 110, date: today),
        ],
      );
      expect(warning.kind, ExpenseWarningKind.anomaly);
      expect(warning.typical, 110);
    });

    test('no warning for a normal amount with too little history', () {
      final warning = detectExpenseWarning(
        amount: 130,
        category: 'Food',
        date: today,
        cycleExpenses: [_expense(category: 'Food', amount: 100, date: today)],
      );
      expect(warning.kind, ExpenseWarningKind.none);
    });
  });

  group('Feature 7: chat action JSON parsing', () {
    // Mirrors AiChatNotifier._tryParseAction: whole reply must be an object
    // with an "action" key; prose must not be misread as an action.
    Map<String, dynamic>? tryParseAction(String reply) {
      final trimmed = reply.trim();
      if (!trimmed.startsWith('{')) return null;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> && decoded['action'] is String) {
          return decoded;
        }
      } catch (_) {}
      return null;
    }

    test('parses a valid action object', () {
      final action = tryParseAction('{"action":"set_budget","amount":5000}');
      expect(action?['action'], 'set_budget');
      expect((action?['amount'] as num).toDouble(), 5000);
    });

    test('treats plain prose as not-an-action', () {
      expect(tryParseAction('You spent 5000 this cycle.'), isNull);
      expect(tryParseAction('{ not json'), isNull);
      expect(tryParseAction('{"note":"no action key"}'), isNull);
    });
  });
}
