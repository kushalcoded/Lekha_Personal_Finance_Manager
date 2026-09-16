import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category/category_kinds.dart';
import '../../models/category/expense_category.dart';
import '../../models/expense/expense_model.dart';
import '../../screens/expenses/utils/expense_helpers.dart';
import '../../screens/settings/providers/settings_providers.dart';
import '../auth/auth_provider.dart';
import '../categories/category_providers.dart';
import '../storage/storage_providers.dart';
import 'payment_method_providers.dart';

/// A payment method the user marked as a credit card.
///
/// The statement and due days are only for framing — "this statement, due on
/// the 5th". The balance never needs them.
class CardConfig {
  final String method;
  final int? statementDay;
  final int? dueDay;

  const CardConfig({required this.method, this.statementDay, this.dueDay});

  bool get hasCycle => statementDay != null && dueDay != null;
}

final cardsProvider = Provider<List<CardConfig>>((ref) {
  // Rebuild when a method is renamed or removed — the card map is keyed by
  // name and PaymentMethodsNotifier carries it across.
  ref.watch(paymentMethodsProvider);
  final userId = ref.watch(currentUserIdProvider) ?? localUserId;
  final raw = ref.read(hiveServiceProvider).getCards(userId);
  return [
    for (final entry in raw.entries)
      CardConfig(
        method: entry.key,
        statementDay: entry.value['statementDay'],
        dueDay: entry.value['dueDay'],
      ),
  ]..sort((a, b) => a.method.toLowerCase().compareTo(b.method.toLowerCase()));
});

/// What is still owed on [method], across all time.
///
/// Purchases and the bill that settles them straddle cycles by construction,
/// so this must never be cycle-scoped — a card balance that reset on the 1st
/// of every month would simply be wrong.
///
/// A bill payment is a transfer-kind expense recorded against the card, so it
/// subtracts here and counts nowhere else.
double cardOutstanding(
  Iterable<Expense> all,
  String method,
  CategoryKinds kinds,
) {
  var owed = 0.0;
  for (final expense in all) {
    if (expensePaymentMethod(expense) != method) continue;
    if (kinds.of(expense.category) == CategoryKind.transfer) {
      owed -= expense.amount;
    } else if (kinds.spends(expense.category)) {
      owed += expense.amount;
    }
  }
  return owed;
}

final cardOutstandingProvider = Provider.family<double, String>((ref, method) {
  final userId = ref.watch(currentUserIdProvider) ?? localUserId;
  return cardOutstanding(
    ref.watch(expensesProvider).expenses.where((e) => e.userId == userId),
    method,
    ref.watch(categoryKindsProvider),
  );
});

/// The window the current statement covers, and when it has to be paid.
///
/// Reuses the salary-day arithmetic, which already clamps a 31st into short
/// months and is covered by its own tests — a card's statement day has exactly
/// the same month-end problem.
({DateTime periodStart, DateTime statementDate, DateTime dueDate})
cardStatementPeriod({
  required int statementDay,
  required int dueDay,
  required DateTime now,
}) {
  final statementDate = lastSalaryDayOnOrBefore(now, statementDay);
  final periodStart = lastSalaryDayOnOrBefore(
    statementDate.subtract(const Duration(days: 1)),
    statementDay,
  );
  return (
    periodStart: periodStart,
    statementDate: statementDate,
    dueDate: nextSalaryDayAfter(statementDate, dueDay),
  );
}

/// What the closed statement came to: purchases in [periodStart, statementDate).
double statementTotal(
  Iterable<Expense> all,
  String method,
  CategoryKinds kinds, {
  required DateTime periodStart,
  required DateTime statementDate,
}) {
  var total = 0.0;
  for (final expense in all) {
    if (expensePaymentMethod(expense) != method) continue;
    if (!kinds.spends(expense.category)) continue;
    if (expense.date.isBefore(periodStart)) continue;
    if (!expense.date.isBefore(statementDate)) continue;
    total += expense.amount;
  }
  return total;
}
