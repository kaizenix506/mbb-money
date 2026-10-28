import 'package:flutter/material.dart';

/// Static catalogue of spending categories.
///
/// Categories are seeded from code (not user data) so the auto-categoriser,
/// the icon set and the colour palette always agree. Phase 2 can move this
/// into SQLite once users can rename/add their own; the [id] strings must stay
/// stable because transactions reference them.
enum Category {
  food(
    id: 'food',
    label: 'Ăn uống',
    icon: Icons.restaurant_rounded,
    tint: Color(0xFFFF7700),
  ),
  drink(
    id: 'drink',
    label: 'Đồ uống',
    icon: Icons.local_drink_rounded,
    tint: Color(0xFF00F0FF),
  ),
  coffee(
    id: 'coffee',
    label: 'Cà phê',
    icon: Icons.local_cafe_rounded,
    tint: Color(0xFFFFB800),
  ),
  transport(
    id: 'transport',
    label: 'Đi lại',
    icon: Icons.directions_car_filled_rounded,
    tint: Color(0xFF2979FF),
  ),
  shopping(
    id: 'shopping',
    label: 'Mua sắm',
    icon: Icons.shopping_bag_rounded,
    tint: Color(0xFFFF007F),
  ),
  bills(
    id: 'bills',
    label: 'Hóa đơn',
    icon: Icons.receipt_long_rounded,
    tint: Color(0xFF9D00FF),
  ),
  health(
    id: 'health',
    label: 'Sức khỏe',
    icon: Icons.favorite_rounded,
    tint: Color(0xFFFF1744),
  ),
  entertainment(
    id: 'entertainment',
    label: 'Giải trí',
    icon: Icons.sports_esports_rounded,
    tint: Color(0xFFFFEA00),
  ),
  education(
    id: 'education',
    label: 'Giáo dục',
    icon: Icons.menu_book_rounded,
    tint: Color(0xFF00E676),
  ),
  family(
    id: 'family',
    label: 'Gia đình',
    icon: Icons.family_restroom_rounded,
    tint: Color(0xFFFF4081),
  ),
  salary(
    id: 'salary',
    label: 'Lương',
    icon: Icons.work_rounded,
    tint: Color(0xFF3DE8B0),
  ),
  transfer(
    id: 'transfer',
    label: 'Chuyển khoản',
    icon: Icons.swap_horiz_rounded,
    tint: Color(0xFF00B0FF),
  ),
  other(
    id: 'other',
    label: 'Khác',
    icon: Icons.more_horiz_rounded,
    tint: Color(0xFF78909C),
  );

  const Category({
    required this.id,
    required this.label,
    required this.icon,
    required this.tint,
  });

  /// Stable key stored in `transactions.category_id`.
  final String id;
  final String label;
  final IconData icon;

  /// Base hue used for the icon glyph; the tile background is derived from it.
  final Color tint;

  /// Categories that only make sense as income.
  bool get isIncomeOnly => this == Category.salary;

  static Category? byId(String? id) {
    if (id == null) return null;
    for (final Category c in Category.values) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Categories the user can pick when logging an expense.
  static List<Category> get expenseChoices => Category.values
      .where((Category c) => !c.isIncomeOnly)
      .toList(growable: false);

  /// Categories the user can pick when logging income.
  static List<Category> get incomeChoices => const <Category>[
        Category.salary,
        Category.transfer,
        Category.other,
      ];
}
