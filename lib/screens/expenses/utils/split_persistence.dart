import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/payable/payable_model.dart';
import '../../../models/receivable/receivable_model.dart';
import '../../../providers/storage/storage_providers.dart';
import 'split_helpers.dart';

/// The debts a split created for one expense, found via [Receivable.sourceExpenseId]
/// / [Payable.sourceExpenseId].
class SplitLinks {
  final List<Receivable> receivables;
  final Payable? payable;

  const SplitLinks({this.receivables = const [], this.payable});

  bool get isEmpty => receivables.isEmpty && payable == null;
  bool get paidByMe => receivables.isNotEmpty;

  /// A settlement has already been recorded against one of these debts, so
  /// rewriting the split would erase real history.
  bool get anySettled =>
      receivables.any((r) => r.isPaid) ||
      (payable != null &&
          (payable!.status != PayableStatus.pending ||
              payable!.settlements.isNotEmpty));
}

SplitLinks findSplitLinks(WidgetRef ref, String expenseId) {
  final receivables = ref
      .read(receivablesProvider)
      .receivables
      .where((r) => r.sourceExpenseId == expenseId)
      .toList();
  final payables = ref
      .read(payablesProvider)
      .payables
      .where((p) => p.sourceExpenseId == expenseId)
      .toList();
  return SplitLinks(
    receivables: receivables,
    payable: payables.isEmpty ? null : payables.first,
  );
}

Future<void> deleteSplitLinks(WidgetRef ref, SplitLinks links) async {
  for (final r in links.receivables) {
    await ref.read(receivablesProvider.notifier).deleteReceivable(r.id);
  }
  if (links.payable != null) {
    await ref.read(payablesProvider.notifier).deletePayable(links.payable!.id);
  }
}

/// Create the debts for a split: if you paid, everyone else owes you their
/// share; if a friend paid, you owe them your share. Each is tagged with
/// [sourceExpenseId] so the split can be found and edited later.
Future<void> createSplitDebts({
  required WidgetRef ref,
  required String userId,
  required String sourceExpenseId,
  required SplitConfig config,
  required SplitResult split,
  required String? note,
  required DateTime date,
  required String category,
}) async {
  final now = DateTime.now();
  final due = date.add(const Duration(days: 7));

  if (config.paidByMe) {
    for (final share in split.others) {
      if (share.amount <= 0) continue;
      await ref
          .read(receivablesProvider.notifier)
          .addReceivable(
            Receivable(
              id: const Uuid().v4(),
              userId: userId,
              fromPerson: share.person,
              amount: share.amount,
              description: note,
              dueDate: due,
              isPaid: false,
              sourceExpenseId: sourceExpenseId,
              createdAt: now,
            ),
          );
    }
    return;
  }

  if (split.myShare <= 0) return;
  await ref
      .read(payablesProvider.notifier)
      .addPayable(
        Payable(
          id: const Uuid().v4(),
          userId: userId,
          toPerson: config.paidBy!,
          amount: split.myShare,
          remainingAmount: split.myShare,
          category: category,
          notes: note,
          sourceExpenseId: sourceExpenseId,
          // Who else was on the bill. Without this a friend-paid split knew
          // only the payer: it couldn't be reopened for editing, and everyone
          // else went uncounted in the people picker's ranking.
          participants: {
            for (final share in split.others) share.person: share.amount,
          },
          createdAt: now,
          dueDate: due,
          status: PayableStatus.pending,
          settlements: const [],
        ),
      );
}

/// Rebuild the split config + full bill from the debts it created.
///
/// [myShare] is the current stored expense amount. Returns null when it can't
/// be reconstructed — a friend-paid split saved before participants were
/// recorded has nothing to rebuild from.
({SplitConfig config, double total})? reconstructSplit(
  SplitLinks links,
  double myShare,
) {
  final payable = links.payable;
  if (links.receivables.isEmpty && payable != null) {
    if (payable.participants.isEmpty) return null;
    final othersTotal = payable.participants.values.fold<double>(
      0,
      (sum, amount) => sum + amount,
    );
    return (
      config: SplitConfig(
        people: payable.participants.keys.toList(),
        paidBy: payable.toPerson,
        mode: SplitMode.exact,
        exact: Map.of(payable.participants),
      ),
      total: myShare + othersTotal,
    );
  }
  if (links.receivables.isEmpty) return null;
  final people = links.receivables.map((r) => r.fromPerson).toList();
  final exact = {for (final r in links.receivables) r.fromPerson: r.amount};
  final othersTotal = links.receivables.fold<double>(
    0,
    (sum, r) => sum + r.amount,
  );
  return (
    config: SplitConfig(people: people, mode: SplitMode.exact, exact: exact),
    total: myShare + othersTotal,
  );
}
