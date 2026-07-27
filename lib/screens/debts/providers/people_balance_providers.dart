import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/payable/payable_model.dart';
import '../../../models/receivable/receivable_model.dart';
import '../../../providers/storage/storage_providers.dart';

/// One entry in a person's ledger — either they owe you (a receivable) or you
/// owe them (a payable). Keeps the source object so settle actions can reuse
/// the existing receivable/payable flows.
class PersonLedgerItem {
  final String id;

  /// true = they owe you; false = you owe them.
  final bool isReceivable;

  /// What's still outstanding on this entry.
  final double amount;
  final String? note;
  final DateTime date;
  final DateTime dueDate;
  final bool settled;
  final Receivable? receivable;
  final Payable? payable;

  const PersonLedgerItem({
    required this.id,
    required this.isReceivable,
    required this.amount,
    required this.note,
    required this.date,
    required this.dueDate,
    required this.settled,
    this.receivable,
    this.payable,
  });

  bool get isOverdue => !settled && dueDate.isBefore(DateTime.now());
}

/// Everything you and one person owe each other, netted.
class PersonBalance {
  final String name;
  final double owedToYou;
  final double youOwe;
  final List<PersonLedgerItem> items;

  const PersonBalance({
    required this.name,
    required this.owedToYou,
    required this.youOwe,
    required this.items,
  });

  /// Positive = they owe you, negative = you owe them.
  double get net => owedToYou - youOwe;
  bool get hasOverdue => items.any((i) => i.isOverdue);
  int get openCount => items.where((i) => !i.settled).length;
}

class _Acc {
  final String name;
  double owedToYou = 0;
  double youOwe = 0;
  final List<PersonLedgerItem> items = [];
  _Acc(this.name);
}

/// Receivables + payables collapsed into one net balance per person, biggest
/// balance first. People whose debts are fully settled drop off the list.
final peopleBalancesProvider = Provider<List<PersonBalance>>((ref) {
  final receivables = ref.watch(receivablesProvider).receivables;
  final payables = ref.watch(payablesProvider).payables;
  final byPerson = <String, _Acc>{};

  for (final r in receivables) {
    final name = r.fromPerson.trim();
    if (name.isEmpty) continue;
    final acc = byPerson.putIfAbsent(name.toLowerCase(), () => _Acc(name));
    final settled = r.isPaid || r.remaining <= 0;
    acc.items.add(
      PersonLedgerItem(
        id: r.id,
        isReceivable: true,
        amount: settled ? r.amount : r.remaining,
        note: r.description,
        date: r.createdAt,
        dueDate: r.dueDate,
        settled: settled,
        receivable: r,
      ),
    );
    if (!settled) acc.owedToYou += r.remaining;
  }

  for (final p in payables) {
    final name = p.toPerson.trim();
    if (name.isEmpty) continue;
    final acc = byPerson.putIfAbsent(name.toLowerCase(), () => _Acc(name));
    final settled = p.status == PayableStatus.paid || p.remainingAmount <= 0;
    acc.items.add(
      PersonLedgerItem(
        id: p.id,
        isReceivable: false,
        amount: settled ? p.amount : p.remainingAmount,
        note: p.notes,
        date: p.createdAt,
        dueDate: p.dueDate,
        settled: settled,
        payable: p,
      ),
    );
    if (!settled) acc.youOwe += p.remainingAmount;
  }

  final people = byPerson.values
      .where((a) => a.owedToYou > 0 || a.youOwe > 0)
      .map(
        (a) => PersonBalance(
          name: a.name,
          owedToYou: a.owedToYou,
          youOwe: a.youOwe,
          items: a.items..sort((x, y) => y.date.compareTo(x.date)),
        ),
      )
      .toList();

  people.sort((a, b) => b.net.abs().compareTo(a.net.abs()));
  return people;
});

/// A single person's balance, kept live as receivables/payables change.
final personBalanceProvider = Provider.family<PersonBalance?, String>((
  ref,
  name,
) {
  final people = ref.watch(peopleBalancesProvider);
  final match = people.where(
    (p) => p.name.toLowerCase() == name.toLowerCase(),
  );
  return match.isEmpty ? null : match.first;
});
