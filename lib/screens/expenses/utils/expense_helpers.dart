import '../../../models/expense/expense_model.dart';

enum ExpenseWarningKind { none, duplicate, anomaly, overBudget }

class ExpenseWarning {
  final ExpenseWarningKind kind;
  final String category;
  final double amount;
  final double typical; // category median (anomaly only)

  /// The category's limit for the cycle, and what this expense would take the
  /// total to — both zero unless [kind] is [ExpenseWarningKind.overBudget].
  final double budget;
  final double spentAfter;

  const ExpenseWarning({
    required this.kind,
    required this.category,
    required this.amount,
    this.typical = 0,
    this.budget = 0,
    this.spentAfter = 0,
  });
}

/// What a category has left this cycle. [limit] of 0 means uncapped.
class CategoryBudgetStatus {
  final double limit;
  final double spent;

  const CategoryBudgetStatus({required this.limit, required this.spent});

  bool get isCapped => limit > 0;
  double get remaining => limit - spent;
  bool get isOver => isCapped && spent > limit;

  /// Clamped so a wildly overspent category doesn't draw a bar past the card.
  double get fraction => isCapped ? (spent / limit).clamp(0.0, 1.0) : 0;
}

/// Spend so far in [category] this cycle, against its limit.
CategoryBudgetStatus categoryBudgetStatus({
  required String category,
  required Map<String, double> budgets,
  required List<Expense> cycleExpenses,
}) {
  var spent = 0.0;
  for (final e in cycleExpenses) {
    if (e.category == category) spent += e.amount;
  }
  return CategoryBudgetStatus(limit: budgets[category] ?? 0, spent: spent);
}

/// Feature 5: flag a candidate expense as a likely duplicate (same category,
/// amount, and day already in the cycle) or an anomaly (far above the
/// category's usual spend this cycle). Pure so it stays trivially testable.
ExpenseWarning detectExpenseWarning({
  required double amount,
  required String category,
  required DateTime date,
  required List<Expense> cycleExpenses,
  Map<String, double> categoryBudgets = const {},
}) {
  final sameDayDuplicate = cycleExpenses.any(
    (e) =>
        e.category == category &&
        e.amount == amount &&
        e.date.year == date.year &&
        e.date.month == date.month &&
        e.date.day == date.day,
  );
  if (sameDayDuplicate) {
    return ExpenseWarning(
      kind: ExpenseWarningKind.duplicate,
      category: category,
      amount: amount,
    );
  }

  final categoryAmounts =
      cycleExpenses
          .where((e) => e.category == category)
          .map((e) => e.amount)
          .toList()
        ..sort();
  // Need a few data points before "usual" means anything.
  if (categoryAmounts.length >= 3) {
    final median = categoryAmounts[categoryAmounts.length ~/ 2];
    if (median > 0 && amount > median * 3) {
      return ExpenseWarning(
        kind: ExpenseWarningKind.anomaly,
        category: category,
        amount: amount,
        typical: median,
      );
    }
  }

  // Last, deliberately: a duplicate or a mistyped amount is a mistake, and
  // saying so beats telling someone they've overspent on a number they never
  // meant to enter.
  final status = categoryBudgetStatus(
    category: category,
    budgets: categoryBudgets,
    cycleExpenses: cycleExpenses,
  );
  if (status.isCapped && status.spent + amount > status.limit) {
    return ExpenseWarning(
      kind: ExpenseWarningKind.overBudget,
      category: category,
      amount: amount,
      budget: status.limit,
      spentAfter: status.spent + amount,
    );
  }

  return ExpenseWarning(
    kind: ExpenseWarningKind.none,
    category: category,
    amount: amount,
  );
}

final _labelPattern = RegExp(
  r'^[^:\-—]{1,40} · (UPI|ATM|IMPS|NEFT|Card|Autopay)$',
);

/// Short "who and how" line for a detected SMS — "HDFC Bank · UPI" — built
/// from the sender words at the start of the body plus the channel keyword.
/// Falls back to a generic label so a row is never blank.
String smsSenderLabel(String rawBody) {
  final body = rawBody.trim();
  if (body.isEmpty) return 'Bank SMS';
  // Rows pulled from other devices carry a label, not a message — only the
  // label is ever uploaded. Labelling one again appended the channel a second
  // time, so a card read "SBI · ATM · ATM" after two syncs.
  if (_labelPattern.hasMatch(body)) return body;

  // Sender sits before the first ':' / '-' in nearly every bank template.
  var head = body.split(RegExp(r'[:\-—]')).first.trim();
  final words = head.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length > 3 || head.isEmpty) {
    head = words.take(2).join(' ');
  }
  if (head.isEmpty) head = 'Bank SMS';

  const channels = {
    'upi': 'UPI',
    'atm': 'ATM',
    'imps': 'IMPS',
    'neft': 'NEFT',
    'debit card': 'Card',
    'credit card': 'Card',
    'autopay': 'Autopay',
  };
  final lower = body.toLowerCase();
  for (final entry in channels.entries) {
    if (lower.contains(entry.key)) return '$head · ${entry.value}';
  }
  return head;
}

String? inferPaymentMethod(String? notes) {
  if (notes == null || notes.trim().isEmpty) {
    return null;
  }
  final text = notes.toLowerCase();
  if (text.contains('gpay')) {
    return 'GPay';
  }
  if (text.contains('phonepe')) {
    return 'PhonePe';
  }
  if (text.contains('paytm')) {
    return 'Paytm';
  }
  if (text.contains('bank') || text.contains('transfer')) {
    return 'Bank Transfer';
  }
  if (text.contains('card')) {
    return 'Card';
  }
  if (text.contains('cash')) {
    return 'Cash';
  }
  return null;
}

/// How an expense was paid: the field the user actually chose, falling back
/// to whatever the note implies (records written before paymentMethod became
/// a real field embedded it in the text). Null when neither knows.
///
/// Every surface must ask through here. When this rule was open-coded per
/// screen, the details pane inferred from the note alone and reported
/// "Not recorded" for expenses whose method was sitting right there in the
/// field — while the list beside it showed the method correctly.
String? expensePaymentMethod(Expense expense) {
  final stored = expense.paymentMethod?.trim();
  if (stored != null && stored.isNotEmpty) return stored;
  return inferPaymentMethod(expense.description);
}

/// Display label for [expensePaymentMethod], for surfaces that always show
/// a row and need words for "we don't know".
String formatPaymentMethod(Expense expense) =>
    expensePaymentMethod(expense) ?? 'Not recorded';

String formatNotes(String? notes) {
  final value = notes?.trim();
  if (value == null || value.isEmpty) {
    return 'No notes';
  }
  return value;
}
