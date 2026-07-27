/// Bill-splitting maths. Pure — no storage, no UI — so it can be unit tested.
///
/// The split is always among **you + [people]**. Who actually paid decides the
/// direction afterwards (you paid → they owe you; a friend paid → you owe them),
/// but the share maths is the same either way.
library;

enum SplitMode { equal, exact }

/// One participant's share of the bill.
class SplitShare {
  final String person;
  final double amount;

  const SplitShare(this.person, this.amount);
}

class SplitResult {
  /// What you actually consumed — this becomes the expense amount.
  final double myShare;

  /// Everyone else's shares.
  final List<SplitShare> others;

  const SplitResult({required this.myShare, required this.others});

  double get othersTotal =>
      others.fold(0.0, (sum, share) => sum + share.amount);
}

/// How a bill is being split — what the split sheet hands back to the form.
/// Shares aren't stored here: they're recomputed from the current total so
/// editing the amount afterwards stays correct.
class SplitConfig {
  /// The other participants (you are always implicitly included).
  final List<String> people;

  /// Who paid — null means you. Otherwise a name from [people].
  final String? paidBy;
  final SplitMode mode;

  /// Per-person amounts when [mode] is [SplitMode.exact].
  final Map<String, double> exact;

  const SplitConfig({
    this.people = const [],
    this.paidBy,
    this.mode = SplitMode.equal,
    this.exact = const {},
  });

  bool get isActive => people.isNotEmpty;
  bool get paidByMe => paidBy == null;

  SplitConfig copyWith({
    List<String>? people,
    String? paidBy,
    bool clearPaidBy = false,
    SplitMode? mode,
    Map<String, double>? exact,
  }) {
    return SplitConfig(
      people: people ?? this.people,
      paidBy: clearPaidBy ? null : (paidBy ?? this.paidBy),
      mode: mode ?? this.mode,
      exact: exact ?? this.exact,
    );
  }
}

double _round2(double value) => (value * 100).round() / 100;

/// Split [total] among you + [people].
///
/// - [SplitMode.equal]: everyone pays the same; any rounding remainder lands on
///   you (₹1000 ÷ 3 → they pay ₹333.33 each, you take ₹333.34) so the shares
///   always add back up to exactly [total].
/// - [SplitMode.exact]: [exactAmounts] gives each other person's share and your
///   share is whatever is left.
SplitResult computeSplit({
  required double total,
  required List<String> people,
  SplitMode mode = SplitMode.equal,
  Map<String, double> exactAmounts = const {},
}) {
  if (people.isEmpty) {
    return SplitResult(myShare: _round2(total), others: const []);
  }

  if (mode == SplitMode.exact) {
    final others = people
        .map((p) => SplitShare(p, _round2(exactAmounts[p] ?? 0)))
        .toList();
    final assigned = others.fold(0.0, (sum, s) => sum + s.amount);
    return SplitResult(myShare: _round2(total - assigned), others: others);
  }

  final per = _round2(total / (people.length + 1));
  final others = people.map((p) => SplitShare(p, per)).toList();
  final assigned = per * people.length;
  return SplitResult(myShare: _round2(total - assigned), others: others);
}

/// Why a split can't be saved, or null when it's fine.
String? validateSplit(double total, SplitResult result) {
  if (total <= 0) return 'Enter an amount first';
  if (result.others.any((s) => s.amount < 0)) {
    return 'Shares cannot be negative';
  }
  if (result.othersTotal > total + 0.01) {
    return 'Shares add up to more than the total';
  }
  if (result.myShare < -0.01) return 'Shares add up to more than the total';
  return null;
}
