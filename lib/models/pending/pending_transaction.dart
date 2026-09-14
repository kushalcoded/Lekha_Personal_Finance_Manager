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

  /// Who the money went to — "Swiggy", "Kushal" — so the card says where you
  /// paid. Only kept while the card waits: it goes into the expense's note when
  /// added, and is cleared once the card is added or dismissed.
  final String? merchant;

  const PendingTransaction({
    required this.id,
    required this.amount,
    required this.dateTime,
    required this.rawBody,
    this.status = PendingStatus.pending,
    this.linkedExpenseId,
    required this.createdAt,
    this.provisional = false,
    this.merchant,
  });

  PendingTransaction copyWith({
    double? amount,
    DateTime? dateTime,
    PendingStatus? status,
    String? linkedExpenseId,
    bool? provisional,
    String? merchant,
    bool clearMerchant = false,
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
      merchant: clearMerchant ? null : (merchant ?? this.merchant),
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
    'merchant': merchant,
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
      merchant: cleanMerchant(json['merchant']),
    );
  }
}

/// A merchant name as the model or the server gave it, or null if there is
/// nothing usable. Trimmed, and never the literal strings a model writes for
/// "unknown".
String? cleanMerchant(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return null;
  const unknown = {'null', 'none', 'unknown', 'n/a', 'na', '-'};
  if (unknown.contains(value.toLowerCase())) return null;
  return value.length > 40 ? value.substring(0, 40).trim() : value;
}
