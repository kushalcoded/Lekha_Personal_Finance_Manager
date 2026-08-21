import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/pending/pending_transaction.dart';
import 'package:personal_expanse_tracker/services/storage/hive_service.dart';

PendingTransaction _provisional(String id, double amount) => PendingTransaction(
  id: id,
  amount: amount,
  dateTime: DateTime(2026, 8, 13, 18, 30),
  rawBody: 'Rs.$amount debited from A/c XX1234',
  createdAt: DateTime(2026, 8, 13, 18, 30),
  provisional: true,
);

/// A card read locally shows immediately and carries [PendingTransaction.provisional]
/// until the model confirms it. These pin the rules the verification pass must
/// obey — above all that a decision the user has already made is never undone.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('lekha_provisional');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    await HiveService.initialize();
  });

  test('the flag round-trips through storage', () async {
    final hive = HiveService();
    await hive.savePendingTransaction(_provisional('p1', 450));

    final stored = hive.getPendingTransactions().firstWhere(
      (t) => t.id == 'p1',
    );
    expect(stored.provisional, isTrue);
    expect(stored.amount, 450);
  });

  test('rows written before this feature read as already confirmed', () {
    // No 'provisional' key at all — those were all AI-parsed.
    final legacy = PendingTransaction.fromJson({
      'id': 'old',
      'amount': 200.0,
      'dateTime': '2026-08-01T10:00:00.000',
      'rawBody': 'Rs.200 debited',
      'status': 'pending',
      'createdAt': '2026-08-01T10:00:00.000',
    });
    expect(legacy.provisional, isFalse);
  });

  test('a correction updates the amount and clears the flag', () async {
    final hive = HiveService();
    await hive.savePendingTransaction(_provisional('p2', 450));

    final row = hive.getPendingTransactions().firstWhere((t) => t.id == 'p2');
    await hive.savePendingTransaction(
      row.copyWith(amount: 495.50, provisional: false),
    );

    final after = hive.getPendingTransactions().firstWhere((t) => t.id == 'p2');
    expect(after.amount, 495.50);
    expect(after.provisional, isFalse);
    expect(after.rawBody, row.rawBody, reason: 'the SMS trail must survive');
  });

  test('a row the model rejects is deleted outright', () async {
    // Agreed behaviour: it vanishes rather than sitting there to be dismissed
    // by hand when the app already knows it was not a spend.
    final hive = HiveService();
    await hive.savePendingTransaction(_provisional('p3', 999));
    expect(hive.getPendingTransactions().any((t) => t.id == 'p3'), isTrue);

    await hive.deletePendingTransaction('p3');
    expect(hive.getPendingTransactions().any((t) => t.id == 'p3'), isFalse);
  });

  test('deleting a detection does not mark the account dirty', () async {
    // Same rule as savePendingTransaction: detections sync through their own
    // table, and marking dirty here would stop the device accepting other
    // devices' expenses.
    final hive = HiveService();
    await hive.savePendingTransaction(_provisional('p4', 120));
    await hive.clearLocalMutationMarker();

    await hive.deletePendingTransaction('p4');
    expect(hive.lastLocalMutationAt, isNull);
  });

  test('an added row keeps its link and status through a copyWith', () async {
    // The verification pass must never reach a row the user has decided on;
    // this pins that the fields it would touch survive intact.
    final hive = HiveService();
    await hive.savePendingTransaction(_provisional('p5', 300));
    final row = hive.getPendingTransactions().firstWhere((t) => t.id == 'p5');

    await hive.savePendingTransaction(
      row.copyWith(
        status: PendingStatus.added,
        linkedExpenseId: 'exp-1',
        provisional: false,
      ),
    );

    final after = hive.getPendingTransactions().firstWhere((t) => t.id == 'p5');
    expect(after.status, PendingStatus.added);
    expect(after.linkedExpenseId, 'exp-1');
    expect(after.amount, 300, reason: 'a decided row keeps the amount shown');
  });
}
