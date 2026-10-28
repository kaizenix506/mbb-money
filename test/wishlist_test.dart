import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/models/wishlist_item.dart';

void main() {
  group('WishlistItem tests', () {
    test('effectivePrice uses actualPrice when bought, expectedPrice otherwise', () {
      final unbought = WishlistItem(
        id: 1,
        title: 'Bàn phím cơ',
        expectedPrice: 2000000,
        createdAt: DateTime.now(),
      );
      expect(unbought.effectivePrice, 2000000);

      final boughtWithDiscount = WishlistItem(
        id: 2,
        title: 'Bàn phím cơ',
        expectedPrice: 2000000,
        actualPrice: 1800000,
        isBought: true,
        createdAt: DateTime.now(),
      );
      expect(boughtWithDiscount.effectivePrice, 1800000);

      final boughtWithoutActual = WishlistItem(
        id: 3,
        title: 'Chuột không dây',
        expectedPrice: 500000,
        isBought: true,
        createdAt: DateTime.now(),
      );
      expect(boughtWithoutActual.effectivePrice, 500000);
    });

    test('WishlistItem round-trips through map serialization', () {
      final now = DateTime(2026, 10, 28, 12, 0);
      final item = WishlistItem(
        id: 42,
        title: 'Màn hình 4K',
        expectedPrice: 8500000,
        actualPrice: 8200000,
        isBought: true,
        boughtAt: now,
        createdAt: now,
        notes: 'Mua tại CellphoneS',
      );

      final map = item.toMap();
      final roundTrip = WishlistItem.fromMap(map);

      expect(roundTrip.id, 42);
      expect(roundTrip.title, 'Màn hình 4K');
      expect(roundTrip.expectedPrice, 8500000);
      expect(roundTrip.actualPrice, 8200000);
      expect(roundTrip.isBought, isTrue);
      expect(roundTrip.boughtAt, now);
      expect(roundTrip.createdAt, now);
      expect(roundTrip.notes, 'Mua tại CellphoneS');
    });

    test('Budget math: remaining budget subtracts expected price of planned items', () {
      const int totalBudget = 10000000; // 10tr

      final item1 = WishlistItem(
        id: 1,
        title: 'Món 1',
        expectedPrice: 3000000,
        createdAt: DateTime.now(),
      );
      final item2 = WishlistItem(
        id: 2,
        title: 'Món 2',
        expectedPrice: 2500000,
        createdAt: DateTime.now(),
      );
      final item3Bought = WishlistItem(
        id: 3,
        title: 'Món 3 (đã mua)',
        expectedPrice: 1500000,
        isBought: true,
        actualPrice: 1400000,
        createdAt: DateTime.now(),
      );

      final items = [item1, item2, item3Bought];

      final planned = items.where((i) => !i.isBought).toList();
      final bought = items.where((i) => i.isBought).toList();

      final int totalPlanned = planned.fold(0, (s, i) => s + i.expectedPrice);
      final int totalBought = bought.fold(0, (s, i) => s + i.effectivePrice);
      final int remainingBudget = totalBudget - totalPlanned;

      expect(totalPlanned, 5500000); // 3tr + 2.5tr
      expect(totalBought, 1400000); // 1.4tr
      expect(remainingBudget, 4500000); // 10tr - 5.5tr = 4.5tr
    });
  });
}
