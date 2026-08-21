/// Reducing a tangle of IOUs to the fewest payments that clear it.
///
/// Pure — no storage, no UI — like the split maths next door in
/// `split_helpers.dart`.
///
/// **This does nothing useful with two people.** A pairwise `net` is one number
/// and its exact negative, so the answer is always the single transfer the
/// Debts tab already shows. It earns its keep only once a group has three or
/// more people owing in different directions, which is why nothing calls it
/// yet.
library;

/// One payment that would clear part of the tangle.
class Transfer {
  /// Who hands over the money.
  final String from;

  /// Who receives it.
  final String to;

  final double amount;

  const Transfer(this.from, this.to, this.amount);

  @override
  String toString() => '$from → $to: $amount';

  @override
  bool operator ==(Object other) =>
      other is Transfer &&
      other.from == from &&
      other.to == to &&
      (other.amount - amount).abs() < 0.005;

  @override
  int get hashCode => Object.hash(from, to, (amount * 100).round());
}

double _round2(double value) => (value * 100).round() / 100;

/// The fewest payments (greedily) that settle [net], where a positive value
/// means that person is owed money and a negative one means they owe it.
///
/// Balances within [epsilon] of zero are treated as already settled, so
/// sub-paisa residue never produces a ₹0.00 transfer nobody can make.
///
/// Returns at most `net.length - 1` transfers, and the money paid always
/// equals the money received.
///
// ponytail: greedy max-matching. The true minimum is a subset-sum problem and
// therefore NP-hard; greedy can emit one extra transfer where some subgroup
// happens to net to zero on its own. Splitwise ships the same greedy. Worth
// replacing with a subset-partition search only if a group ever passes ~10
// people and somebody actually complains about the extra payment.
List<Transfer> simplifyDebts(Map<String, double> net, {double epsilon = 0.01}) {
  final creditors = <MapEntry<String, double>>[];
  final debtors = <MapEntry<String, double>>[];
  for (final entry in net.entries) {
    if (entry.value > epsilon) {
      creditors.add(MapEntry(entry.key, entry.value));
    } else if (entry.value < -epsilon) {
      debtors.add(MapEntry(entry.key, -entry.value));
    }
  }

  final transfers = <Transfer>[];
  // Re-sorting each pass is O(n² log n), which is nothing at the size of a
  // friend group and saves reaching for a heap.
  while (creditors.isNotEmpty && debtors.isNotEmpty) {
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final owed = creditors.first;
    final owing = debtors.first;
    final amount = _round2(owed.value < owing.value ? owed.value : owing.value);
    if (amount <= epsilon) break;

    transfers.add(Transfer(owing.key, owed.key, amount));

    final creditLeft = _round2(owed.value - amount);
    final debtLeft = _round2(owing.value - amount);
    if (creditLeft > epsilon) {
      creditors[0] = MapEntry(owed.key, creditLeft);
    } else {
      creditors.removeAt(0);
    }
    if (debtLeft > epsilon) {
      debtors[0] = MapEntry(owing.key, debtLeft);
    } else {
      debtors.removeAt(0);
    }
  }

  return transfers;
}
