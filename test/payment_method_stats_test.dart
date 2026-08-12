import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/providers/payment/payment_method_providers.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/expense_helpers.dart';

Expense expense(double amount, {String? method, String? note}) => Expense(
  id: '$amount-$method-$note',
  userId: 'u1',
  amount: amount,
  category: 'Food',
  description: note,
  paymentMethod: method,
  date: DateTime(2026, 8, 10),
  createdAt: DateTime(2026, 8, 10),
);

/// Mirrors the grouping in analyticsPaymentMethodStatsProvider.
Map<String, double> methodTotals(List<Expense> expenses) {
  final totals = <String, double>{};
  for (final e in expenses) {
    final method = expensePaymentMethod(e);
    if (method == null) continue;
    totals[method] = (totals[method] ?? 0) + e.amount;
  }
  return totals;
}

void main() {
  test('a blank stored method does not become its own bucket', () {
    // The analytics copy of the resolver skipped the trim() guard, so '  '
    // counted toward the denominator while never being drawn — every
    // percentage on screen came out smaller than the truth.
    final totals = methodTotals([
      expense(100, method: 'GPay'),
      expense(50, method: '   '),
    ]);
    expect(totals.keys, ['GPay']);
    expect(totals['GPay'], 100);
  });

  test('a method the user invented still appears', () {
    // Grouping used to be a hardcoded six, so a custom method was invisible.
    final totals = methodTotals([
      expense(70, method: 'Amex'),
      expense(30, method: 'GPay'),
    ]);
    expect(totals['Amex'], 70);
  });

  test('an old expense falls back to what the note implies', () {
    final totals = methodTotals([expense(40, note: 'Lunch via GPay')]);
    expect(totals['GPay'], 40);
  });

  test('a genuinely unknown method is skipped, not bucketed as empty', () {
    final totals = methodTotals([expense(25, note: 'lunch')]);
    expect(totals, isEmpty);
  });

  group('auto payment method', () {
    test('the default wins over sniffing the SMS body', () {
      // Inference reads the sender name, so "HDFC Bank" made every card spend
      // look like a bank transfer.
      expect(resolveAutoPaymentMethod('Card', 'Bank Transfer'), 'Card');
    });

    test('inference is the fallback when no default is set', () {
      expect(resolveAutoPaymentMethod(null, 'GPay'), 'GPay');
      expect(resolveAutoPaymentMethod('   ', 'GPay'), 'GPay');
    });

    test('null when neither knows', () {
      expect(resolveAutoPaymentMethod(null, null), isNull);
    });
  });

  group('editing keeps a deleted method visible', () {
    test('the expense\'s own method is added back to the picker', () {
      // Otherwise opening an old expense silently retags it with whatever
      // happened to be selected instead.
      final methods = methodsIncluding(const ['Cash', 'GPay'], 'Amex');
      expect(methods, contains('Amex'));
    });

    test('no duplicate when it is already offered', () {
      final methods = methodsIncluding(const ['Cash', 'GPay'], 'gpay');
      expect(methods.length, 2);
    });

    test('a record with no method leaves the list alone', () {
      expect(methodsIncluding(const ['Cash'], null), ['Cash']);
      expect(methodsIncluding(const ['Cash'], '  '), ['Cash']);
    });
  });
}
