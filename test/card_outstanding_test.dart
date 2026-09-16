import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/category_kinds.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/providers/payment/card_providers.dart';

/// A card balance needs no new storage: purchases add, bill payments subtract,
/// and a bill payment is just a transfer-kind expense on the same card. These
/// tests pin the arithmetic and the two things that would quietly break it.
void main() {
  Expense expense(
    String category,
    double amount, {
    String? method,
    String? note,
    DateTime? date,
  }) => Expense(
    id: '$category-$amount-${date ?? ''}-$method',
    userId: 'u1',
    amount: amount,
    category: category,
    description: note,
    paymentMethod: method,
    date: date ?? DateTime(2026, 9, 12),
    createdAt: date ?? DateTime(2026, 9, 12),
  );

  final kinds = CategoryKinds.from(const [
    ExpenseCategory(name: 'Food', iconKey: 'restaurant', colorHex: '#FFFFFF'),
    ExpenseCategory(
      name: 'Card bill',
      iconKey: 'credit_card',
      colorHex: '#FFFFFF',
      kind: CategoryKind.transfer,
    ),
    ExpenseCategory(
      name: 'Investment',
      iconKey: 'trending_up',
      colorHex: '#FFFFFF',
      kind: CategoryKind.investment,
    ),
  ]);

  group('cardOutstanding', () {
    test('a partial payment leaves the rest owed', () {
      final all = [
        expense('Food', 10000, method: 'HDFC'),
        expense('Card bill', 4000, method: 'HDFC'),
      ];
      expect(cardOutstanding(all, 'HDFC', kinds), 6000);
    });

    test('paying it off in full leaves nothing', () {
      final all = [
        expense('Food', 7500, method: 'HDFC'),
        expense('Card bill', 7500, method: 'HDFC'),
      ];
      expect(cardOutstanding(all, 'HDFC', kinds), 0);
    });

    test('over-paying goes negative rather than hiding it', () {
      // Someone who starts the app already owing money computes from zero, so
      // their first real bill payment overshoots. Clamping at zero would hide
      // a number that is simply wrong; showing it invites the fix.
      final all = [
        expense('Food', 1000, method: 'HDFC'),
        expense('Card bill', 40000, method: 'HDFC'),
      ];
      expect(cardOutstanding(all, 'HDFC', kinds), -39000);
    });

    test('another card is another balance', () {
      final all = [
        expense('Food', 5000, method: 'HDFC'),
        expense('Card bill', 5000, method: 'ICICI'),
      ];
      expect(cardOutstanding(all, 'HDFC', kinds), 5000);
      expect(cardOutstanding(all, 'ICICI', kinds), -5000);
    });

    test('an investment bought on the card is not card spending', () {
      // It left the account but was not consumed, so it is not a purchase the
      // statement is settling either.
      final all = [
        expense('Food', 1000, method: 'HDFC'),
        expense('Investment', 20000, method: 'HDFC'),
      ];
      expect(cardOutstanding(all, 'HDFC', kinds), 1000);
    });

    test('a legacy row with only a note still lands on the card', () {
      // Old expenses carry no paymentMethod field; every surface resolves them
      // through expensePaymentMethod, and this must match.
      final all = [expense('Food', 900, note: 'paid by card')];
      expect(cardOutstanding(all, 'Card', kinds), 900);
    });

    test('purchases from different cycles both count', () {
      final all = [
        expense('Food', 2000, method: 'HDFC', date: DateTime(2026, 7, 4)),
        expense('Food', 3000, method: 'HDFC', date: DateTime(2026, 9, 4)),
      ];
      expect(cardOutstanding(all, 'HDFC', kinds), 5000);
    });
  });

  group('cardStatementPeriod', () {
    test('statement on the 18th, due on the 5th, is due next month', () {
      final period = cardStatementPeriod(
        statementDay: 18,
        dueDay: 5,
        now: DateTime(2026, 9, 25),
      );
      expect(period.statementDate, DateTime(2026, 9, 18));
      expect(period.periodStart, DateTime(2026, 8, 18));
      expect(period.dueDate, DateTime(2026, 10, 5));
    });

    test('statement on the 5th, due on the 25th, is due the same month', () {
      final period = cardStatementPeriod(
        statementDay: 5,
        dueDay: 25,
        now: DateTime(2026, 9, 12),
      );
      expect(period.statementDate, DateTime(2026, 9, 5));
      expect(period.dueDate, DateTime(2026, 9, 25));
    });

    test('the same statement and due day means a month to pay', () {
      final period = cardStatementPeriod(
        statementDay: 18,
        dueDay: 18,
        now: DateTime(2026, 9, 20),
      );
      expect(period.dueDate, DateTime(2026, 10, 18));
    });

    test('a 31st statement day clamps into February', () {
      final period = cardStatementPeriod(
        statementDay: 31,
        dueDay: 20,
        now: DateTime(2026, 3, 15),
      );
      // The statement that has closed is February's, and February 2026 has
      // 28 days. The window it covers runs from January's, which has 31.
      expect(period.statementDate, DateTime(2026, 2, 28));
      expect(period.periodStart, DateTime(2026, 1, 31));
      expect(period.dueDate, DateTime(2026, 3, 20));
    });
  });

  test('statementTotal covers the closed window only', () {
    final all = [
      expense('Food', 1000, method: 'HDFC', date: DateTime(2026, 8, 20)),
      expense('Food', 2000, method: 'HDFC', date: DateTime(2026, 9, 10)),
      // After the statement closed — next month's problem.
      expense('Food', 500, method: 'HDFC', date: DateTime(2026, 9, 19)),
      expense('Card bill', 3000, method: 'HDFC', date: DateTime(2026, 9, 2)),
    ];
    expect(
      statementTotal(
        all,
        'HDFC',
        kinds,
        periodStart: DateTime(2026, 8, 18),
        statementDate: DateTime(2026, 9, 18),
      ),
      3000,
    );
  });
}
