import 'tx_source.dart';

enum TxType { income, expense, transfer }

/// A single money movement.
///
/// [amount] is always stored as a **positive** number in đồng; direction lives
/// in [type]. That keeps aggregation queries (`SUM(amount) WHERE type = ...`)
/// trivial and removes a whole class of sign bugs.
class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.occurredAt,
    this.description = '',
    this.counterparty,
    this.categoryId,
    this.source = TxSource.manual,
    this.accountId,
    this.referenceNumber,
    this.rawText,
    this.createdAt,
    this.isPendingReview = false,
  });

  /// Unsaved drafts (before insert) carry the sentinel id [draftId].
  static const int draftId = -1;

  final int id;
  final TxType type;
  final int amount;
  final DateTime occurredAt;

  /// Short merchant label, e.g. "Highlands Coffee".
  final String description;

  /// Who the money went to / came from, when the bank tells us.
  final String? counterparty;

  final String? categoryId;
  final TxSource source;
  final String? accountId;

  /// Bank reference code — the natural key for de-duplicating syncs.
  final String? referenceNumber;

  /// Verbatim SMS / notification body, kept for auditing a bad parse.
  final String? rawText;

  final DateTime? createdAt;

  /// True when the parser could not confidently categorise the row, so the
  /// overview nudges the user to review it.
  final bool isPendingReview;

  bool get isIncome => type == TxType.income;
  bool get isExpense => type == TxType.expense;

  /// Signed value, useful for sorting and rolling sums.
  int get signedAmount => switch (type) {
        TxType.income => amount,
        TxType.expense => -amount,
        TxType.transfer => 0,
      };

  Transaction copyWith({
    int? id,
    TxType? type,
    int? amount,
    DateTime? occurredAt,
    String? description,
    String? counterparty,
    Object? categoryId = _unset,
    TxSource? source,
    String? accountId,
    String? referenceNumber,
    String? rawText,
    DateTime? createdAt,
    bool? isPendingReview,
  }) {
    return Transaction(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      occurredAt: occurredAt ?? this.occurredAt,
      description: description ?? this.description,
      counterparty: counterparty ?? this.counterparty,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      source: source ?? this.source,
      accountId: accountId ?? this.accountId,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      rawText: rawText ?? this.rawText,
      createdAt: createdAt ?? this.createdAt,
      isPendingReview: isPendingReview ?? this.isPendingReview,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != draftId) 'id': id,
      'type': type.name,
      'amount': amount,
      'occurred_at': occurredAt.millisecondsSinceEpoch,
      'description': description,
      'counterparty': counterparty,
      'category_id': categoryId,
      'source': source.storageKey,
      'account_id': accountId,
      'reference_number': referenceNumber,
      'raw_text': rawText,
      'created_at':
          (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
      'pending_review': isPendingReview ? 1 : 0,
    };
  }

  static Transaction fromMap(Map<String, Object?> map) {
    return Transaction(
      id: (map['id'] as num?)?.toInt() ?? draftId,
      type: _typeFromKey(map['type'] as String?),
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        (map['occurred_at'] as num?)?.toInt() ?? 0,
      ),
      description: (map['description'] as String?) ?? '',
      counterparty: map['counterparty'] as String?,
      categoryId: map['category_id'] as String?,
      source: TxSource.fromKey(map['source'] as String?),
      accountId: map['account_id'] as String?,
      referenceNumber: map['reference_number'] as String?,
      rawText: map['raw_text'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['created_at']! as num).toInt(),
            ),
      isPendingReview: ((map['pending_review'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  static TxType _typeFromKey(String? key) {
    return switch (key) {
      'income' => TxType.income,
      'transfer' => TxType.transfer,
      _ => TxType.expense,
    };
  }

  /// Two rows are the same event when they share a bank reference, or —
  /// falling back for banks that omit one — same amount, direction and an
  /// occurrence within the same minute.
  bool looksSameAs(Transaction other) {
    if (id != draftId && id == other.id) return true;
    if (referenceNumber != null &&
        other.referenceNumber != null &&
        referenceNumber == other.referenceNumber) {
      return true;
    }
    if (amount != other.amount || type != other.type) return false;
    final int gap =
        occurredAt.difference(other.occurredAt).inSeconds.abs();
    return gap <= 60;
  }

  @override
  String toString() =>
      'Transaction($id, ${type.name}, $amount, "$description")';
}

const Object _unset = Object();
