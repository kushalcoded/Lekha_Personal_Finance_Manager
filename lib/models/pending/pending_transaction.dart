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

  /// Read locally by regex and shown immediately, with the model's verdict
  /// still outstanding. Cleared once AI has confirmed or corrected the row —
  /// the card is real either way, this only marks it as not yet double-checked.
  final bool provisional;

  const PendingTransaction({
    required this.id,
    required this.amount,
    required this.dateTime,
    required this.rawBody,
    this.status = PendingStatus.pending,
    this.linkedExpenseId,
    required this.createdAt,
    this.provisional = false,
  });

  PendingTransaction copyWith({
    double? amount,
    DateTime? dateTime,
    PendingStatus? status,
    String? linkedExpenseId,
    bool? provisional,
  }) {
    return PendingTransaction(
      id: id,
      amount: amount ?? this.amount,
      dateTime: dateTime ?? this.dateTime,
      rawBody: rawBody,
      status: status ?? this.status,
      linkedExpenseId: linkedExpenseId ?? this.linkedExpenseId,
      createdAt: createdAt,
      provisional: provisional ?? this.provisional,
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
    'provisional': provisional,
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
      // Absent on rows written before local-first parsing — those were all
      // AI-parsed, so they're already confirmed.
      provisional: json['provisional'] as bool? ?? false,
    );
  }
}
