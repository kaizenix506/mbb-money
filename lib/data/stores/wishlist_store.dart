import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/wishlist_dao.dart';
import '../models/wishlist_item.dart';

/// State store managing shopping wishlist, expected prices, and remaining budget calculation.
class WishlistStore extends ChangeNotifier {
  WishlistStore({required WishlistDao dao}) : _dao = dao {
    load();
  }

  static const String _kBudgetPrefsKey = 'mbb.wishlist.total_budget';

  final WishlistDao _dao;
  List<WishlistItem> _items = const <WishlistItem>[];
  int _totalBudget = 0;
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  List<WishlistItem> get all => _items;
  List<WishlistItem> get planned =>
      _items.where((WishlistItem i) => !i.isBought).toList();
  List<WishlistItem> get bought =>
      _items.where((WishlistItem i) => i.isBought).toList();

  /// Tổng tiền đã cam kết chi (dự kiến mua + đã mua).
  int get totalCommitted => totalPlanned + totalBought;

  int get totalBudget => _totalBudget;

  /// Tổng số tiền các món đồ muốn mua (dự kiến mua, chưa mua).
  int get totalPlanned =>
      planned.fold<int>(0, (int s, WishlistItem i) => s + i.expectedPrice);

  /// Tổng số tiền các món đồ đã mua.
  int get totalBought =>
      bought.fold<int>(0, (int s, WishlistItem i) => s + i.effectivePrice);

  /// Tổng ngân sách còn lại = Tổng ngân sách - (tiền dự kiến mua + tiền đã mua).
  /// Tiền của món đã mua vẫn bị trừ, không được hoàn lại vào ngân sách.
  int get remainingBudget => _totalBudget - totalPlanned - totalBought;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _totalBudget = prefs.getInt(_kBudgetPrefsKey) ?? 0;
      _items = await _dao.getAll();
    } catch (e) {
      debugPrint('Error loading wishlist items: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setTotalBudget(int amount) async {
    _totalBudget = amount.clamp(0, 1000000000000);
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBudgetPrefsKey, _totalBudget);
    } catch (e) {
      debugPrint('Error saving wishlist budget: $e');
    }
  }

  Future<WishlistItem> addItem({
    required String title,
    required int expectedPrice,
    String? notes,
  }) async {
    final WishlistItem created = await _dao.insert(
      title: title,
      expectedPrice: expectedPrice,
      notes: notes,
    );
    _items = <WishlistItem>[created, ..._items];
    notifyListeners();
    return created;
  }

  Future<void> toggleBought(
    int id,
    bool isBought, {
    int? actualPrice,
  }) async {
    await _dao.setBought(id, isBought, actualPrice: actualPrice);
    final DateTime now = DateTime.now();
    _items = _items.map((WishlistItem i) {
      if (i.id == id) {
        return i.copyWith(
          isBought: isBought,
          actualPrice: actualPrice ?? (isBought ? i.expectedPrice : null),
          boughtAt: isBought ? now : null,
        );
      }
      return i;
    }).toList();
    notifyListeners();
  }

  Future<void> deleteItem(int id) async {
    await _dao.delete(id);
    _items = _items.where((WishlistItem i) => i.id != id).toList();
    notifyListeners();
  }

  Future<void> clearBought() async {
    await _dao.clearBought();
    _items = _items.where((WishlistItem i) => !i.isBought).toList();
    notifyListeners();
  }

  Future<void> updateItem(WishlistItem item) async {
    await _dao.update(item);
    _items = _items.map((WishlistItem i) => i.id == item.id ? item : i).toList();
    notifyListeners();
  }
}
