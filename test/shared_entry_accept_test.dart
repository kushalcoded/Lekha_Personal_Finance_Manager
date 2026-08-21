import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/share/shared_entry.dart';
import 'package:personal_expanse_tracker/providers/share/share_providers.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/split_helpers.dart';

/// Accepting a guest's entry is the only place money enters the ledger on
/// somebody else's word, and every way of getting it wrong is silent: the
/// balance still looks like a balance, it is just the wrong number or pointing
/// at the wrong person.
void main() {
  const owner = 'Kushal';

  SharedEntry entry({
    String kind = 'expense',
    required double total,
    required String payer,
    required Map<String, double> shares,
  }) => SharedEntry(
    id: 'e1',
    spaceId: 's1',
    personName: 'Rahul',
    kind: kind,
    total: total,
    payerName: payer,
    shares: shares,
    note: 'Dinner',
    occurredOn: DateTime(2026, 8, 18),
  );

  SplitResult resolve(SharedEntry e) {
    final config = splitConfigFor(e, ownerName: owner);
    return computeSplit(
      total: e.total,
      people: config.people,
      mode: config.mode,
      exactAmounts: config.exact,
    );
  }

  test('the guest paid and split it evenly — the owner owes their half', () {
    final e = entry(
      total: 1200,
      payer: 'Rahul',
      shares: {'Rahul': 600, 'Kushal': 600},
    );
    expect(splitConfigFor(e, ownerName: owner).paidByMe, isFalse);
    final split = resolve(e);
    expect(split.myShare, 600);
    expect(split.others.single.person, 'Rahul');
    expect(split.others.single.amount, 600);
  });

  test('the owner paid and split it evenly — the guest owes their half', () {
    final e = entry(
      total: 1200,
      payer: owner,
      shares: {'Rahul': 600, 'Kushal': 600},
    );
    // paidByMe drives createSplitDebts down the receivable branch.
    expect(splitConfigFor(e, ownerName: owner).paidByMe, isTrue);
    expect(resolve(e).myShare, 600);
  });

  test('the expense amount is the owner\'s share, never the whole bill', () {
    final e = entry(
      total: 900,
      payer: 'Rahul',
      shares: {'Rahul': 300, 'Kushal': 600},
    );
    expect(resolve(e).myShare, 600);
    expect(resolve(e).others.single.amount, 300);
  });

  test('the guest covering the whole thing leaves the owner nothing to book', () {
    final e = entry(total: 900, payer: 'Rahul', shares: {'Rahul': 900});
    // createSplitDebts returns early on myShare <= 0, so no payable is written.
    expect(resolve(e).myShare, 0);
  });

  test('the owner covering the whole thing is owed all of it', () {
    final e = entry(total: 900, payer: owner, shares: {'Rahul': 900});
    final split = resolve(e);
    expect(split.myShare, 0);
    expect(split.others.single.amount, 900);
  });

  test('shares always add back up to the bill', () {
    final e = entry(
      total: 1000.01,
      payer: 'Rahul',
      shares: {'Rahul': 500, 'Kushal': 500.01},
    );
    final split = resolve(e);
    expect(split.myShare + split.othersTotal, closeTo(1000.01, 0.001));
  });

  test('a missing share for the guest is treated as zero, not as null', () {
    final e = entry(total: 500, payer: owner, shares: {'Kushal': 500});
    expect(splitConfigFor(e, ownerName: owner).exact['Rahul'], 0);
    expect(resolve(e).myShare, 500);
  });

  // A settlement moves money that already exists; which side it pays down is
  // the entire decision, and it is exactly invertible.
  group('settlements', () {
    test('the guest paying the owner pays down what the guest owed', () {
      final e = entry(
        kind: 'settlement',
        total: 430,
        payer: 'Rahul',
        shares: {'Kushal': 430},
      );
      expect(settlementPaysOwner(e, ownerName: owner), isTrue);
    });

    test('the owner paying the guest pays down what the owner owed', () {
      final e = entry(
        kind: 'settlement',
        total: 430,
        payer: owner,
        shares: {'Rahul': 430},
      );
      expect(settlementPaysOwner(e, ownerName: owner), isFalse);
    });
  });

  // The card's one line is the only place the owner is told what a tap will
  // do. It has to name the direction in words, never "payable"/"receivable".
  group('the effect line', () {
    test('names who would owe whom when the guest paid', () {
      final e = entry(
        total: 1200,
        payer: 'Rahul',
        shares: {'Rahul': 600, 'Kushal': 600},
      );
      expect(
        sharedEntryEffect(e, ownerName: owner),
        'Bill ₹1,200 · you would owe Rahul ₹600',
      );
    });

    test('flips when the owner paid', () {
      final e = entry(
        total: 1200,
        payer: owner,
        shares: {'Rahul': 600, 'Kushal': 600},
      );
      expect(
        sharedEntryEffect(e, ownerName: owner),
        contains('Rahul would owe you'),
      );
    });

    test('says so when nothing is owed either way', () {
      final e = entry(total: 900, payer: 'Rahul', shares: {'Rahul': 900});
      expect(sharedEntryEffect(e, ownerName: owner), contains('covered it'));
    });

    test('a settlement reads as a claim, not a fact', () {
      final e = entry(
        kind: 'settlement',
        total: 430,
        payer: 'Rahul',
        shares: {'Kushal': 430},
      );
      expect(
        sharedEntryEffect(e, ownerName: owner),
        'Rahul says they paid you ₹430',
      );
    });
  });

  // A group entry splits among everyone on it, and must not collapse onto
  // whoever happened to submit it.
  group('groups', () {
    test('a four-way split lands as a four-way split', () {
      final e = SharedEntry(
        id: 'g1',
        spaceId: 's1',
        personName: 'Rahul',
        kind: 'expense',
        total: 1200,
        payerName: 'Meera',
        shares: const {'Rahul': 300, 'Meera': 300, 'Kushal': 300, 'Aman': 300},
        note: 'Cab',
        occurredOn: DateTime(2026, 8, 18),
      );
      final config = splitConfigFor(e, ownerName: owner);
      expect(config.people, containsAll(['Rahul', 'Meera', 'Aman']));
      expect(config.people, isNot(contains(owner)));
      expect(config.paidByMe, isFalse, reason: 'Meera paid, not Kushal');
      expect(config.paidBy, 'Meera');
      final split = computeSplit(
        total: e.total,
        people: config.people,
        mode: config.mode,
        exactAmounts: config.exact,
      );
      expect(split.myShare, 300);
      expect(split.othersTotal, 900);
    });

    test('somebody who paid but ate none of it is still a participant', () {
      final e = SharedEntry(
        id: 'g2',
        spaceId: 's1',
        personName: 'Rahul',
        kind: 'expense',
        total: 600,
        payerName: 'Meera',
        shares: const {'Rahul': 300, 'Kushal': 300},
        note: 'Tickets',
        occurredOn: DateTime(2026, 8, 18),
      );
      final config = splitConfigFor(e, ownerName: owner);
      expect(config.people, contains('Meera'));
      expect(config.exact['Meera'], 0);
      expect(config.paidBy, 'Meera');
    });

    // A group lets guests split between themselves. Those entries are real on
    // the shared page and count there, but the owner has no stake in them, and
    // accepting one writes nothing at all.
    test('an entry between two guests is not the owner\'s business', () {
      final e = SharedEntry(
        id: 'g3',
        spaceId: 's1',
        personName: 'Rahul',
        kind: 'expense',
        total: 400,
        payerName: 'Meera',
        shares: const {'Rahul': 200, 'Meera': 200},
        note: 'Their cab',
        occurredOn: DateTime(2026, 8, 18),
      );
      expect(entryInvolvesOwner(e, ownerName: owner), isFalse);
      // And it would indeed do nothing: no share for the owner to book.
      expect(resolve(e).myShare, 0);
    });

    test('the owner having a share puts it back in their inbox', () {
      final e = SharedEntry(
        id: 'g4',
        spaceId: 's1',
        personName: 'Rahul',
        kind: 'expense',
        total: 600,
        payerName: 'Meera',
        shares: const {'Rahul': 300, 'Kushal': 300},
        note: 'Tickets',
        occurredOn: DateTime(2026, 8, 18),
      );
      expect(entryInvolvesOwner(e, ownerName: owner), isTrue);
    });

    test('the owner paying counts even with no share of their own', () {
      final e = SharedEntry(
        id: 'g5',
        spaceId: 's1',
        personName: 'Rahul',
        kind: 'expense',
        total: 600,
        payerName: owner,
        shares: const {'Rahul': 600},
        note: 'Covered it',
        occurredOn: DateTime(2026, 8, 18),
      );
      expect(entryInvolvesOwner(e, ownerName: owner), isTrue);
    });
  });

  // Four states across a list of names, and only one of them is guesswork:
  // the server knows when a page loaded and when a PIN was chosen; nothing can
  // know whether the message was actually delivered.
  // The owner is the author of anything they add themselves, so any wording
  // built from personName describes them to themselves.
  group('an entry the owner added alone', () {
    test('does not book them a debt with themselves', () {
      final e = SharedEntry(
        id: 'g6',
        spaceId: 's1',
        personName: owner,
        kind: 'expense',
        total: 300,
        payerName: owner,
        shares: const {'Kushal': 300},
        note: null,
        occurredOn: DateTime(2026, 8, 21),
      );
      final config = splitConfigFor(e, ownerName: owner);
      expect(
        config.people,
        isEmpty,
        reason: 'nobody else is on it, so there is nobody to owe',
      );
      expect(resolve(e).myShare, 300);
    });
  });

  group('shareProgressFor', () {
    test('a PIN means joined, whatever else is true', () {
      expect(
        shareProgressFor(
          sent: false,
          openedAt: null,
          joinedAt: DateTime(2026, 8, 21),
        ),
        ShareProgress.joined,
      );
    });

    test('opened without a PIN is its own state', () {
      expect(
        shareProgressFor(sent: true, openedAt: DateTime(2026, 8, 21)),
        ShareProgress.opened,
      );
    });

    test('taking the link and them never opening it are different things', () {
      expect(shareProgressFor(sent: true), ShareProgress.sent);
      expect(shareProgressFor(sent: false), ShareProgress.notSent);
    });

    test('every state says something, none of them blank', () {
      for (final p in ShareProgress.values) {
        expect(shareProgressLabel(p), isNotEmpty, reason: p.name);
      }
    });
  });

  group('fromRow', () {
    test('survives the types Postgres actually returns', () {
      final e = SharedEntry.fromRow({
        'id': 'abc',
        'space_id': 'sp',
        'kind': 'expense',
        'total': 1200, // int, not double
        'payer_name': 'Rahul',
        'shares': <dynamic, dynamic>{'Rahul': 600, 'Kushal': 600.0},
        'note': '  ',
        'occurred_on': '2026-08-18',
      }, personName: 'Rahul');
      expect(e.total, 1200.0);
      expect(e.shares['Rahul'], 600.0);
      expect(e.note, isNull, reason: 'a blank note is no note');
      expect(e.occurredOn, DateTime(2026, 8, 18));
    });
  });
}
