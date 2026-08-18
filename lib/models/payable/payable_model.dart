import 'package:flutter/foundation.dart';

enum PayableStatus { pending, partial, paid }

@immutable
class PayableSettlement {
  final String id;
  final double amount;
  final double remainingAfter;
  final String? note;
  final DateTime settledAt;

  const PayableSettlement({
    required this.id,
    required this.amount,
    required this.remainingAfter,
    this.note,
    required this.settledAt,
  });

  PayableSettlement copyWith({
    String? id,
    double? amount,
    double? remainingAfter,
    String? note,
    DateTime? settledAt,
  }) {
    return PayableSettlement(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      remainingAfter: remainingAfter ?? this.remainingAfter,
      note: note ?? this.note,
      settledAt: settledAt ?? this.settledAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'remainingAfter': remainingAfter,
      'note': note,
      'settledAt': settledAt.toIso8601String(),
    };
  }

  static PayableSettlement fromJson(Map<dynamic, dynamic> json) {
    return PayableSettlement(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      remainingAfter: (json['remainingAfter'] as num).toDouble(),
      note: json['note'] as String?,
      settledAt: DateTime.parse(json['settledAt'] as String),
    );
  }
}

@immutable
class Payable {
  final String id;
  final String userId;
  final String toPerson;
  final double amount;
  final double remainingAmount;
  final String category;
  final String? notes;

  /// The expense whose split created this, so the split can be edited later.
  final String? sourceExpenseId;

  /// Everyone else on the bill and their share, when a friend paid — the payer
  /// included, you excluded (your share is [amount]). Empty on a plain payable
  /// and on every split recorded before this was stored, which is why the edit
  /// sheet still has a read-only path.
  final Map<String, double> participants;
  final DateTime createdAt;
  final DateTime dueDate;
  final PayableStatus status;
  final List<PayableSettlement> settlements;
  final DateTime? updatedAt;

  const Payable({
    required this.id,
    required this.userId,
    required this.toPerson,
    required this.amount,
    required this.remainingAmount,
    required this.category,
    this.notes,
    this.sourceExpenseId,
    this.participants = const {},
    required this.createdAt,
    required this.dueDate,
    required this.status,
    required this.settlements,
    this.updatedAt,
  });

  Payable copyWith({
    String? id,
    String? userId,
    String? toPerson,
    double? amount,
    double? remainingAmount,
    String? category,
    String? notes,
    String? sourceExpenseId,
    Map<String, double>? participants,
    DateTime? createdAt,
    DateTime? dueDate,
    PayableStatus? status,
    List<PayableSettlement>? settlements,
    DateTime? updatedAt,
  }) {
    return Payable(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      toPerson: toPerson ?? this.toPerson,
      amount: amount ?? this.amount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      sourceExpenseId: sourceExpenseId ?? this.sourceExpenseId,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      settlements: settlements ?? this.settlements,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'toPerson': toPerson,
      'amount': amount,
      'remainingAmount': remainingAmount,
      'category': category,
      'notes': notes,
      'sourceExpenseId': sourceExpenseId,
      'participants': participants,
      'createdAt': createdAt.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'status': status.name,
      'settlements': settlements.map((entry) => entry.toJson()).toList(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static Payable fromJson(Map<dynamic, dynamic> json) {
    final settlementsRaw = json['settlements'] as List<dynamic>? ?? [];
    return Payable(
      id: json['id'] as String,
      userId: json['userId'] as String,
      toPerson: json['toPerson'] as String,
      amount: (json['amount'] as num).toDouble(),
      remainingAmount: (json['remainingAmount'] as num).toDouble(),
      category: json['category'] as String? ?? 'Miscellaneous',
      notes: json['notes'] as String?,
      sourceExpenseId: json['sourceExpenseId'] as String?,
      participants: {
        for (final entry in (json['participants'] as Map? ?? {}).entries)
          if ((entry.value as num?) != null)
            entry.key.toString(): (entry.value as num).toDouble(),
      },
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueDate: DateTime.parse(json['dueDate'] as String),
      status: PayableStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => PayableStatus.pending,
      ),
      settlements: settlementsRaw
          .whereType<Map>()
          .map((entry) => PayableSettlement.fromJson(entry))
          .toList(),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );
  }
}
