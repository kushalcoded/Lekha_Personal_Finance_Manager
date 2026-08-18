import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/payable/payable_model.dart';
import 'package:personal_expanse_tracker/providers/people/people_providers.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/split_helpers.dart';
import 'package:personal_expanse_tracker/screens/expenses/utils/split_persistence.dart';

/// A split someone else paid used to record only the payer, so it could not be
/// reopened and everyone else on the bill went uncounted. Rows written before
/// that still exist, so both paths have to keep working.
void main() {
  Payable payable({Map<String, double> participants = const {}}) => Payable(
    id: 'pay_1',
    userId: 'u1',
    toPerson: 'Rahul',
    amount: 250,
    remainingAmount: 250,
    category: 'Food',
    sourceExpenseId: 'exp_1',
    participants: participants,
    createdAt: DateTime(2026, 8, 1),
    dueDate: DateTime(2026, 8, 8),
    status: PayableStatus.pending,
    settlements: const [],
  );

  group('participants survive storage', () {
    test('round trip through JSON', () {
      final restored = Payable.fromJson(
        payable(participants: {'Rahul': 400, 'Priya': 350}).toJson(),
      );

      expect(restored.participants, {'Rahul': 400.0, 'Priya': 350.0});
    });

    test('a row written before the field decodes to empty, not a crash', () {
      final legacy = payable().toJson()..remove('participants');

      expect(Payable.fromJson(legacy).participants, isEmpty);
    });
  });

  group('reconstructSplit', () {
    test('rebuilds a friend-paid split, bill and all', () {
      final result = reconstructSplit(
        SplitLinks(
          payable: payable(participants: {'Rahul': 400, 'Priya': 350}),
        ),
        250,
      );

      expect(result, isNotNull);
      expect(result!.total, 1000); // 250 mine + 400 + 350
      expect(result.config.paidBy, 'Rahul');
      expect(result.config.paidByMe, isFalse);
      expect(result.config.mode, SplitMode.exact);
      expect(result.config.people, containsAll(['Rahul', 'Priya']));
    });

    test('gives up on a row that never stored anyone', () {
      expect(reconstructSplit(SplitLinks(payable: payable()), 250), isNull);
    });
  });

  group('who a payable puts you in touch with', () {
    test('the payer plus everyone else on the bill', () {
      expect(
        payablePeople(payable(participants: {'Rahul': 400, 'Priya': 350})),
        ['Rahul', 'Priya'],
      );
    });

    test('the payer is listed once, however they are spelled', () {
      expect(
        payablePeople(payable(participants: {'rahul': 400, 'Priya': 350})),
        ['Rahul', 'Priya'],
      );
    });

    test('a plain payable is just the person you owe', () {
      expect(payablePeople(payable()), ['Rahul']);
    });
  });
}
