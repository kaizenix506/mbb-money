import 'package:sqflite/sqflite.dart';
import '../models/wishlist_item.dart';

class WishlistDao {
  const WishlistDao(this._dbFuture);

  final Future<Database> _dbFuture;

  Future<Database> get _db => _dbFuture;

  Future<List<WishlistItem>> getAll() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'wishlist_items',
      orderBy: 'is_bought ASC, created_at DESC',
    );
    return rows.map(WishlistItem.fromMap).toList();
  }

  Future<WishlistItem> insert({
    required String title,
    required int expectedPrice,
    String? notes,
  }) async {
    final Database db = await _db;
    final DateTime now = DateTime.now();
    final WishlistItem draft = WishlistItem(
      id: 0,
      title: title.trim(),
      expectedPrice: expectedPrice,
      createdAt: now,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
    );
    final int id = await db.insert('wishlist_items', draft.toMap());
    return draft.copyWith(id: id);
  }

  Future<void> update(WishlistItem item) async {
    final Database db = await _db;
    await db.update(
      'wishlist_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[item.id],
    );
  }

  Future<void> setBought(int id, bool isBought, {int? actualPrice}) async {
    final Database db = await _db;
    await db.update(
      'wishlist_items',
      <String, Object?>{
        'is_bought': isBought ? 1 : 0,
        'actual_price': actualPrice,
        'bought_at': isBought ? DateTime.now().millisecondsSinceEpoch : null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> delete(int id) async {
    final Database db = await _db;
    await db.delete(
      'wishlist_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> clearBought() async {
    final Database db = await _db;
    return db.delete(
      'wishlist_items',
      where: 'is_bought = 1',
    );
  }
}
