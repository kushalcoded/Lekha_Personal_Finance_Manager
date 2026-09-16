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

// The budget the user sets is the everyday allowance itself — food, fuel,
// shopping, the part of spending they decide about week to week. Rent and
// bills are tracked and shown, but never subtracted from it: an allowance
// derived by arithmetic from a bigger number was a figure nobody had typed and
// nobody recognised.
//
// So there is no allowance function here any more. `budget - everydaySpent` is
// the whole of it, and it lives in budgetMetricsProvider.
