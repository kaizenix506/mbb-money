import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Mapping of supported category icons using const IconData to keep tree-shaking 100% happy!
const Map<String, IconData> categoryIconMap = {
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'transport': Icons.directions_car_filled_rounded,
  'shopping': Icons.shopping_bag_rounded,
  'bills': Icons.receipt_long_rounded,
  'health': Icons.favorite_rounded,
  'entertainment': Icons.sports_esports_rounded,
  'education': Icons.menu_book_rounded,
  'other': Icons.more_horiz_rounded,
  'flight': Icons.flight_takeoff_rounded,
  'pet': Icons.pets_rounded,
  'sport': Icons.sports_soccer_rounded,
  'music': Icons.music_note_rounded,
  'gift': Icons.card_giftcard_rounded,
};

/// Represents a financial category with liquid glass tint and icon.
class CategoryItem {
  const CategoryItem({
    required this.id,
    required this.label,
    required this.iconKey,
    required this.colorValue,
    this.isCustom = false,
  });

  final String id;
  final String label;
  final String iconKey;
  final int colorValue;
  final bool isCustom;

  IconData get icon => categoryIconMap[iconKey] ?? Icons.category_rounded;
  Color get tint => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'iconKey': iconKey,
        'colorValue': colorValue,
        'isCustom': isCustom,
      };

  factory CategoryItem.fromJson(Map<String, dynamic> json) => CategoryItem(
        id: json['id'] as String,
        label: json['label'] as String,
        iconKey: (json['iconKey'] ?? 'other') as String,
        colorValue: json['colorValue'] as int,
        isCustom: json['isCustom'] as bool? ?? false,
      );
}

/// Global Category Store allowing user to dynamically add, edit, or remove expense categories.
class CategoryStore extends ChangeNotifier {
  CategoryStore() {
    _loadFromPrefs();
  }

  static const String _prefsKey = 'mbb.custom_categories.v2';

  // Default rich preset categories
  static final List<CategoryItem> _defaults = [
    const CategoryItem(
      id: 'food',
      label: 'Ăn uống',
      iconKey: 'food',
      colorValue: 0xFFFFB066,
    ),
    const CategoryItem(
      id: 'coffee',
      label: 'Cà phê',
      iconKey: 'coffee',
      colorValue: 0xFF00F0FF,
    ),
    const CategoryItem(
      id: 'transport',
      label: 'Đi lại',
      iconKey: 'transport',
      colorValue: 0xFF6CA3FF,
    ),
    const CategoryItem(
      id: 'shopping',
      label: 'Mua sắm',
      iconKey: 'shopping',
      colorValue: 0xFFFF0055,
    ),
    const CategoryItem(
      id: 'bills',
      label: 'Hóa đơn',
      iconKey: 'bills',
      colorValue: 0xFFB48CFF,
    ),
    const CategoryItem(
      id: 'health',
      label: 'Sức khỏe',
      iconKey: 'health',
      colorValue: 0xFFFF3366,
    ),
    const CategoryItem(
      id: 'entertainment',
      label: 'Giải trí',
      iconKey: 'entertainment',
      colorValue: 0xFFFFE600,
    ),
    const CategoryItem(
      id: 'education',
      label: 'Giáo dục',
      iconKey: 'education',
      colorValue: 0xFF39FF14,
    ),
    const CategoryItem(
      id: 'other',
      label: 'Khác',
      iconKey: 'other',
      colorValue: 0xFF8B9BB4,
    ),
  ];

  List<CategoryItem> _categories = List.from(_defaults);

  List<CategoryItem> get all => List.unmodifiable(_categories);

  CategoryItem findById(String? id) {
    if (id == null) return _categories.firstWhere((c) => c.id == 'other');
    return _categories.firstWhere(
      (c) => c.id == id,
      orElse: () => _categories.firstWhere((c) => c.id == 'other'),
    );
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final List list = jsonDecode(raw);
        _categories = list.map((item) => CategoryItem.fromJson(item as Map<String, dynamic>)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading custom categories: $e');
    }
  }

  Future<void> addCategory({
    required String label,
    required String iconKey,
    required Color color,
  }) async {
    final newId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    final item = CategoryItem(
      id: newId,
      label: label.trim(),
      iconKey: iconKey,
      colorValue: color.value,
      isCustom: true,
    );
    _categories.insert(_categories.length - 1, item); // Insert before 'other'
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> removeCategory(String id) async {
    if (id == 'other') return; // protect default
    _categories.removeWhere((c) => c.id == id);
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_categories.map((c) => c.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      debugPrint('Error saving custom categories: $e');
    }
  }
}
