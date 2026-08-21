import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/pending/pending_transaction.dart';

void main() {
  test('PendingTransaction survives a Hive JSON round-trip', () {
    final txn = PendingTransaction(
      id: 'hash123',
      amount: 820.5,
      dateTime: DateTime(2026, 7, 16, 14, 5),
      rawBody: 'Rs 820.50 debited from A/c XX34',
      status: PendingStatus.pending,
      createdAt: DateTime(2026, 7, 16, 14, 6),
    );

    final restored = PendingTransaction.fromJson(txn.toJson());

    expect(restored.id, txn.id);
    expect(restored.amount, txn.amount);
    expect(restored.dateTime, txn.dateTime);
    expect(restored.rawBody, txn.rawBody);
    expect(restored.status, PendingStatus.pending);
  });

  test('copyWith flips status and unknown status falls back to pending', () {
    final txn = PendingTransaction(
      id: 'h',
      amount: 10,
      dateTime: DateTime(2026, 1, 1),
      rawBody: 'x',
      createdAt: DateTime(2026, 1, 1),
    );

    final added = txn.copyWith(
      status: PendingStatus.added,
      linkedExpenseId: 'e1',
    );
    expect(added.status, PendingStatus.added);
    expect(added.linkedExpenseId, 'e1');

    final bad = Map<String, dynamic>.from(txn.toJson())..['status'] = 'garbage';
    expect(PendingTransaction.fromJson(bad).status, PendingStatus.pending);
  });
}
