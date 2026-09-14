import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/receivable/receivable_model.dart';
import 'package:personal_expanse_tracker/models/share/shared_entry.dart';
import 'package:personal_expanse_tracker/providers/share/share_providers.dart';
import 'package:personal_expanse_tracker/screens/debts/providers/people_balance_providers.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/split_helpers.dart';

/// Splitting an expense with a group picked puts the same bill in your books
/// and on the group's page. The two must agree, and the bill must not also
/// turn up a second time on each member's one-to-one page.
void main() {
  const owner = 'Kushal';

  group('posting a split to a group', () {
    test('shares add up to the bill and include the owner', () {
      const config = SplitConfig(people: ['Sarthak', 'Rahul']);
      final split = computeSplit(total: 1000, people: config.people);
      final entry = groupEntryForSplit(
        ownerName: owner,
        config: config,
        split: split,
      );
      expect(entry.payer, owner);
      expect(entry.total, 1000);
      expect(entry.shares.keys, containsAll([owner, 'Sarthak', 'Rahul']));
      expect(
        entry.shares.values.fold<double>(0, (a, b) => a + b),
        closeTo(1000, 0.001),
      );
    });

    test('a friend paying makes them the payer', () {
      const config = SplitConfig(people: ['Sarthak'], paidBy: 'Sarthak');
      final split = computeSplit(total: 600, people: config.people);
      final entry = groupEntryForSplit(
        ownerName: owner,
        config: config,
        split: split,
      );
      expect(entry.payer, 'Sarthak');
      expect(entry.shares, {owner: 300.0, 'Sarthak': 300.0});
    });

    test('nobody is listed with a share of nothing', () {
      const config = SplitConfig(
        people: ['Sarthak'],
        mode: SplitMode.exact,
        exact: {'Sarthak': 500},
      );
      final split = computeSplit(
        total: 500,
        people: config.people,
        mode: SplitMode.exact,
        exactAmounts: config.exact,
      );
      final entry = groupEntryForSplit(
        ownerName: owner,
        config: config,
        split: split,
      );
      expect(entry.shares, {'Sarthak': 500.0});
    });

    test('one row per expense, however many times it is posted', () {
      // A retry after a timeout that actually landed must update, not add.
      expect(groupEntryIdFor('abc'), groupEntryIdFor('abc'));
      expect(groupEntryIdFor('abc'), isNot(groupEntryIdFor('abd')));
      expect(
        groupEntryIdFor('rec_template_2026-09-14'),
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-')),
        reason: 'shared_entries.id is a uuid column',
      );
    });
  });

  group('the one-to-one page', () {
    PersonLedgerItem owed(String id, double amount, {String? source}) =>
        PersonLedgerItem(
          id: id,
          isReceivable: true,
          amount: amount,
          note: null,
          date: DateTime(2026, 9, 14),
          dueDate: DateTime(2026, 9, 21),
          settled: false,
          receivable: Receivable(
            id: id,
            userId: 'u',
            fromPerson: 'Sarthak',
            amount: amount,
            dueDate: DateTime(2026, 9, 21),
            isPaid: false,
            sourceExpenseId: source,
            createdAt: DateTime(2026, 9, 14),
          ),
        );

    final balance = PersonBalance(
      name: 'Sarthak',
      owedToYou: 700,
      youOwe: 0,
      items: [
        owed('cab', 200, source: 'group-bill'),
        owed('lunch', 300, source: 'just-us'),
        owed('accepted', 200, source: 'their-entry'),
      ],
    );

    test('a bill posted to a group stays off it, and out of its balance', () {
      final view = pairwiseView(
        balance: balance,
        inGroups: {'group-bill'},
        fromShare: const {},
      );
      expect(view.items.map((i) => i.id), ['lunch', 'accepted']);
      expect(view.net, 500);
    });

    test('their own accepted entry is not shown twice, but still counts', () {
      final view = pairwiseView(
        balance: balance,
        inGroups: const {},
        fromShare: {'their-entry'},
      );
      expect(view.items.map((i) => i.id), ['cab', 'lunch']);
      expect(view.net, 700);
    });
  });

  group('accepting a settlement', () {
    SharedEntry settlement(String payer, String receiver) => SharedEntry(
      id: 's',
      spaceId: 'g',
      personName: 'Rahul', // who typed it
      kind: 'settlement',
      total: 400,
      payerName: payer,
      shares: {receiver: 400},
      note: null,
      occurredOn: DateTime(2026, 9, 14),
    );

    test('is between the payer and the receiver, not whoever typed it', () {
      expect(settlementWith(settlement('Sarthak', owner), ownerName: owner), (
        person: 'Sarthak',
        toOwner: true,
      ));
      expect(settlementWith(settlement(owner, 'Sarthak'), ownerName: owner), (
        person: 'Sarthak',
        toOwner: false,
      ));
    });

    test('two guests paying each other is not the owner\'s to book', () {
      expect(
        settlementWith(settlement('Sarthak', 'Rahul'), ownerName: owner),
        isNull,
      );
    });
  });
}
