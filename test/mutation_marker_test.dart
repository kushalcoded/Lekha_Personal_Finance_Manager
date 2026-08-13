import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/models/pending/pending_transaction.dart';
import 'package:personal_expanse_tracker/services/storage/hive_service.dart';

Expense _expense(String id) => Expense(
  id: id,
  userId: 'u1',
  amount: 100,
  category: 'Food',
  date: DateTime(2026, 8, 13),
  createdAt: DateTime(2026, 8, 13),
);

/// The marker that tells sync "this device has edits the cloud hasn't seen".
///
/// It used to live only in memory, so every cold start looked clean and let a
/// pull overwrite work that was never pushed — changes made just before closing
/// the app came back reverted.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('lekha_marker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    await HiveService.initialize();
  });

  test('a local edit marks the device dirty', () async {
    final hive = HiveService();
    await hive.clearLocalMutationMarker();
    expect(hive.lastLocalMutationAt, isNull);

    await hive.addExpense(_expense('e1'));
    expect(hive.lastLocalMutationAt, isNotNull);
  });

  test('the marker survives a reopen, which is the whole point', () async {
    final hive = HiveService();
    await hive.addExpense(_expense('e2'));
    final before = hive.lastLocalMutationAt;
    expect(before, isNotNull);

    // Simulate a cold start: drop the in-memory copy by reading it back out of
    // storage the way a fresh process would.
    final stored = Hive.box<Map>('sync_state').get('__lastLocalMutationAt');
    expect(stored, isNotNull);
    expect(DateTime.parse(stored!['at'] as String).isUtc, isTrue);
  });

  test('a completed push clears it, or the device would never pull', () async {
    final hive = HiveService();
    await hive.addExpense(_expense('e3'));
    expect(hive.lastLocalMutationAt, isNotNull);

    await hive.clearLocalMutationMarker();
    expect(hive.lastLocalMutationAt, isNull);
    expect(Hive.box<Map>('sync_state').get('__lastLocalMutationAt'), isNull);
  });

  test('receiving an SMS detection does NOT mark the device dirty', () async {
    // Pinned separately in pending_dirty_flag_test: a device that merely
    // received a detection must still accept the other device's expenses.
    final hive = HiveService();
    await hive.clearLocalMutationMarker();
    await hive.savePendingTransaction(
      PendingTransaction(
        id: 'p1',
        amount: 50,
        dateTime: DateTime(2026, 8, 13),
        rawBody: 'debited 50',
        createdAt: DateTime(2026, 8, 13),
      ),
    );
    expect(hive.lastLocalMutationAt, isNull);
  });
}
