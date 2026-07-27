import 'package:flutter/foundation.dart';

/// One partial (or full) repayment recorded against a receivable.
@immutable
class ReceivableSettlement {
  final String id;
  final double amount;
  final double remainingAfter;
  final String? note;
  final DateTime settledAt;

  const ReceivableSettlement({
    required this.id,
    required this.amount,
    required this.remainingAfter,
    this.note,
    required this.settledAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'remainingAfter': remainingAfter,
    'note': note,
    'settledAt': settledAt.toIso8601String(),
  };

  static ReceivableSettlement fromJson(Map<dynamic, dynamic> json) {
    return ReceivableSettlement(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      remainingAfter: (json['remainingAfter'] as num).toDouble(),
      note: json['note'] as String?,
      settledAt: DateTime.parse(json['settledAt'] as String),
    );
  }
}

/// Receivable model for tracking money owed to user.
@immutable
class Receivable {
  final String id;
  final String userId;
  final String fromPerson;
  final double amount;
  final String? description;
  final DateTime dueDate;
  final bool isPaid;

  /// The expense whose split created this, so the split can be edited later.
  final String? sourceExpenseId;

  /// What's still outstanding. Null on records saved before partial settlement
  /// existed — [remaining] falls back to the full [amount] for those.
  final double? remainingAmount;
  final List<ReceivableSettlement> settlements;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Receivable({
    required this.id,
    required this.userId,
    required this.fromPerson,
    required this.amount,
    this.description,
    required this.dueDate,
    required this.isPaid,
    this.sourceExpenseId,
    this.remainingAmount,
    this.settlements = const [],
    required this.createdAt,
    this.updatedAt,
  });

  /// Outstanding amount: 0 once fully paid, otherwise the remaining balance
  /// (or the full amount for legacy records with no [remainingAmount]).
  double get remaining => isPaid ? 0 : (remainingAmount ?? amount);

  bool get isPartiallyPaid => !isPaid && remaining > 0 && remaining < amount;

  Receivable copyWith({
    String? id,
    String? userId,
    String? fromPerson,
    double? amount,
    String? description,
    DateTime? dueDate,
    bool? isPaid,
    String? sourceExpenseId,
    double? remainingAmount,
    List<ReceivableSettlement>? settlements,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Receivable(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fromPerson: fromPerson ?? this.fromPerson,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      isPaid: isPaid ?? this.isPaid,
      sourceExpenseId: sourceExpenseId ?? this.sourceExpenseId,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      settlements: settlements ?? this.settlements,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
