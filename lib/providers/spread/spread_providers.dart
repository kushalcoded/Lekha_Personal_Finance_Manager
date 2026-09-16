import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/expense/expense_model.dart';
import '../../screens/expenses/providers/recurring_expenses_providers.dart'
    show shiftByMonths;
import '../../services/storage/hive_service.dart';
import '../auth/auth_provider.dart';
import '../storage/storage_providers.dart';

/// For charts only: each spread expense becomes one slice a month, dated from
/// its own date forward.
///
/// A ₹12,000 premium covers a year, but it was paid on one day, so Insights
/// drew it as one spike — that month a blowout, the other eleven looking
/// cheaper than they were. Home, the budget and the expense list deliberately
/// do not use this: the record is still one payment of the full amount.
///
/// A slice only appears once its date has arrived. Every Insights window is a
/// lower bound only, so without that all twelve slices of a payment made today
/// would land in "this cycle" at once.
///
/// ponytail: a slice appears on its anniversary day, not on the 1st of its
/// month, so for a month's first few days its share is not counted yet. Anchor
/// slices to the month start if that ever confuses anyone.
Iterable<Expense> spreadForCharts(
  Iterable<Expense> expenses,
  Map<String, int> spread, {
  required DateTime now,
}) sync* {
  for (final expense in expenses) {
    final months = spread[expense.id] ?? 1;
    if (months <= 1) {
      yield expense;
      continue;
    }
    // Round each slice to the paisa and put what is left over on the last one,
    // so the slices always add back up to exactly what was paid.
    final slice = (expense.amount / months * 100).roundToDouble() / 100;
    for (var i = 0; i < months; i++) {
      // Shifted from the original date every time, never from the slice
      // before, so a payment on the 31st stays on the last day of each month.
      final date = shiftByMonths(expense.date, i);
      if (date.isAfter(now)) break;
      final isLast = i == months - 1;
      yield expense.copyWith(
        id: '${expense.id}$_sliceMarker$i',
        amount: isLast ? expense.amount - slice * (months - 1) : slice,
        date: date,
      );
    }
  }
}

const _sliceMarker = '#spread';

/// Whether [expense] is one month's share of a spread payment rather than a
/// real record. Lets Insights say so, since Home counts the whole payment.
bool isSpreadSlice(Expense expense) => expense.id.contains(_sliceMarker);

/// Which expenses are spread in Insights, and over how many months.
final spreadExpensesProvider =
    StateNotifierProvider<SpreadExpensesNotifier, Map<String, int>>((ref) {
      return SpreadExpensesNotifier(ref);
    });

class SpreadExpensesNotifier extends StateNotifier<Map<String, int>> {
  final Ref _ref;

  SpreadExpensesNotifier(this._ref) : super(const {}) {
    state = _hive.getSpreadExpenses(_userId);
  }

  HiveService get _hive => _ref.read(hiveServiceProvider);
  String get _userId => _ref.read(currentUserIdProvider) ?? localUserId;

  /// One month, or fewer, means "not spread" and removes the entry.
  ///
  /// ponytail: the whole map is one settings key, so two devices spreading
  /// different expenses at the same moment would keep only one of the two.
  /// Move this to a field on Expense if that ever happens.
  Future<void> set(String expenseId, int months) async {
    if ((state[expenseId] ?? 1) == months) return;
    final next = Map<String, int>.from(state);
    if (months > 1) {
      next[expenseId] = months;
    } else {
      next.remove(expenseId);
    }
    state = next;
    await _hive.saveSpreadExpenses(_userId, next);
  }

  /// Re-read after a sync pull or a restore replaces the settings map.
  void refresh() => state = _hive.getSpreadExpenses(_userId);
}
