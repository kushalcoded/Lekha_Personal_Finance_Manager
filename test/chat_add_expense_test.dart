import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/providers/ai_providers.dart';

/// The confirm card is the only thing between a model's reading of a sentence
/// and a real row in the ledger, so it has to state every field it is about to
/// write — an amount alone would get waved through.
void main() {
  test('states amount, category, note, date and method', () {
    final summary = summarizeAddExpense({
      'action': 'add_expense',
      'amount': 450,
      'category': 'food',
      'note': 'Swiggy',
      'date': '2026-08-17',
      'paymentMethod': 'GPay',
    }, 'Food');

    expect(summary, 'Add ₹450 to Food for Swiggy on 17 Aug via GPay');
  });

  test('leaves out what the model did not say', () {
    final summary = summarizeAddExpense({
      'action': 'add_expense',
      'amount': 90,
    }, null);

    expect(summary, 'Add ₹90');
  });

  test('an unreadable amount still reads as money, not as null', () {
    final summary = summarizeAddExpense({'action': 'add_expense'}, 'Food');

    expect(summary, 'Add ₹0 to Food');
  });

  test('a date the model garbled is dropped rather than guessed', () {
    final summary = summarizeAddExpense({
      'amount': 120,
      'date': 'yesterday',
    }, 'Travel');

    expect(summary, 'Add ₹120 to Travel');
  });
}
