import '../../../models/expense/expense_model.dart';

enum ExpenseWarningKind { none, duplicate, anomaly }

class ExpenseWarning {
  final ExpenseWarningKind kind;
  final String category;
  final double amount;
  final double typical; // category median (anomaly only)

  const ExpenseWarning({
    required this.kind,
    required this.category,
    required this.amount,
    this.typical = 0,
  });
}

/// Feature 5: flag a candidate expense as a likely duplicate (same category,
/// amount, and day already in the cycle) or an anomaly (far above the
/// category's usual spend this cycle). Pure so it stays trivially testable.
ExpenseWarning detectExpenseWarning({
  required double amount,
  required String category,
  required DateTime date,
  required List<Expense> cycleExpenses,
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

  return ExpenseWarning(
    kind: ExpenseWarningKind.none,
    category: category,
    amount: amount,
  );
}

/// Short "who and how" line for a detected SMS — "HDFC Bank · UPI" — built
/// from the sender words at the start of the body plus the channel keyword.
/// Falls back to a generic label so a row is never blank.
String smsSenderLabel(String rawBody) {
  final body = rawBody.trim();
  if (body.isEmpty) return 'Bank SMS';

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
