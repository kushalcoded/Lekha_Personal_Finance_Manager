import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/services/sync/snapshot_merge.dart';

/// Categories live in the per-user settings map, which syncs as one atomic
/// key. That buys the kind field free sync and backup, and costs one known
/// failure — documented by the last test here so nobody rediscovers it as a
/// mystery six months from now.
void main() {
  Map<String, dynamic> stored(String name, {String? kind}) => {
    'name': name,
    'iconKey': 'category',
    'colorHex': '#FFFFFF',
    'kind': ?kind,
  };

  group('fromJson', () {
    test('a list written before kinds existed gets the seeded ones back', () {
      expect(
        ExpenseCategory.fromJson(stored('Rent')).kind,
        CategoryKind.committed,
      );
      expect(
        ExpenseCategory.fromJson(stored('Investment')).kind,
        CategoryKind.investment,
      );
    });

    test('a name nobody seeded is everyday', () {
      expect(
        ExpenseCategory.fromJson(stored('Dog food')).kind,
        CategoryKind.everyday,
      );
    });

    test('a stored choice always beats the name table', () {
      // Someone who deliberately marks Rent as everyday must not have it
      // silently put back the next time the app reads the list.
      expect(
        ExpenseCategory.fromJson(stored('Rent', kind: 'everyday')).kind,
        CategoryKind.everyday,
      );
    });

    test('a kind from a newer build reads as everyday, not a crash', () {
      expect(
        ExpenseCategory.fromJson(stored('Food', kind: 'refund')).kind,
        CategoryKind.everyday,
      );
    });

    test('round-trips a non-default kind', () {
      const original = ExpenseCategory(
        name: 'SIP',
        iconKey: 'trending_up',
        colorHex: '#A3BF7B',
        kind: CategoryKind.investment,
      );
      expect(
        ExpenseCategory.fromJson(original.toJson()).kind,
        CategoryKind.investment,
      );
    });
  });

  test('an older build editing categories drops every kind', () {
    // The failure this design accepts. `categories` is one settings key, so a
    // device on a build without kinds writes a kind-less list, stamps the key
    // as changed, and the merge takes it. The name table restores the seeded
    // ones on the next read; a kind set on a custom category is lost.
    final withKinds = [
      const ExpenseCategory(
        name: 'Gym',
        iconKey: 'category',
        colorHex: '#FFFFFF',
        kind: CategoryKind.committed,
      ).toJson(),
    ];
    final withoutKinds = [
      {'name': 'Gym', 'iconKey': 'category', 'colorHex': '#FFFFFF'},
    ];

    expect(
      changedSettingKeys({'categories': withKinds}, {
        'categories': withoutKinds,
      }),
      contains('categories'),
    );
    // And what comes back is everyday, because "Gym" is not a seeded name.
    expect(
      ExpenseCategory.fromJson(withoutKinds.first).kind,
      CategoryKind.everyday,
    );
  });
}
