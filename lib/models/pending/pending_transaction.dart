/// A debit detected from an SMS, awaiting the user's decision to add or dismiss.
enum PendingStatus { pending, added, dismissed }

class PendingTransaction {
  /// Stable id — the SMS hash, so the same message never doubles up.
  final String id;
  final double amount;

  /// From the SMS's own timestamp (we don't parse a date out of the body).
  final DateTime dateTime;
  final String rawBody;
  final PendingStatus status;
  final String? linkedExpenseId;
  final DateTime createdAt;

  const PendingTransaction({
    required this.id,
    required this.amount,
    required this.dateTime,
    required this.rawBody,
    this.status = PendingStatus.pending,
    this.linkedExpenseId,
    required this.createdAt,
  });

  PendingTransaction copyWith({
    PendingStatus? status,
    String? linkedExpenseId,
  }) {
    return PendingTransaction(
      id: id,
      amount: amount,
      dateTime: dateTime,
      rawBody: rawBody,
      status: status ?? this.status,
      linkedExpenseId: linkedExpenseId ?? this.linkedExpenseId,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'dateTime': dateTime.toIso8601String(),
    'rawBody': rawBody,
    'status': status.name,
    'linkedExpenseId': linkedExpenseId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingTransaction.fromJson(Map<dynamic, dynamic> json) {
    return PendingTransaction(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      dateTime: DateTime.parse(json['dateTime'] as String),
      rawBody: json['rawBody'] as String? ?? '',
      status: PendingStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => PendingStatus.pending,
      ),
      linkedExpenseId: json['linkedExpenseId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
