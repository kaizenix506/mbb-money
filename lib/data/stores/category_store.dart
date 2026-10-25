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

/// Global Category Store allowing user to dynamically add, edit, or remove
/// expense categories — including the built-in ones.
class CategoryStore extends ChangeNotifier {
  CategoryStore() {
    _loadFromPrefs();
  }

  static const String _prefsKey = 'mbb.custom_categories.v3';
  static const String _kFallbackId = 'other';

  /// Default rich preset categories.
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

  /// Built-ins are never dropped from this lookup so historical transactions
  /// still resolve their label after the user deletes the category.
  final Map<String, CategoryItem> _known = {
    for (final CategoryItem c in _defaults) c.id: c,
  };

  /// Categories the user explicitly deleted that ship with the app.
  final Set<String> _hiddenDefaultIds = <String>{};

  List<CategoryItem> get all => List.unmodifiable(_categories);

  /// Categories currently available for *new* transactions.
  List<CategoryItem> get selectable =>
      _categories.where((CategoryItem c) => c.id != _kFallbackId).toList();

  bool get canDeleteAny => _categories.length > 1;

  CategoryItem get fallback => _known[_kFallbackId] ?? _defaults.last;

  /// Resolves an id for display — including categories the user already
  /// deleted, so old rows keep their meaning.
  CategoryItem? resolve(String? id) {
    if (id == null) return null;
    for (final CategoryItem c in _categories) {
      if (c.id == id) return c;
    }
    return _known[id];
  }

  CategoryItem findById(String? id) => resolve(id) ?? fallback;

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;

        final List<dynamic> list = (decoded['items'] as List<dynamic>?) ?? <dynamic>[];
        if (list.isNotEmpty) {
          _categories = list
              .map((dynamic item) => CategoryItem.fromJson(item as Map<String, dynamic>))
              .toList();
        }

        final List<dynamic> hidden =
            (decoded['hiddenDefaults'] as List<dynamic>?) ?? <dynamic>[];
        _hiddenDefaultIds
          ..clear()
          ..addAll(hidden.map((dynamic e) => e.toString()));

        for (final CategoryItem c in _categories) {
          _known[c.id] = c;
        }
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
    final String newId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    final CategoryItem item = CategoryItem(
      id: newId,
      label: label.trim(),
      iconKey: iconKey,
      colorValue: color.value,
      isCustom: true,
    );
    // Insert before the 'other' bucket so it stays last.
    final int otherIdx = _categories.indexWhere((CategoryItem c) => c.id == _kFallbackId);
    if (otherIdx == -1) {
      _categories.add(item);
    } else {
      _categories.insert(otherIdx, item);
    }
    _known[newId] = item;
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> updateCategory(
    String id, {
    required String label,
    required String iconKey,
    required Color color,
  }) async {
    final int idx = _categories.indexWhere((CategoryItem c) => c.id == id);
    if (idx == -1) return;
    final CategoryItem updated = CategoryItem(
      id: id,
      label: label.trim(),
      iconKey: iconKey,
      colorValue: color.value,
      isCustom: _categories[idx].isCustom,
    );
    _categories[idx] = updated;
    _known[id] = updated;
    await _saveToPrefs();
    notifyListeners();
  }

  /// Removes a category. The caller is responsible for moving the existing
  /// transactions to [fallback] first (see TransactionStore).
  Future<void> removeCategory(String id) async {
    if (id == _kFallbackId) return; // the fallback bucket is permanent
    if (_categories.length <= 1) return;
    _categories.removeWhere((CategoryItem c) => c.id == id);
    if (!_known.containsKey(id) || _defaults.any((CategoryItem c) => c.id == id)) {
      _hiddenDefaultIds.add(id);
    }
    await _saveToPrefs();
    notifyListeners();
  }

  /// Restores a deleted built-in category.
  Future<void> restoreDefaults() async {
    _categories = List.from(_defaults);
    _hiddenDefaultIds.clear();
    _known
      ..clear()
      ..addAll(<String, CategoryItem>{for (final CategoryItem c in _defaults) c.id: c});
    await _saveToPrefs();
    notifyListeners();
  }

  bool get hasDeletedDefaults => _hiddenDefaultIds.isNotEmpty;

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded = jsonEncode(<String, dynamic>{
        'items': _categories.map((CategoryItem c) => c.toJson()).toList(),
        'hiddenDefaults': _hiddenDefaultIds.toList(),
      });
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      debugPrint('Error saving custom categories: $e');
    }
  }
}
