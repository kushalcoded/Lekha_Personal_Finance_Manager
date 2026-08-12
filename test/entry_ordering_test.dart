import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/providers/people/people_providers.dart';
import 'package:personal_expanse_tracker/screens/expenses/providers/expenses_providers.dart';

void main() {
  group('category order', () {
    const all = [
      'Food',
      'Friends',
      'Fuel',
      'Shopping',
      'Bills',
      'Travel',
      'Health',
      'Gifts',
      'Miscellaneous',
    ];

    test('most-used lead, the rest are strictly alphabetical', () {
      final ordered = orderCategories(all, {
        'Fuel': 9,
        'Food': 12,
        'Gifts': 3,
      });

      expect(ordered.frequent, ['Food', 'Fuel', 'Gifts']);
      // The remainder must be findable by knowing the alphabet, not by
      // remembering the order they happened to be created in.
      expect(ordered.rest, [
        'Bills',
        'Friends',
        'Health',
        'Miscellaneous',
        'Shopping',
        'Travel',
      ]);
    });

    test('every category survives the split', () {
      final ordered = orderCategories(all, {'Food': 2});
      expect(ordered.all.toSet(), all.toSet());
      expect(ordered.all.length, all.length);
    });

    test('ties break alphabetically, so positions do not jitter', () {
      // Equal counts must not depend on map iteration order.
      final a = orderCategories(all, {'Travel': 4, 'Bills': 4, 'Food': 4});
      final b = orderCategories(all, {'Food': 4, 'Bills': 4, 'Travel': 4});
      expect(a.frequent, ['Bills', 'Food', 'Travel']);
      expect(a.frequent, b.frequent);
    });

    test('an unused category is never pinned', () {
      final ordered = orderCategories(all, const {});
      expect(ordered.frequent, isEmpty);
      expect(ordered.rest.first, 'Bills');
    });

    test('the pinned group is capped', () {
      final ordered = orderCategories(all, {
        for (final name in all) name: 5,
      });
      expect(ordered.frequent.length, kFrequentCategoryCount);
    });
  });

  group('people ranking', () {
    final older = DateTime(2026, 5, 1);
    final newer = DateTime(2026, 8, 1);
    final people = [
      PersonUse(name: 'Zara', count: 5, lastUsed: older),
      PersonUse(name: 'Aditi', count: 1, lastUsed: newer),
      PersonUse(name: 'Manav', count: 5, lastUsed: newer),
    ];

    test('frequency beats alphabetical, recency breaks the tie', () {
      expect(rankPeople(people), ['Manav', 'Zara', 'Aditi']);
    });

    test('pinned names lead, in the order they were pinned', () {
      expect(
        rankPeople(people, pinned: ['Aditi']),
        ['Aditi', 'Manav', 'Zara'],
      );
      expect(
        rankPeople(people, pinned: ['Zara', 'Aditi']),
        ['Zara', 'Aditi', 'Manav'],
      );
    });

    test('hidden names are dropped entirely', () {
      expect(rankPeople(people, hidden: ['manav']), ['Zara', 'Aditi']);
    });

    test('pinning and hiding are case-insensitive', () {
      // The same person typed two ways must not slip past either list.
      expect(rankPeople(people, pinned: ['MANAV']).first, 'Manav');
      expect(rankPeople(people, hidden: ['ZARA']), isNot(contains('Zara')));
    });

    test('someone never used still ranks, just last', () {
      final withUnused = [
        ...people,
        const PersonUse(name: 'Bilal', count: 0),
      ];
      expect(rankPeople(withUnused).last, 'Bilal');
    });
  });
}
