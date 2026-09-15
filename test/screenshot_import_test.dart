import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/models/pending/pending_transaction.dart';
import 'package:personal_expanse_tracker/providers/sms/screenshot_import.dart';

/// A payments-app screenshot becoming detected payments. What can go wrong is
/// quiet: a payment added twice, a real one swallowed as a duplicate, or last
/// December's rows filed next December.
void main() {
  final now = DateTime(2026, 9, 14, 18);

  Map<String, dynamic> row(
    double amount, {
    String merchant = 'Swiggy',
    String? date = '2026-09-14',
    String? time = '13:05',
    bool isDebit = true,
    String status = 'success',
  }) => {
    'amount': amount,
    'merchant': merchant,
    'date': date,
    'time': time,
    'isDebit': isDebit,
    'status': status,
  };

  ({List<PendingTransaction> fresh, int known, Map<AlreadyHere, int> where})
  import(
    List<Map<String, dynamic>> rows, {
    List<PendingTransaction> existing = const [],
    List<Expense> expenses = const [],
  }) => pendingFromScreenshot(
    paymentsFromScreenshot({'items': rows}, now: now),
    app: 'Google Pay',
    existing: existing,
    expenses: expenses,
    now: now,
  );

  group('reading the reply', () {
    test('only money that left and went through counts', () {
      final payments = paymentsFromScreenshot({
        'items': [
          row(450),
          row(200, isDebit: false),
          row(99, status: 'failed'),
          row(10, status: 'pending'),
          row(0),
          row(75, date: null),
        ],
      }, now: now);
      expect(payments.map((p) => p.amount), [450]);
      expect(payments.single.merchant, 'Swiggy');
      expect(payments.single.when, DateTime(2026, 9, 14, 13, 5));
    });

    test('a date with no time sits at noon, the same every read', () {
      final p = paymentsFromScreenshot({
        'items': [row(120, time: null)],
      }, now: now).single;
      expect(p.when, DateTime(2026, 9, 14, 12));
    });

    test('a date after today was last year', () {
      // "12 Dec" read in September, and called this year by the model.
      final p = paymentsFromScreenshot({
        'items': [row(300, date: '2026-12-12')],
      }, now: now).single;
      expect(p.when.year, 2025);
    });
  });

  group('what is new', () {
    test('rows land as detected payments with where the money went', () {
      final result = import([row(450), row(80, merchant: 'Chai Point')]);
      expect(result.fresh.map((t) => t.merchant), ['Swiggy', 'Chai Point']);
      expect(result.fresh.first.rawBody, 'Google Pay · UPI');
      expect(result.fresh.every((t) => !t.provisional), isTrue);
    });

    test('importing an overlapping screenshot adds nothing twice', () {
      final first = import([row(450), row(80, merchant: 'Chai Point')]);
      final second = import([
        row(80, merchant: 'Chai Point'),
        row(450),
        row(999, merchant: 'IRCTC'),
      ], existing: first.fresh);
      expect(second.fresh.map((t) => t.amount), [999]);
      expect(second.known, 2);
    });

    test('ids are the same however many times a row is read', () {
      expect(
        import([row(450)]).fresh.single.id,
        import([row(450)]).fresh.single.id,
      );
    });

    test('two real payments of the same amount on one day are both kept', () {
      final result = import([
        row(50, merchant: 'Tea'),
        row(50, merchant: 'Tea'),
      ]);
      expect(result.fresh, hasLength(2));
      expect(result.fresh[0].id, isNot(result.fresh[1].id));
    });

    test('says where each skipped payment already is', () {
      PendingTransaction detected(String id, double amount, PendingStatus s) =>
          PendingTransaction(
            id: id,
            amount: amount,
            dateTime: DateTime(2026, 9, 14, 9),
            rawBody: 'HDFC Bank · UPI',
            createdAt: now,
            status: s,
          );
      final typed = Expense(
        id: 'typed',
        userId: 'u',
        amount: 90,
        category: 'Food',
        date: DateTime(2026, 9, 14),
        createdAt: now,
      );
      final result = import(
        [row(20), row(50), row(80), row(90), row(344)],
        existing: [
          detected('a', 20, PendingStatus.pending),
          detected('b', 50, PendingStatus.added),
          detected('c', 80, PendingStatus.dismissed),
        ],
        expenses: [typed],
      );
      expect(result.where, {
        AlreadyHere.waiting: 1,
        AlreadyHere.added: 2,
        AlreadyHere.dismissed: 1,
      });
      expect(result.fresh.single.amount, 344);
    });

    test('a payment already here from an SMS is not added again', () {
      final sms = PendingTransaction(
        id: 'sms1',
        amount: 450,
        dateTime: DateTime(2026, 9, 14, 13, 6),
        rawBody: 'HDFC Bank · UPI',
        createdAt: now,
        status: PendingStatus.dismissed,
      );
      expect(import([row(450)], existing: [sms]).fresh, isEmpty);
    });

    test('an expense typed in by hand counts, but only once', () {
      final typed = Expense(
        id: 'e1',
        userId: 'u',
        amount: 50,
        category: 'Food',
        date: DateTime(2026, 9, 14),
        createdAt: now,
      );
      // One ₹50 already in the books; the screenshot shows two.
      final result = import([row(50), row(50)], expenses: [typed]);
      expect(result.fresh, hasLength(1));
      expect(result.known, 1);
    });

    test('an expense added from a detection is not counted twice', () {
      final added = PendingTransaction(
        id: 'sms2',
        amount: 50,
        dateTime: DateTime(2026, 9, 14, 9),
        rawBody: 'HDFC Bank · UPI',
        createdAt: now,
        status: PendingStatus.added,
        linkedExpenseId: 'e2',
      );
      final itsExpense = Expense(
        id: 'e2',
        userId: 'u',
        amount: 50,
        category: 'Food',
        date: DateTime(2026, 9, 14),
        createdAt: now,
      );
      final result = import(
        [row(50), row(50)],
        existing: [added],
        expenses: [itsExpense],
      );
      expect(result.fresh, hasLength(1));
    });
  });

  test('the merchant is dropped once the card is decided', () {
    final txn = PendingTransaction(
      id: 'x',
      amount: 1,
      dateTime: now,
      rawBody: 'Google Pay · UPI',
      createdAt: now,
      merchant: 'Swiggy',
    );
    expect(
      txn.copyWith(status: PendingStatus.added, clearMerchant: true).merchant,
      isNull,
    );
    expect(PendingTransaction.fromJson(txn.toJson()).merchant, 'Swiggy');
    expect(cleanMerchant('  null '), isNull);
  });
}
