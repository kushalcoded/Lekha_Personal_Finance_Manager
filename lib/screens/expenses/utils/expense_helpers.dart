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

String formatPaymentMethod(String? notes) {
  return inferPaymentMethod(notes) ?? 'Not recorded';
}

String formatNotes(String? notes) {
  final value = notes?.trim();
  if (value == null || value.isEmpty) {
    return 'No notes';
  }
  return value;
}
