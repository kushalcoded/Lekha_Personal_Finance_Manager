import '../../../models/expense/expense_model.dart';

class ExpenseGroup {
  final DateTime date;
  final List<Expense> expenses;
  final double total;

  const ExpenseGroup({
    required this.date,
    required this.expenses,
    required this.total,
  });
}

class ExpenseStats {
  /// Money consumed by the rows on screen. Investments, card-bill payments
  /// and income are in the list but not in here — the header says "spent",
  /// and it has to mean the same thing it means on Home.
  final double total;
  final double monthly;
  final int transactionCount;
  final String? topCategory;
  final double topCategoryTotal;

  /// Money that moved without being spent. Shown as its own line so the
  /// difference between this header and the rows under it is never a mystery.
  final double moved;

  const ExpenseStats({
    required this.total,
    required this.monthly,
    required this.transactionCount,
    required this.topCategory,
    required this.topCategoryTotal,
    this.moved = 0,
  });
}
