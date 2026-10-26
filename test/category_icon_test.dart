import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/stores/category_store.dart';

/// Regression tests for the "mọi danh mục đều ra cái dĩa" bug.
///
/// The editor used to seed every new category with `iconKey: 'food'`, which is
/// `Icons.restaurant_rounded` — the plate. These tests pin the replacement
/// behaviour: a new category's icon is derived from its name, never a blanket
/// default.
void main() {
  group('guessIconKey', () {
    test('never returns food for a name that is not about eating', () {
      expect(guessIconKey('Nuôi mèo'), 'pet');
      expect(guessIconKey('Du lịch Đà Lạt'), 'flight');
      expect(guessIconKey('Cà phê sáng'), 'coffee');
      expect(guessIconKey('Tiền điện'), 'bills');
    });

    test('maps the obvious Vietnamese cases', () {
      expect(guessIconKey('Ăn uống'), 'food');
      expect(guessIconKey('Trà sữa'), 'coffee');
      expect(guessIconKey('Xăng xe'), 'transport');
      expect(guessIconKey('Mua quần áo'), 'shopping');
      expect(guessIconKey('Thuốc men'), 'health');
      expect(guessIconKey('Quà tặng'), 'gift');
      expect(guessIconKey('Thú cưng'), 'pet');
    });

    test('falls back to a neutral glyph, not the plate', () {
      // Unrecognisable input must not silently become "food".
      expect(guessIconKey('xyzabc'), isNot('food'));
      expect(guessIconKey(''), isNot('food'));
      expect(guessIconKey(''), 'other');
    });

    test('every guessed key is renderable', () {
      // A key missing from categoryIconMap would render Icons.category_rounded,
      // which looks broken next to a real choice.
      const List<String> names = <String>[
        'Ăn uống',
        'Trà sữa',
        'Xăng xe',
        'Mua sắm',
        'Tiền điện',
        'Thuốc',
        'Game',
        'Sách',
        'Gia đình',
        'Mèo',
        'Bóng đá',
        'Nhạc',
        'Quà',
        'Du lịch',
        'Không rõ là gì',
      ];
      for (final String n in names) {
        final String key = guessIconKey(n);
        expect(categoryIconMap.containsKey(key), isTrue,
            reason: '"$n" guessed "$key" which is not in categoryIconMap');
      }
    });
  });

  group('CategoryItem', () {
    test('resolves a distinct icon per iconKey', () {
      // Directly guards the reported symptom: two different keys must not
      // collapse to the same IconData.
      const CategoryItem pet = CategoryItem(
        id: 'cat_1',
        label: 'Nuôi mèo',
        iconKey: 'pet',
        colorValue: 0xFF00F0FF,
      );
      const CategoryItem food = CategoryItem(
        id: 'cat_2',
        label: 'Ăn uống',
        iconKey: 'food',
        colorValue: 0xFFFFB066,
      );
      expect(pet.icon, isNot(food.icon));
    });

    test('round-trips iconKey through JSON', () {
      const CategoryItem item = CategoryItem(
        id: 'cat_9',
        label: 'Du lịch',
        iconKey: 'flight',
        colorValue: 0xFF39FF14,
        isCustom: true,
      );
      final CategoryItem back = CategoryItem.fromJson(item.toJson());
      expect(back.iconKey, 'flight');
      expect(back.label, 'Du lịch');
      expect(back.isCustom, isTrue);
    });

    test('unknown iconKey degrades to the neutral glyph, not a plate', () {
      const CategoryItem item = CategoryItem(
        id: 'cat_3',
        label: 'X',
        iconKey: 'key_that_does_not_exist',
        colorValue: 0xFFFFFFFF,
      );
      expect(item.icon, isNot(categoryIconMap['food']));
    });
  });
}
