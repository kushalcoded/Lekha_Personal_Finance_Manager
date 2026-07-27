import 'package:hive/hive.dart';

part 'expense_hive_model.g.dart';

@HiveType(typeId: 0)
class ExpenseHive {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final double amount;

  @HiveField(3)
  final String category;

  @HiveField(4)
  final String? description;

  @HiveField(5)
  final DateTime date;

  @HiveField(10)
  final String? paymentMethod;

  @HiveField(8)
  final String? recurringTemplateId;

  @HiveField(9)
  final DateTime? recurringDueDate;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  final DateTime? updatedAt;

  ExpenseHive({
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

  ExpenseHive copyWith({
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
    return ExpenseHive(
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
