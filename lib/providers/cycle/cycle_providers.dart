import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/expense/expense_model.dart';
import '../../screens/settings/providers/settings_providers.dart';
import '../storage/storage_providers.dart';

/// Expenses belonging to the current salary cycle only (dated on or after the
/// current cycle start). Every user-facing surface — the expenses list, the
/// dashboard, and analytics — reads from this, so after a cycle reset the
/// previous cycle's data disappears from those views. History snapshots and
/// backups intentionally keep using the full [expensesProvider] list.
final cycleExpensesProvider = Provider<List<Expense>>((ref) {
  final expenses = ref.watch(expensesProvider).expenses;
  final cycleStart = ref.watch(cycleStartProvider);
  return expenses.where((e) => !e.date.isBefore(cycleStart)).toList();
});

/// Midnight on the first day of the current cycle — the single lower bound
/// every cycle-scoped figure shares.
final cycleStartProvider = Provider<DateTime>((ref) {
  final start = ref.watch(settingsProvider).currentCycleStartDate;
  return DateTime(start.year, start.month, start.day);
});

/// Where the current cycle is expected to end — exclusive.
///
/// Nothing stores a cycle end: a cycle ends when the user says their salary
/// landed. So this is the date it is *due* to roll, or a month out when no
/// salary day is set. Used for planning ahead ("what still has to be paid this
/// cycle"), never for filtering expenses — [cycleExpensesProvider] deliberately
/// has no upper bound.
final cycleEndProvider = Provider<DateTime>((ref) {
  final settings = ref.watch(settingsProvider);
  final start = ref.watch(cycleStartProvider);
  return settings.expectedCycleRollDate ??
      DateTime(start.year, start.month + 1, start.day);
});
