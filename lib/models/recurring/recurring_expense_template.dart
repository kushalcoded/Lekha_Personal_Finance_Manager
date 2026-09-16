import 'package:flutter/foundation.dart';

enum RecurringFrequency { daily, weekly, monthly, yearly }

extension RecurringFrequencyLabel on RecurringFrequency {
  String get label => name[0].toUpperCase() + name.substring(1);
}

@immutable
class RecurringExpenseTemplate {
  final String id;
  final String userId;
  final double amount;
  final String category;
  final String paymentMethod;
  final String? notes;
  final RecurringFrequency frequency;
  final DateTime nextDueDate;
  final bool isActive;
  final DateTime? lastGeneratedAt;
  final String? lastGeneratedExpenseId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Spread this bill's cost across this many cycles when budgeting.
  ///
  /// An annual insurance premium lands in one cycle and wrecks it, even though
  /// you knew about it all year. With 12 here, the budget holds back a twelfth
  /// each cycle and the real payment, when it comes, draws only that twelfth
  /// from the allowance. The expense itself is still recorded in full — this
  /// changes planning, never the record. 1 means no spreading.
  final int spreadOverCycles;

  /// What to set aside per cycle. Equal to [amount] unless spread.
  double get cycleShare =>
      spreadOverCycles > 1 ? amount / spreadOverCycles : amount;

  bool get isSpread => spreadOverCycles > 1;

  const RecurringExpenseTemplate({
    required this.id,
    required this.userId,
    required this.amount,
    required this.category,
    required this.paymentMethod,
    this.notes,
    required this.frequency,
    required this.nextDueDate,
    required this.isActive,
    this.lastGeneratedAt,
    this.lastGeneratedExpenseId,
    required this.createdAt,
    this.updatedAt,
    this.spreadOverCycles = 1,
  });

  RecurringExpenseTemplate copyWith({
    String? id,
    String? userId,
    double? amount,
    String? category,
    String? paymentMethod,
    String? notes,
    RecurringFrequency? frequency,
    DateTime? nextDueDate,
    bool? isActive,
    DateTime? lastGeneratedAt,
    String? lastGeneratedExpenseId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? spreadOverCycles,
  }) {
    return RecurringExpenseTemplate(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      frequency: frequency ?? this.frequency,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      isActive: isActive ?? this.isActive,
      lastGeneratedAt: lastGeneratedAt ?? this.lastGeneratedAt,
      lastGeneratedExpenseId:
          lastGeneratedExpenseId ?? this.lastGeneratedExpenseId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      spreadOverCycles: spreadOverCycles ?? this.spreadOverCycles,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'amount': amount,
      'category': category,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'frequency': frequency.name,
      'nextDueDate': nextDueDate.toIso8601String(),
      'isActive': isActive,
      'lastGeneratedAt': lastGeneratedAt?.toIso8601String(),
      'lastGeneratedExpenseId': lastGeneratedExpenseId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'spreadOverCycles': spreadOverCycles,
    };
  }

  static RecurringExpenseTemplate fromJson(Map<dynamic, dynamic> json) {
    return RecurringExpenseTemplate(
      id: json['id'] as String,
      userId: json['userId'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: json['category'] as String,
      paymentMethod: json['paymentMethod'] as String? ?? 'Cash',
      notes: json['notes'] as String?,
      frequency: RecurringFrequency.values.firstWhere(
        (value) => value.name == json['frequency'],
        orElse: () => RecurringFrequency.monthly,
      ),
      nextDueDate: DateTime.parse(json['nextDueDate'] as String),
      isActive: json['isActive'] as bool? ?? true,
      lastGeneratedAt: json['lastGeneratedAt'] == null
          ? null
          : DateTime.parse(json['lastGeneratedAt'] as String),
      lastGeneratedExpenseId: json['lastGeneratedExpenseId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      spreadOverCycles: (json['spreadOverCycles'] as num?)?.toInt() ?? 1,
    );
  }
}
