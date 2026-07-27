import 'package:flutter/foundation.dart';

@immutable
class CycleHistoryExpenseEntry {
  final String id;
  final String category;
  final String? description;
  final double amount;
  final DateTime date;

  const CycleHistoryExpenseEntry({
    required this.id,
    required this.category,
    this.description,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(),
    };
  }

  static CycleHistoryExpenseEntry fromJson(Map<dynamic, dynamic> json) {
    return CycleHistoryExpenseEntry(
      id: json['id'] as String,
      category: json['category'] as String? ?? 'Other',
      description: json['description'] as String?,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
    );
  }
}

@immutable
class CycleHistorySnapshot {
  final String id;
  final String userId;
  final DateTime cycleStartDate;
  final DateTime cycleEndDate;
  final DateTime archivedAt;
  final double totalExpenses;
  final double cycleBudget;
  final double cycleSalary;
  final Map<String, double> categoryBreakdown;
  final List<CycleHistoryExpenseEntry> expenses;

  const CycleHistorySnapshot({
    required this.id,
    required this.userId,
    required this.cycleStartDate,
    required this.cycleEndDate,
    required this.archivedAt,
    required this.totalExpenses,
    required this.cycleBudget,
    required this.cycleSalary,
    required this.categoryBreakdown,
    required this.expenses,
  });

  int get transactionCount => expenses.length;
  double get salaryMinusBudget => cycleSalary - cycleBudget;
  double get budgetMinusExpenses => cycleBudget - totalExpenses;
  double get salaryMinusExpenses => cycleSalary - totalExpenses;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'cycleStartDate': cycleStartDate.toIso8601String(),
      'cycleEndDate': cycleEndDate.toIso8601String(),
      'archivedAt': archivedAt.toIso8601String(),
      'totalExpenses': totalExpenses,
      'cycleBudget': cycleBudget,
      'cycleSalary': cycleSalary,
      'categoryBreakdown': categoryBreakdown,
      'expenses': expenses.map((entry) => entry.toJson()).toList(),
    };
  }

  static CycleHistorySnapshot fromJson(Map<dynamic, dynamic> json) {
    final categoryBreakdownRaw =
        json['categoryBreakdown'] as Map<dynamic, dynamic>? ?? {};
    final expensesRaw = json['expenses'] as List<dynamic>? ?? [];

    return CycleHistorySnapshot(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      cycleStartDate: DateTime.parse(json['cycleStartDate'] as String),
      cycleEndDate: DateTime.parse(json['cycleEndDate'] as String),
      archivedAt: DateTime.parse(json['archivedAt'] as String),
      totalExpenses: (json['totalExpenses'] as num?)?.toDouble() ?? 0.0,
      cycleBudget: (json['cycleBudget'] as num?)?.toDouble() ?? 0.0,
      cycleSalary: (json['cycleSalary'] as num?)?.toDouble() ?? 0.0,
      categoryBreakdown: {
        for (final entry in categoryBreakdownRaw.entries)
          entry.key.toString(): (entry.value as num).toDouble(),
      },
      expenses: expensesRaw
          .whereType<Map>()
          .map(CycleHistoryExpenseEntry.fromJson)
          .toList(),
    );
  }
}
