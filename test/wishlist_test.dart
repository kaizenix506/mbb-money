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
      final int totalCommitted = totalPlanned + totalBought;
      final int remainingBudget = totalBudget - totalCommitted;

      expect(totalPlanned, 5500000); // 3tr + 2.5tr
      expect(totalBought, 1400000); // 1.4tr
      expect(totalCommitted, 6900000); // 5.5tr + 1.4tr
      expect(remainingBudget, 3100000); // 10tr - 6.9tr = 3.1tr
    });

    test('Ticking "da mua" must not refund money back into the budget', () {
      const int totalBudget = 10000000; // 10tr

      final item = WishlistItem(
        id: 1,
        title: 'Tai nghe',
        expectedPrice: 3000000,
        createdAt: DateTime.now(),
      );

      int remainingFor(List<WishlistItem> list) {
        final int planned =
            list.where((i) => !i.isBought).fold(0, (s, i) => s + i.expectedPrice);
        final int bought =
            list.where((i) => i.isBought).fold(0, (s, i) => s + i.effectivePrice);
        return totalBudget - planned - bought;
      }

      final int beforeBuy = remainingFor([item]);
      expect(beforeBuy, 7000000); // 10tr - 3tr

      // Tick "da mua": money stays deducted, must NOT increase.
      final boughtItem = item.copyWith(isBought: true, actualPrice: 3000000);
      final int afterBuy = remainingFor([boughtItem]);
      expect(afterBuy, 7000000);
      expect(afterBuy, lessThanOrEqualTo(beforeBuy));

      // Actual price higher than expected -> remaining must decrease further.
      final boughtPricier = item.copyWith(isBought: true, actualPrice: 3500000);
      expect(remainingFor([boughtPricier]), 6500000);
      expect(remainingFor([boughtPricier]), lessThan(afterBuy));
    });

    test('Remaining budget can go negative when over budget', () {
      final overBudget = WishlistItem(
        id: 9,
        title: 'Mon dat',
        expectedPrice: 12000000,
        createdAt: DateTime.now(),
      );
      final int remaining = 10000000 - overBudget.expectedPrice;
      expect(remaining, -2000000);
    });
  });
}
