import 'package:flutter/foundation.dart';

/// Expense model for transaction tracking
@immutable
class Expense {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final String? description;
  final DateTime date;

  /// How it was paid (GPay, Cash...). Null on records saved before this
  /// was stored — callers fall back to inferring it from [description].
  final String? paymentMethod;
  final String? recurringTemplateId;
  final DateTime? recurringDueDate;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Expense({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    this.description,
    required this.date,
    this.paymentMethod,
    this.recurringTemplateId,
    this.recurringDueDate,
    required this.createdAt,
    this.updatedAt,
  });

  Expense copyWith({
    String? id,
    String? userId,
    double? amount,
    String? category,
    String? description,
    DateTime? date,
    String? paymentMethod,
    String? recurringTemplateId,
    DateTime? recurringDueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      date: date ?? this.date,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      recurringTemplateId: recurringTemplateId ?? this.recurringTemplateId,
      recurringDueDate: recurringDueDate ?? this.recurringDueDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
