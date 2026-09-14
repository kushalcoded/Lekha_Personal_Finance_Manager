import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/services/sync/snapshot_merge.dart';

/// Two devices that both changed things since they last synced. Before the
/// merge one snapshot replaced the other, and the expenses added on the web
/// app disappeared under a phone's older copy.
void main() {
  Map<String, dynamic> expense(String id, {double amount = 100}) => {
    'id': id,
    'userId': 'u',
    'amount': amount,
    'category': 'Food',
    'date': '2026-09-14T00:00:00.000',
    'createdAt': '2026-09-14T00:00:00.000',
  };

  Map<String, dynamic> clock(String at, {bool deleted = false}) => {
    'at': at,
    'deleted': deleted,
  };

  Map<String, dynamic> snap({
    List<Map<String, dynamic>> expenses = const [],
    List<Map<String, dynamic>> receivables = const [],
    Map<String, dynamic> recordClock = const {},
    Map<String, dynamic> settings = const {},
    Map<String, String> settingsClock = const {},
  }) => {
    'userId': 'u',
    'expenses': expenses,
    'receivables': receivables,
    'payables': <Map<String, dynamic>>[],
    'recurringTemplates': <Map<String, dynamic>>[],
    'recordClock': recordClock,
    'settings': settings,
    'settingsClock': settingsClock,
  };

  List<String> ids(Map<String, dynamic> s, [String key = 'expenses']) =>
      [for (final r in s[key] as List) '${(r as Map)['id']}']..sort();

  test('what each side added is kept', () {
    final merged = mergeSnapshots(
      snap(
        expenses: [expense('web')],
        recordClock: {'expense:web': clock('2026-09-14T10:00:00Z')},
      ),
      snap(
        expenses: [expense('phone')],
        recordClock: {'expense:phone': clock('2026-09-14T09:00:00Z')},
      ),
    );
    expect(ids(merged), ['phone', 'web']);
  });

  test('a deletion on the other device sticks', () {
    final merged = mergeSnapshots(
      snap(expenses: [expense('gone'), expense('kept')]),
      snap(
        expenses: [expense('kept')],
        recordClock: {
          'expense:gone': clock('2026-09-14T10:00:00Z', deleted: true),
        },
      ),
    );
    expect(ids(merged), ['kept']);
  });

  test('a deletion is remembered, so a third device cannot revive it', () {
    // Device A deleted. B merged with A and uploaded. C, which still has the
    // record, merges with B's upload: the clock must have survived B.
    final afterB = mergeSnapshots(
      snap(expenses: [expense('x2')]),
      snap(
        recordClock: {'expense:x': clock('2026-09-14T10:00:00Z', deleted: true)},
      ),
    );
    final atC = mergeSnapshots(snap(expenses: [expense('x')]), afterB);
    expect(ids(atC), ['x2']);
  });

  test('the same expense edited on both sides takes the newer edit', () {
    final merged = mergeSnapshots(
      snap(
        expenses: [expense('e', amount: 100)],
        recordClock: {'expense:e': clock('2026-09-14T09:00:00Z')},
      ),
      snap(
        expenses: [expense('e', amount: 250)],
        recordClock: {'expense:e': clock('2026-09-14T11:00:00Z')},
      ),
    );
    expect((merged['expenses'] as List).single['amount'], 250);
    expect(
      (merged['recordClock'] as Map)['expense:e']['at'],
      startsWith('2026-09-14T11:00:00'),
    );
  });

  test('records from before clocks existed are kept, not dropped', () {
    final merged = mergeSnapshots(
      snap(expenses: [expense('old-local')]),
      snap(expenses: [expense('old-remote')]),
    );
    expect(ids(merged), ['old-local', 'old-remote']);
  });

  test('two partial payments recorded on two devices both count', () {
    Map<String, dynamic> receivable(List<Map<String, dynamic>> settlements) => {
      'id': 'r',
      'amount': 1000,
      'isPaid': false,
      'remainingAmount': 1000 - settlements.fold<num>(0, (s, e) => s + e['amount']),
      'settlements': settlements,
    };
    final a = {'id': 's1', 'amount': 300, 'settledAt': '2026-09-14T09:00:00Z'};
    final b = {'id': 's2', 'amount': 700, 'settledAt': '2026-09-14T10:00:00Z'};

    final merged = mergeSnapshots(
      snap(
        receivables: [receivable([a])],
        recordClock: {'receivable:r': clock('2026-09-14T09:00:00Z')},
      ),
      snap(
        receivables: [receivable([b])],
        recordClock: {'receivable:r': clock('2026-09-14T10:00:00Z')},
      ),
    );
    final r = (merged['receivables'] as List).single as Map;
    expect((r['settlements'] as List).map((s) => s['id']), ['s1', 's2']);
    expect(r['remainingAmount'], 0.0);
    expect(r['isPaid'], isTrue);
  });

  group('settings', () {
    test('a key changed only on the other device survives', () {
      // The whole-map overlay this replaces put a stale device's categories
      // back over the ones just changed elsewhere.
      final merged = mergeSnapshots(
        snap(
          settings: {'categories': ['Food'], 'salary': 50000},
          settingsClock: {'salary': '2026-09-14T09:00:00Z'},
        ),
        snap(
          settings: {'categories': ['Food', 'Pets'], 'salary': 40000},
          settingsClock: {'categories': '2026-09-14T10:00:00Z'},
        ),
      );
      expect(merged['settings'], {
        'categories': ['Food', 'Pets'],
        'salary': 50000,
      });
    });

    test('a newer removal of a key wins', () {
      final merged = mergeSnapshots(
        snap(settings: {'draft': 'x'}),
        snap(settingsClock: {'draft': '2026-09-14T10:00:00Z'}),
      );
      expect((merged['settings'] as Map).containsKey('draft'), isFalse);
    });

    test('a key only one side has, with no clock either way, is kept', () {
      final merged = mergeSnapshots(
        snap(settings: {'a': 1}),
        snap(settings: {'b': 2}),
      );
      expect(merged['settings'], {'a': 1, 'b': 2});
    });

    test('only keys whose value changed are stamped', () {
      expect(
        changedSettingKeys(
          {'a': 1, 'list': [1, 2], 'gone': true},
          {'a': 1, 'list': [1, 2, 3], 'new': 'x'},
        ),
        {'list', 'gone', 'new'},
      );
    });
  });
}
