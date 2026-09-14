import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/services/storage/hive_service.dart';
import 'package:personal_expanse_tracker/services/sync/snapshot_merge.dart';

Expense _expense(String id, {double amount = 100}) => Expense(
  id: id,
  userId: 'u1',
  amount: amount,
  category: 'Food',
  date: DateTime(2026, 9, 14),
  createdAt: DateTime(2026, 9, 14),
);

/// The merge applied to a real store: the part where a mistake loses data
/// rather than merely computing the wrong list.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('lekha_merge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    await HiveService.initialize();
  });

  test('web adds, phone adds, both end up on both', () async {
    final hive = HiveService();
    await hive.addExpense(_expense('added-here'));
    await hive.deleteExpense('added-here');
    await hive.addExpense(_expense('added-here'));

    final local = hive.createLocalBackupSnapshot('u1');
    expect(
      (local['recordClock'] as Map).containsKey('expense:added-here'),
      isTrue,
      reason: 'every write leaves a clock in the snapshot',
    );

    // What the other device uploaded: one expense of its own.
    final remote = Map<String, dynamic>.from(local)
      ..['expenses'] = [
        {
          'id': 'added-there',
          'userId': 'u1',
          'amount': 250.0,
          'category': 'Travel',
          'date': '2026-09-14T00:00:00.000',
          'createdAt': '2026-09-14T00:00:00.000',
        },
      ]
      ..['recordClock'] = {
        'expense:added-there': {'at': '2026-09-14T12:00:00Z', 'deleted': false},
      };

    await hive.applyMergedSnapshot(mergeSnapshots(local, remote), 'u1');
    final ids = hive.getAllExpenses('u1').map((e) => e.id).toSet();
    expect(ids, containsAll(['added-here', 'added-there']));

    // And the next snapshot carries the other device's clock onward.
    final after = hive.createLocalBackupSnapshot('u1');
    expect(
      (after['recordClock'] as Map).containsKey('expense:added-there'),
      isTrue,
    );
  });

  test('a deletion from the other device removes the record here', () async {
    final hive = HiveService();
    await hive.addExpense(_expense('doomed'));
    final local = hive.createLocalBackupSnapshot('u1');
    final remote = Map<String, dynamic>.from(local)
      ..['expenses'] = (local['expenses'] as List)
          .where((e) => (e as Map)['id'] != 'doomed')
          .toList()
      ..['recordClock'] = {
        'expense:doomed': {
          'at': DateTime.now().toUtc().add(const Duration(minutes: 1))
              .toIso8601String(),
          'deleted': true,
        },
      };

    await hive.applyMergedSnapshot(mergeSnapshots(local, remote), 'u1');
    expect(hive.getAllExpenses('u1').any((e) => e.id == 'doomed'), isFalse);
  });

  test('saving settings stamps only the key that changed', () async {
    final hive = HiveService();
    await hive.saveSettings('u2', {'salary': 50000, 'categories': ['Food']});
    final first = Map.of(
      hive.createLocalBackupSnapshot('u2')['settingsClock'] as Map,
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await hive.saveSettings('u2', {
      'salary': 50000,
      'categories': ['Food', 'Pets'],
    });
    final second = hive.createLocalBackupSnapshot('u2')['settingsClock'] as Map;

    expect(second['salary'], first['salary']);
    expect(second['categories'], isNot(first['categories']));
  });

  test('a pull keeps the clocks it brought', () async {
    final hive = HiveService();
    final snapshot = hive.createLocalBackupSnapshot('u1')
      ..['recordClock'] = {
        'expense:pulled-deletion': {
          'at': '2026-09-14T12:00:00Z',
          'deleted': true,
        },
      };
    await hive.restoreFromBackup(snapshot);
    final clocks = hive.createLocalBackupSnapshot('u1')['recordClock'] as Map;
    expect(clocks['expense:pulled-deletion']?['deleted'], isTrue);
    expect(Hive.isBoxOpen('sync_metadata'), isTrue);
  });
}
