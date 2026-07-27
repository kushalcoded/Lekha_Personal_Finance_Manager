import 'package:flutter/material.dart';

enum ReminderType {
  budgetWarning,
  overdueReceivable,
  upcomingRecurringExpense,
  monthlyBudgetPrompt,
}

enum ReminderSeverity { info, warning, danger, success }

@immutable
class AppReminder {
  final String id;
  final ReminderType type;
  final String title;
  final String message;
  final DateTime dueAt;
  final ReminderSeverity severity;

  const AppReminder({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.dueAt,
    required this.severity,
  });
}
