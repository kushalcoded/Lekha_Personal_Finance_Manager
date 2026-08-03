import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/expense_helpers.dart';

Expense expense({String? paymentMethod, String? description}) => Expense(
  id: 'e1',
  userId: 'u1',
  amount: 1090,
  category: 'Friends',
  description: description,
  paymentMethod: paymentMethod,
  date: DateTime(2026, 8, 3),
  createdAt: DateTime(2026, 8, 3),
);

void main() {
  test('the chosen method wins, whatever the note says', () {
    // The reported bug: details said "Not recorded" for an expense whose
    // method was stored, because it only ever read the note.
    expect(
      formatPaymentMethod(expense(paymentMethod: 'GPay', description: 'gift')),
      'GPay',
    );
    expect(
      expensePaymentMethod(
        expense(paymentMethod: 'GPay', description: 'gift'),
      ),
      'GPay',
    );
  });

  test('older records still resolve from the note', () {
    expect(
      formatPaymentMethod(expense(description: 'Lunch via GPay')),
      'GPay',
    );
  });

  test('an empty stored method is treated as absent', () {
    expect(
      formatPaymentMethod(expense(paymentMethod: '   ', description: 'gift')),
      'Not recorded',
    );
  });

  test('says so plainly when neither knows', () {
    expect(formatPaymentMethod(expense(description: 'gift')), 'Not recorded');
    expect(expensePaymentMethod(expense(description: 'gift')), isNull);
  });
}
