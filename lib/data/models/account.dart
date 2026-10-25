/// A bank account or wallet the transactions belong to.
///
/// Phase 1 ships with a single MB account plus cash, seeded on first run.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.bankKey,
    this.last4,
    this.isDefault = false,
  });

  static const String cashId = 'cash';
  static const String mbId = 'mb-bank';

  /// Mirrors SePay's `bank_brand_name` so sync can map rows to accounts.
  static const String mbBankKey = 'MB';

  final String id;
  final String name;
  final String bankKey;
  final String? last4;
  final bool isDefault;

  /// "MB •• 1234"
  String get displayName =>
      last4 == null ? name : '$name •• $last4';

  static const List<Account> defaults = <Account>[
    Account(
      id: mbId,
      name: 'MB Bank',
      bankKey: mbBankKey,
      isDefault: true,
    ),
    Account(
      id: cashId,
      name: 'Tiền mặt',
      bankKey: 'CASH',
    ),
  ];
}
