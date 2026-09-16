import '../../models/category/category_kinds.dart';
import '../../models/category/expense_category.dart';
import '../../models/recurring/recurring_expense_template.dart';
import '../../screens/expenses/providers/recurring_expenses_providers.dart'
    show advanceDueDate;

/// A safety stop for the occurrence walk below: a daily template against a
/// cycle nobody has rolled in a year would otherwise loop for a long time.
const _maxOccurrences = 400;

/// What still has to leave this cycle for bills that aren't a choice.
///
/// Occurrences are counted forward from `nextDueDate`, which is by definition
/// "not generated yet" — the generator advances it past now — so a payment can
/// never be both spent and planned. That is why the caller **adds** this to
/// what has already been paid rather than taking the larger of the two.
///
/// There is no lower bound on purpose: a template whose due date slipped past
/// before the cycle even started is still money owed, and pretending otherwise
/// would quietly free up an allowance the user doesn't have.
double committedPlanned({
  required Iterable<RecurringExpenseTemplate> activeTemplates,
  required CategoryKinds kinds,
  required DateTime cycleEnd,
}) {
  var total = 0.0;
  for (final template in activeTemplates) {
    if (kinds.of(template.category) != CategoryKind.committed) continue;
    // A spread bill sets aside its share every cycle, whether or not it falls
    // due in this one — that is the entire point of spreading it.
    //
    // ponytail: one share per cycle, not an accrued balance. Set a yearly bill
    // up two months before it lands and the allowance behaves as if it were
    // fully covered. Track paid-vs-reserved per template if that ever bites.
    if (template.isSpread) {
      total += template.cycleShare;
      continue;
    }
    var due = template.nextDueDate;
    var seen = 0;
    while (due.isBefore(cycleEnd) && seen < _maxOccurrences) {
      total += template.amount;
      due = advanceDueDate(template.frequency, due);
      seen++;
    }
  }
  return total;
}

/// How a cycle's budget divides once bills are taken out of it.
///
/// [committedReserved] is money already gone plus money still to go, so the
/// everyday allowance is what is genuinely free to spend — not what is left
/// before the rent lands.
({
  double committedReserved,
  double everydayAllowance,
  double everydayLeft,
  bool isOverCommitted,
})
everydayAllowance({
  required double budget,
  required double committedSpent,
  required double committedPlanned,
  required double everydaySpent,
  double spreadPaid = 0,
}) {
  // [spreadPaid] is what actually left for spread bills this cycle. It is real
  // spending and stays in the totals, but the allowance already held back a
  // share for it in this cycle and every earlier one, so charging the whole
  // lump again here is what wrecking-the-month looked like.
  final reserved = (committedSpent - spreadPaid) + committedPlanned;
  // A paisa of tolerance, the same one the rest of the budget maths uses:
  // summing two-decimal amounts leaves float residue.
  final overCommitted = budget > 0 && reserved > budget + 0.005;
  final allowance = budget <= 0 ? 0.0 : (budget - reserved).clamp(0.0, budget);
  return (
    committedReserved: reserved,
    everydayAllowance: allowance,
    everydayLeft: budget <= 0 ? 0.0 : allowance - everydaySpent,
    isOverCommitted: overCommitted,
  );
}
