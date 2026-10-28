/// Represents an item the user wants to buy with its expected and actual price.
class WishlistItem {
  const WishlistItem({
    required this.id,
    required this.title,
    required this.expectedPrice,
    this.actualPrice,
    this.isBought = false,
    this.boughtAt,
    required this.createdAt,
    this.notes,
  });

  final int id;
  final String title;
  final int expectedPrice;
  final int? actualPrice;
  final bool isBought;
  final DateTime? boughtAt;
  final DateTime createdAt;
  final String? notes;

  int get effectivePrice => (isBought && actualPrice != null && actualPrice! > 0)
      ? actualPrice!
      : expectedPrice;

  WishlistItem copyWith({
    int? id,
    String? title,
    int? expectedPrice,
    Object? actualPrice = _unset,
    bool? isBought,
    Object? boughtAt = _unset,
    DateTime? createdAt,
    Object? notes = _unset,
  }) {
    return WishlistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      expectedPrice: expectedPrice ?? this.expectedPrice,
      actualPrice: identical(actualPrice, _unset)
          ? this.actualPrice
          : actualPrice as int?,
      isBought: isBought ?? this.isBought,
      boughtAt: identical(boughtAt, _unset)
          ? this.boughtAt
          : boughtAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id > 0) 'id': id,
      'title': title,
      'expected_price': expectedPrice,
      'actual_price': actualPrice,
      'is_bought': isBought ? 1 : 0,
      'bought_at': boughtAt?.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'notes': notes,
    };
  }

  factory WishlistItem.fromMap(Map<String, Object?> map) {
    return WishlistItem(
      id: map['id'] as int,
      title: (map['title'] as String?) ?? '',
      expectedPrice: (map['expected_price'] as int?) ?? 0,
      actualPrice: map['actual_price'] as int?,
      isBought: ((map['is_bought'] as int?) ?? 0) == 1,
      boughtAt: map['bought_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['bought_at'] as int)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      notes: map['notes'] as String?,
    );
  }
}

const Object _unset = Object();
