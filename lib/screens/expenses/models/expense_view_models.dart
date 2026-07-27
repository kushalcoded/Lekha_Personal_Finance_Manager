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
  final double total;
  final double monthly;
  final int transactionCount;
  final String? topCategory;
  final double topCategoryTotal;

  const ExpenseStats({
    required this.total,
    required this.monthly,
    required this.transactionCount,
    required this.topCategory,
    required this.topCategoryTotal,
  });
}
