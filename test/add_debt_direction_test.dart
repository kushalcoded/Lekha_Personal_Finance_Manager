import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/debts/widgets/add_debt_sheet.dart';

/// The add-debt sheet asks one question that decides which store the money
/// lands in, and getting it backwards books the debt against the wrong person
/// silently — the balance still looks plausible, it is just the wrong sign.
void main() {
  ({bool receivable, double amount})? draft(
    DebtDirection direction,
    String amount,
  ) => resolveDebtDraft(direction: direction, rawAmount: amount);

  test('you paid means they owe you — a receivable', () {
    final d = draft(DebtDirection.youPaid, '500');
    expect(d?.receivable, isTrue);
    expect(d?.amount, 500);
  });

  test('they paid means you owe them — a payable', () {
    final d = draft(DebtDirection.theyPaid, '500');
    expect(d?.receivable, isFalse);
    expect(d?.amount, 500);
  });

  test('the amount goes through the same parser as everywhere else', () {
    expect(draft(DebtDirection.youPaid, '450+120')?.amount, 570);
    expect(draft(DebtDirection.youPaid, '450 120')?.amount, 570);
    expect(draft(DebtDirection.youPaid, ' 500 ')?.amount, 500);
    // Comma is a separator here, not a thousands mark — parseAmountExpression
    // says so, and the live total hint is what makes it visible.
    expect(draft(DebtDirection.youPaid, '1,200')?.amount, 201);
  });

  test('nothing is saved until the amount is a positive number', () {
    expect(draft(DebtDirection.youPaid, ''), isNull);
    expect(draft(DebtDirection.youPaid, '0'), isNull);
    expect(draft(DebtDirection.youPaid, '-40'), isNull);
    expect(draft(DebtDirection.youPaid, 'dinner'), isNull);
  });

  // The sentence under the pills is the only place the direction is spelled
  // out in words, so it has to agree with where the row actually goes.
  group('the summary line names the right debtor', () {
    test('you paid', () {
      expect(
        debtSummaryLine(
          name: 'Rahul',
          amount: 500,
          direction: DebtDirection.youPaid,
        ),
        contains('Rahul will owe you'),
      );
    });

    test('they paid', () {
      expect(
        debtSummaryLine(
          name: 'Rahul',
          amount: 500,
          direction: DebtDirection.theyPaid,
        ),
        contains("You'll owe Rahul"),
      );
    });
  });
}
