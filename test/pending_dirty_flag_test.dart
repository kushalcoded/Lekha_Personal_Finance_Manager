import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/models/pending/pending_transaction.dart';
import 'package:personal_expanse_tracker/services/storage/hive_service.dart';

/// Regression: receiving a detected SMS must not make the device look like it
/// has unpushed money edits.
///
/// It did once, and the result was silent divergence: pulling a detection set
/// lastLocalMutationAt, sync then read that as "local is the fresh editor",
/// took the push branch on every later run, and the device stopped accepting
/// the other one's expenses — then overwrote them in the cloud. Detections
/// have their own table; only real money edits may set this flag.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('lekha_dirty');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    await HiveService.initialize();
  });

  test('saving a detected SMS leaves the account clean', () async {
    final hive = HiveService();
    await hive.clearLocalMutationMarker();

    await hive.savePendingTransaction(
      PendingTransaction(
        id: 'sms_1',
        amount: 214,
        dateTime: DateTime(2026, 8, 2, 16, 43),
        rawBody: 'Sent Rs.214.00',
        createdAt: DateTime(2026, 8, 2, 16, 43),
      ),
    );

    expect(
      hive.lastLocalMutationAt,
      isNull,
      reason: 'a detection is not a local money edit',
    );
  });

  test('deciding on a detection also leaves it clean', () async {
    final hive = HiveService();
    await hive.clearLocalMutationMarker();

    await hive.savePendingTransaction(
      PendingTransaction(
        id: 'sms_2',
        amount: 99,
        dateTime: DateTime(2026, 8, 2),
        rawBody: 'Sent Rs.99.00',
        status: PendingStatus.dismissed,
        createdAt: DateTime(2026, 8, 2),
      ),
    );

    expect(hive.lastLocalMutationAt, isNull);
  });

  test('an actual expense still marks the account dirty', () async {
    final hive = HiveService();
    // The marker is persisted now, so it's cleared through the same call a
    // completed push uses rather than by assignment.
    await hive.clearLocalMutationMarker();

    await hive.addExpense(
      Expense(
        id: 'exp_1',
        userId: 'u1',
        amount: 678,
        category: 'Health',
        description: 'Shampoo',
        date: DateTime(2026, 8, 2),
        createdAt: DateTime(2026, 8, 2),
      ),
    );

    expect(
      hive.lastLocalMutationAt,
      isNotNull,
      reason: 'money edits must still win over a stale cloud snapshot',
    );
  });
}
