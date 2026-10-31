import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/transaction_dao.dart';

/// Mapping of supported category icons using const IconData to keep tree-shaking 100% happy!
const Map<String, IconData> categoryIconMap = {
  'food': Icons.restaurant_rounded,
  'drink': Icons.local_drink_rounded,
  'coffee': Icons.local_cafe_rounded,
  'transport': Icons.directions_car_filled_rounded,
  'shopping': Icons.shopping_bag_rounded,
  'bills': Icons.receipt_long_rounded,
  'health': Icons.favorite_rounded,
  'entertainment': Icons.sports_esports_rounded,
  'education': Icons.menu_book_rounded,
  'family': Icons.family_restroom_rounded,
  'other': Icons.more_horiz_rounded,
  'flight': Icons.flight_takeoff_rounded,
  'pet': Icons.pets_rounded,
  'sport': Icons.sports_soccer_rounded,
  'music': Icons.music_note_rounded,
  'gift': Icons.card_giftcard_rounded,
  'tech': Icons.smart_toy_rounded,
  'beauty': Icons.spa_rounded,
  'work': Icons.work_rounded,
  'invest': Icons.trending_up_rounded,
};

/// Guesses an icon key from a Vietnamese category name.
///
/// Exists because the editor used to default every new category to `'food'`,
/// which is why *all* custom categories showed the same plate. Matching on the
/// label means a category is born with a sensible glyph even if the user never
/// opens the icon picker.
///
/// Order matters: more specific words come first so "trà sữa" hits `drink`
/// before the generic "ăn" rule can claim it.
String guessIconKey(String label) {
  final String s = label.toLowerCase();

  const List<({String key, List<String> words})> rules =
      <({String key, List<String> words})>[
    (key: 'coffee', words: <String>['cà phê', 'cafe', 'coffee', 'trà sữa', 'trà']),
    (key: 'drink', words: <String>['nước', 'sinh tố', 'sữa', 'bia', 'rượu', 'giải khát']),
    // Transport must sit above food: "xăng xe" contains "ăn" (x-ă-n-g),
    // so the food rule would otherwise claim every fuel purchase.
    (key: 'transport', words: <String>['xăng', 'xe', 'grab', 'taxi', 'đi lại', 'di chuyển', 'chuyển', 'vé', 'tàu']),
    (key: 'beauty', words: <String>['skin', 'care', 'skincare', 'mỹ phẩm', 'spa', 'làm đẹp', 'son', 'phấn']),
    (key: 'tech', words: <String>['ai', 'gpt', 'chatgpt', 'tool', 'phần mềm', 'tech', 'công nghệ', 'software', 'bot']),
    (key: 'flight', words: <String>['du lịch', 'máy bay', 'khách sạn', 'resort', 'phượt']),
    (key: 'food', words: <String>['ăn', 'cơm', 'phở', 'bún', 'cháo', 'bánh', 'quán', 'nhậu']),
    (key: 'shopping', words: <String>['mua', 'shop', 'quần', 'áo', 'giày', 'đồ']),
    (key: 'bills', words: <String>['điện', 'nước sinh', 'mạng', 'internet', 'hoá đơn', 'hóa đơn', 'điện thoại', 'cước']),
    (key: 'health', words: <String>['thuốc', 'khám', 'bệnh', 'sức khoẻ', 'sức khỏe', 'gym', 'y tế']),
    (key: 'entertainment', words: <String>['game', 'phim', 'giải trí', 'karaoke', 'netflix']),
    (key: 'education', words: <String>['học', 'sách', 'trường', 'khoá', 'khóa', 'giáo dục']),
    (key: 'family', words: <String>['gia đình', 'bố', 'mẹ', 'con', 'vợ', 'chồng']),
    (key: 'pet', words: <String>['mèo', 'chó', 'thú cưng', 'pet']),
    (key: 'sport', words: <String>['thể thao', 'bóng', 'chạy', 'bơi', 'sport']),
    (key: 'music', words: <String>['nhạc', 'music', 'spotify']),
    (key: 'gift', words: <String>['quà', 'tặng', 'gift', 'cưới', 'sinh nhật']),
  ];

  for (final ({String key, List<String> words}) rule in rules) {
    for (final String w in rule.words) {
      if (s.contains(w)) return rule.key;
    }
  }
  // A name we cannot read still deserves a neutral glyph rather than a plate.
  return 'other';
}

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
  CategoryStore({TransactionDao? dao}) : _dao = dao {
    _loadFromPrefs();
  }

  TransactionDao? _dao;

  void attachDao(TransactionDao dao) {
    _dao = dao;
  }

  Future<void> init({TransactionDao? dao}) async {
    if (dao != null) _dao = dao;
    await _loadFromPrefs();
  }

  static const String _prefsKey = 'mbb.custom_categories.v4';
  static const String _kFallbackId = 'other';

  /// Vibrant Cyberpunk neon palette where every color is distinct and high-contrast.
  static const List<int> neonPalette = <int>[
    0xFF00E5FF, // Cyber Cyan
    0xFFFF5722, // Neon Orange
    0xFFA855F7, // Neon Purple / Violet
    0xFF10B981, // Emerald Green
    0xFFEC4899, // Hot Pink / Magenta
    0xFFFACC15, // Cyber Yellow
    0xFF3B82F6, // Electric Royal Blue
    0xFFD97706, // Amber Caramel
    0xFF00F5D4, // Turquoise Mint
    0xFFFB7185, // Coral Rose
    0xFF6366F1, // Indigo Neon
    0xFFEF4444, // Ruby Red
    0xFF84CC16, // Lime Green
    0xFFF43F5E, // Bright Rose
    0xFF06B6D4, // Deep Sky Cyan
    0xFFD946EF, // Fuchsia Orchid
    0xFFF59E0B, // Honey Gold
    0xFF8B5CF6, // Bright Lavender
  ];

  /// Default rich preset categories.
  static final List<CategoryItem> _defaults = [
    const CategoryItem(
      id: 'food',
      label: 'Ăn uống',
      iconKey: 'food',
      colorValue: 0xFFFF5722, // Đỏ cam
    ),
    const CategoryItem(
      id: 'drink',
      label: 'Đồ uống',
      iconKey: 'drink',
      colorValue: 0xFF00B0FF, // Xanh lơ điện
    ),
    const CategoryItem(
      id: 'coffee',
      label: 'Cà phê',
      iconKey: 'coffee',
      colorValue: 0xFFD97706, // Nâu caramel hổ phách
    ),
    const CategoryItem(
      id: 'transport',
      label: 'Đi lại',
      iconKey: 'transport',
      colorValue: 0xFF6366F1, // Tím lam Indigo
    ),
    const CategoryItem(
      id: 'shopping',
      label: 'Mua sắm',
      iconKey: 'shopping',
      colorValue: 0xFFEC4899, // Hồng cánh sen Magenta
    ),
    const CategoryItem(
      id: 'bills',
      label: 'Hóa đơn',
      iconKey: 'bills',
      colorValue: 0xFFA855F7, // Tím thạch anh
    ),
    const CategoryItem(
      id: 'health',
      label: 'Sức khỏe',
      iconKey: 'health',
      colorValue: 0xFFEF4444, // Đỏ Ruby
    ),
    const CategoryItem(
      id: 'entertainment',
      label: 'Giải trí',
      iconKey: 'entertainment',
      colorValue: 0xFFFACC15, // Vàng chanh Cyber
    ),
    const CategoryItem(
      id: 'education',
      label: 'Giáo dục',
      iconKey: 'education',
      colorValue: 0xFF10B981, // Xanh ngọc lục bảo
    ),
    const CategoryItem(
      id: 'family',
      label: 'Gia đình',
      iconKey: 'family',
      colorValue: 0xFFFB7185, // Hồng đào san hô
    ),
    const CategoryItem(
      id: 'other',
      label: 'Khác',
      iconKey: 'other',
      colorValue: 0xFF94A3B8, // Xám bạc titan
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

  /// Returns the next available vibrant neon color from [neonPalette]
  /// that is not currently claimed by any category in the store.
  Color nextAvailableColor() {
    final Set<int> used = _categories.map((CategoryItem c) => c.colorValue).toSet();
    for (final int cVal in neonPalette) {
      if (!used.contains(cVal)) {
        return Color(cVal);
      }
    }
    return Color(neonPalette[_categories.length % neonPalette.length]);
  }

  /// Enforces that every category has its own distinct, vibrant Cyberpunk color.
  /// If multiple categories have duplicate colors (e.g. custom categories all
  /// defaulted to cyan), this automatically re-assigns unique colors so each
  /// category stands out individually on charts and badges.
  bool _ensureDistinctColors() {
    final Set<int> used = <int>{};
    bool changed = false;
    final List<CategoryItem> updated = <CategoryItem>[];

    for (int i = 0; i < _categories.length; i++) {
      final CategoryItem c = _categories[i];
      if (!used.contains(c.colorValue)) {
        used.add(c.colorValue);
        updated.add(c);
      } else {
        // Duplicate color detected! Find next available vibrant color
        int newColorVal = c.colorValue;
        for (final int palVal in neonPalette) {
          if (!used.contains(palVal)) {
            newColorVal = palVal;
            break;
          }
        }
        used.add(newColorVal);
        final CategoryItem fixed = CategoryItem(
          id: c.id,
          label: c.label,
          iconKey: c.iconKey,
          colorValue: newColorVal,
          isCustom: c.isCustom,
        );
        updated.add(fixed);
        _known[c.id] = fixed;
        changed = true;
      }
    }

    if (changed) {
      _categories = updated;
    }
    return changed;
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? raw = prefs.getString(_prefsKey);
      raw ??= prefs.getString('mbb.custom_categories.v3');
      raw ??= prefs.getString('mbb.custom_categories.v2');
      raw ??= prefs.getString('mbb.custom_categories');

      // Also check SQLite permanent backup if prefs is empty
      if (raw == null && _dao != null) {
        raw = await _dao!.readInternal('mbb_custom_categories');
      }

      if (raw != null) {
        final dynamic decoded = jsonDecode(raw);
        List<dynamic> list = <dynamic>[];
        List<dynamic> hidden = <dynamic>[];

        if (decoded is Map<String, dynamic>) {
          list = (decoded['items'] as List<dynamic>?) ?? <dynamic>[];
          hidden = (decoded['hiddenDefaults'] as List<dynamic>?) ?? <dynamic>[];
        } else if (decoded is List) {
          list = decoded;
        }

        if (list.isNotEmpty) {
          _categories = list.map((dynamic item) {
            final c = CategoryItem.fromJson(item as Map<String, dynamic>);
            if (!c.isCustom) {
              final defaultMatch = _defaults.where((d) => d.id == c.id).firstOrNull;
              if (defaultMatch != null) {
                return CategoryItem(
                  id: c.id,
                  label: c.label,
                  iconKey: c.iconKey,
                  colorValue: defaultMatch.colorValue,
                  isCustom: false,
                );
              }
            }
            return c;
          }).toList();
        }

        _hiddenDefaultIds
          ..clear()
          ..addAll(hidden.map((dynamic e) => e.toString()));

        for (final CategoryItem c in _categories) {
          _known[c.id] = c;
        }
      }

      // Sync with database for orphan categories
      await _syncWithDatabase();

      // Enforce distinct color per category so no two categories share the same color
      final bool colorsChanged = _ensureDistinctColors();
      if (colorsChanged) {
        await _saveToPrefs();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading custom categories: $e');
    }
  }

  Future<void> _syncWithDatabase() async {
    if (_dao == null) return;
    try {
      final List<String> dbCatIds = await _dao!.distinctCategoryIds();
      bool addedAny = false;
      for (final String catId in dbCatIds) {
        if (!_known.containsKey(catId) && catId != _kFallbackId) {
          final String label = catId.startsWith('cat_') ? 'Danh mục tự tạo' : catId;
          final item = CategoryItem(
            id: catId,
            label: label,
            iconKey: guessIconKey(label),
            colorValue: nextAvailableColor().toARGB32(),
            isCustom: true,
          );
          final int otherIdx = _categories.indexWhere((CategoryItem c) => c.id == _kFallbackId);
          if (otherIdx == -1) {
            _categories.add(item);
          } else {
            _categories.insert(otherIdx, item);
          }
          _known[catId] = item;
          addedAny = true;
        }
      }
      if (addedAny) {
        await _saveToPrefs();
      } else {
        // Ensure SQLite backup is up to date
        final String encoded = jsonEncode(<String, dynamic>{
          'items': _categories.map((CategoryItem c) => c.toJson()).toList(),
          'hiddenDefaults': _hiddenDefaultIds.toList(),
        });
        await _dao!.writeInternal('mbb_custom_categories', encoded);
      }
    } catch (e) {
      debugPrint('Error syncing categories with database: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded = jsonEncode(<String, dynamic>{
        'items': _categories.map((CategoryItem c) => c.toJson()).toList(),
        'hiddenDefaults': _hiddenDefaultIds.toList(),
      });
      await prefs.setString(_prefsKey, encoded);
      if (_dao != null) {
        await _dao!.writeInternal('mbb_custom_categories', encoded);
      }
    } catch (e) {
      debugPrint('Error saving custom categories: $e');
    }
  }

  Future<void> addCategory({
    required String label,
    required String iconKey,
    Color? color,
  }) async {
    final String newId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    final Color effectiveColor = color ?? nextAvailableColor();
    final CategoryItem item = CategoryItem(
      id: newId,
      label: label.trim(),
      iconKey: iconKey,
      colorValue: color.toARGB32(),
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
      colorValue: color.toARGB32(),
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
}
