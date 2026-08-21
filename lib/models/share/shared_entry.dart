import '../../screens/expenses/utils/split_helpers.dart';
import '../../utils/formatters/formatters.dart';

/// One line a guest added on a shared page, waiting for a decision.
///
/// Cloud-only, and deliberately **not** a Hive record. A detected SMS is stored
/// locally because it arrives on a device that may be offline for days; this
/// only exists because the network was there to fetch it, so a local copy would
/// be a second source of truth for no benefit.
class SharedEntry {
  final String id;
  final String spaceId;

  /// The guest who added it — also the person this ledger is with.
  final String personName;

  /// `expense` or `settlement`.
  final String kind;

  /// The whole bill, not anyone's share.
  final double total;

  /// Whose money it was. Matches the owner's display name when they paid.
  final String payerName;

  /// Name → that person's share of [total].
  final Map<String, double> shares;

  final String? note;
  final DateTime occurredOn;

  const SharedEntry({
    required this.id,
    required this.spaceId,
    required this.personName,
    required this.kind,
    required this.total,
    required this.payerName,
    required this.shares,
    required this.note,
    required this.occurredOn,
  });

  bool get isSettlement => kind == 'settlement';

  /// Rebuilt defensively: Postgres hands numerics back as `num`, and a jsonb
  /// map arrives with dynamic keys.
  factory SharedEntry.fromRow(
    Map<String, dynamic> row, {
    required String personName,
  }) {
    return SharedEntry(
      id: row['id'].toString(),
      spaceId: row['space_id'].toString(),
      personName: personName,
      kind: row['kind'] as String? ?? 'expense',
      total: (row['total'] as num?)?.toDouble() ?? 0,
      payerName: row['payer_name'] as String? ?? '',
      shares: {
        for (final e in (row['shares'] as Map? ?? const {}).entries)
          if ((e.value as num?) != null)
            e.key.toString(): (e.value as num).toDouble(),
      },
      note: (row['note'] as String?)?.trim().isEmpty ?? true
          ? null
          : row['note'] as String,
      occurredOn:
          DateTime.tryParse(row['occurred_on']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// How a guest's expense becomes a split this app already knows how to store.
///
/// Everything follows from two facts: whether the owner paid, and what the
/// owner's own share was. Nothing is invented here — the result goes straight
/// into [computeSplit] and `createSplitDebts`, the same pair the add-expense
/// form uses, so an accepted entry is indistinguishable from one typed by hand.
SplitConfig splitConfigFor(SharedEntry entry, {required String ownerName}) {
  // Everyone on the bill but the owner. Driven by the shares rather than by
  // who submitted it, so a group entry splitting four ways lands as a four-way
  // split rather than collapsing onto the author.
  final others = entry.shares.keys.where((n) => n != ownerName).toList();
  if (others.isEmpty) others.add(entry.personName);
  // Somebody can pay without eating any of it, and createSplitDebts needs them
  // among the participants to record who was owed.
  if (entry.payerName != ownerName && !others.contains(entry.payerName)) {
    others.add(entry.payerName);
  }
  return SplitConfig(
    people: others,
    // paidBy null means "me" — the owner.
    paidBy: entry.payerName == ownerName ? null : entry.payerName,
    // Always exact: the amounts were already shown to whoever entered them, and
    // re-deriving an equal split here could disagree with them by a paisa.
    mode: SplitMode.exact,
    exact: {for (final name in others) name: entry.shares[name] ?? 0},
  );
}

/// True when accepting this settlement means money came *to* the owner, which
/// is what decides whether it pays down receivables or payables.
bool settlementPaysOwner(SharedEntry entry, {required String ownerName}) =>
    entry.payerName != ownerName;

/// One line saying what accepting this entry would actually do, in the terms
/// the person reading the card already thinks in — never "payable" or
/// "receivable", and always naming who ends up owing whom.
String sharedEntryEffect(SharedEntry entry, {required String ownerName}) {
  final money = AppFormatters.formatCurrency;
  if (entry.isSettlement) {
    return settlementPaysOwner(entry, ownerName: ownerName)
        ? '${entry.personName} says they paid you ${money(entry.total)}'
        : '${entry.personName} says you paid them ${money(entry.total)}';
  }

  final config = splitConfigFor(entry, ownerName: ownerName);
  final split = computeSplit(
    total: entry.total,
    people: config.people,
    mode: config.mode,
    exactAmounts: config.exact,
  );
  final bill = 'Bill ${money(entry.total)}';
  if (config.paidByMe) {
    final theirs = split.others.single.amount;
    return theirs <= 0
        ? '$bill · nothing owed either way'
        : '$bill · ${entry.personName} would owe you ${money(theirs)}';
  }
  return split.myShare <= 0
      ? '$bill · ${entry.personName} covered it, nothing owed'
      : '$bill · you would owe ${entry.personName} ${money(split.myShare)}';
}

/// Whether [entry] is any of the owner's business.
///
/// A group deliberately lets guests split things between themselves — two
/// people sharing a cab the owner was not on is a real entry that counts on the
/// shared page. It just never touches the owner's own books: their share is
/// zero, so accepting it writes nothing and `createSplitDebts` returns early.
/// Putting it in their inbox is a card whose only honest answer is Dismiss.
///
/// Pairwise entries always pass this — the Edge Function refuses to store one
/// that excludes the owner, because a two-person ledger cannot represent it.
bool entryInvolvesOwner(SharedEntry entry, {required String ownerName}) =>
    entry.payerName == ownerName || entry.shares.containsKey(ownerName);
