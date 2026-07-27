import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/pending/pending_transaction.dart';
import 'package:personal_expanse_tracker/providers/sms/sms_providers.dart';

PendingTransaction _txn(double amount, DateTime dt) => PendingTransaction(
  id: '$amount-$dt',
  amount: amount,
  dateTime: dt,
  rawBody: 'x',
  createdAt: dt,
);

void main() {
  final base = DateTime(2026, 7, 16, 20, 53);

  test('same amount seconds apart is a duplicate (re-sent / bank+UPI)', () {
    final existing = [_txn(820, base)];
    expect(
      isDuplicateTransaction(existing, 820, base.add(const Duration(seconds: 40))),
      isTrue,
    );
  });

  test('same amount well outside the window is NOT a duplicate', () {
    final existing = [_txn(820, base)];
    expect(
      isDuplicateTransaction(existing, 820, base.add(const Duration(minutes: 10))),
      isFalse,
    );
  });

  test('different amount at the same time is NOT a duplicate', () {
    final existing = [_txn(820, base)];
    expect(isDuplicateTransaction(existing, 500, base), isFalse);
  });

  test('empty history is never a duplicate', () {
    expect(isDuplicateTransaction(const [], 820, base), isFalse);
  });
}
