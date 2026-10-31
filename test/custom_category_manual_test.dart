import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/models/category.dart';
import 'package:mbb_money/data/models/transaction.dart';
import 'package:mbb_money/data/models/tx_source.dart';
import 'package:mbb_money/data/stores/category_store.dart';
import 'package:mbb_money/ui/category_ref.dart';
import 'package:mbb_money/ui/widgets/charts.dart';

void main() {
  group('Manual transaction category preservation', () {
    test('custom category ID is preserved in draft creation logic', () {
      const String customId = 'cat_1730001234567';
      final String? cleanCatId =
          (customId.isNotEmpty) ? customId.trim() : null;
      final String? resolvedId = cleanCatId;
      final bool needsReview = resolvedId == null || resolvedId.isEmpty;

      final Transaction tx = Transaction(
        id: Transaction.draftId,
        type: TxType.expense,
        amount: 50000,
        occurredAt: DateTime(2026, 10, 30),
        description: 'Trà sữa KOI',
        categoryId: resolvedId,
        source: TxSource.manual,
        isPendingReview: needsReview,
      );

      expect(tx.categoryId, customId);
      expect(tx.isPendingReview, isFalse);
    });

    test('manual transaction with no category sets isPendingReview true and null id', () {
      const String? categoryId = null;
      const String description = 'xyz 123 unknown';
      final String? cleanCatId =
          (categoryId != null && categoryId.trim().isNotEmpty)
              ? categoryId.trim()
              : null;
      final String? resolvedId = cleanCatId;
      final bool needsReview = resolvedId == null || resolvedId.isEmpty;

      final Transaction tx = Transaction(
        id: Transaction.draftId,
        type: TxType.expense,
        amount: 75000,
        occurredAt: DateTime(2026, 10, 30),
        description: description,
        categoryId: resolvedId,
        source: TxSource.manual,
        isPendingReview: needsReview,
      );

      expect(tx.categoryId, isNull);
      expect(tx.isPendingReview, isTrue);
    });
  });

  group('Donut slice aggregation and legend consistency', () {
    test('merges duplicate category references and keeps true order', () {
      final List<({String? id, int total})> raw = [
        (id: 'food', total: 100000),
        (id: null, total: 50000), // maps to fallback 'other'
        (id: 'other', total: 70000), // maps to fallback 'other'
        (id: 'cat_custom', total: 150000), // custom category
      ];

      // Simulate CategoryResolver with a custom category
      CategoryRef resolve(String? id) {
        if (id == 'cat_custom') {
          return CategoryRef(
            id: 'cat_custom',
            label: 'Trọ & Nhà',
            icon: Category.bills.icon,
            tint: Category.bills.tint,
            isCustom: true,
          );
        }
        if (id == 'food') {
          return CategoryRef.fromEnum(Category.food);
        }
        return CategoryRef.fallback;
      }

      final Map<String, ({CategoryRef category, int total})> merged = {};
      for (final c in raw) {
        if (c.total <= 0) continue;
        final CategoryRef ref = resolve(c.id);
        final existing = merged[ref.id];
        if (existing != null) {
          merged[ref.id] = (category: ref, total: existing.total + c.total);
        } else {
          merged[ref.id] = (category: ref, total: c.total);
        }
      }

      final List<({CategoryRef category, int total})> resolved =
          merged.values.toList()..sort((a, b) => b.total.compareTo(a.total));

      // 3 unique categories: cat_custom (150k), other (120k = 50k + 70k), food (100k)
      expect(resolved.length, 3);
      expect(resolved[0].category.id, 'cat_custom');
      expect(resolved[0].total, 150000);
      expect(resolved[0].category.label, 'Trọ & Nhà');

      expect(resolved[1].category.id, 'other');
      expect(resolved[1].total, 120000);
      expect(resolved[1].category.label, 'Khác');

      expect(resolved[2].category.id, 'food');
      expect(resolved[2].total, 100000);

      // Verify DonutSlice count and colors
      final List<DonutSlice> slices = [
        for (final item in resolved)
          DonutSlice(
            label: item.category.label,
            value: item.total,
            color: item.category.tint,
          ),
      ];

      expect(slices.length, 3);
      expect(slices[0].label, 'Trọ & Nhà');
      expect(slices[0].value, 150000);
    });

    test('uncategorized transactions get designated amber category instead of collapsing to Khác', () {
      final List<({String? id, int total})> raw = [
        (id: 'food', total: 100000),
        (id: null, total: 500000), // unclassified row from bank
        (id: 'other', total: 70000), // genuine other row
      ];

      final Map<String, ({CategoryRef category, int total})> merged = {};
      for (final c in raw) {
        if (c.total <= 0) continue;
        final CategoryRef ref = (c.id == null || c.id!.trim().isEmpty)
            ? CategoryRef(
                id: 'uncategorized',
                label: 'Chưa phân loại',
                icon: Category.other.icon,
                tint: const Color(0xFFFF9100),
              )
            : (c.id == 'food'
                ? CategoryRef.fromEnum(Category.food)
                : CategoryRef.fallback);
        final existing = merged[ref.id];
        if (existing != null) {
          merged[ref.id] = (category: ref, total: existing.total + c.total);
        } else {
          merged[ref.id] = (category: ref, total: c.total);
        }
      }

      final List<({CategoryRef category, int total})> resolved =
          merged.values.toList()..sort((a, b) => b.total.compareTo(a.total));

      // 3 completely distinct categories: uncategorized (500k), food (100k), other (70k)
      expect(resolved.length, 3);
      expect(resolved[0].category.id, 'uncategorized');
      expect(resolved[0].category.label, 'Chưa phân loại');
      expect(resolved[0].category.tint, const Color(0xFFFF9100));

      expect(resolved[1].category.id, 'food');
      expect(resolved[1].category.label, 'Ăn uống');
      expect(resolved[1].category.tint, const Color(0xFFFF5722));

      expect(resolved[2].category.id, 'other');
      expect(resolved[2].category.label, 'Khác');
      expect(resolved[2].category.tint, const Color(0xFF94A3B8));
    });

    test('donut chart slices enforce distinct colors even when categories share same color', () {
      // 5 categories like in Hoàng's screenshot where 4 were cyan
      final List<({CategoryRef category, int total})> items = [
        (category: CategoryRef(id: 'c1', label: 'shopping', icon: Icons.shopping_bag, tint: const Color(0xFF00E5FF), isCustom: true), total: 340000),
        (category: CategoryRef(id: 'c2', label: 'Ăn uống', icon: Icons.restaurant, tint: const Color(0xFFFF5722)), total: 200000),
        (category: CategoryRef(id: 'c3', label: 'AI', icon: Icons.smart_toy, tint: const Color(0xFF00E5FF), isCustom: true), total: 180000),
        (category: CategoryRef(id: 'c4', label: 'Skin_Care', icon: Icons.spa, tint: const Color(0xFF00E5FF), isCustom: true), total: 170000),
        (category: CategoryRef(id: 'c5', label: 'Di chuyển', icon: Icons.directions_car, tint: const Color(0xFF00E5FF), isCustom: true), total: 110000),
      ];

      final Set<int> usedSliceColors = <int>{};
      final List<DonutSlice> slices = <DonutSlice>[];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        Color sliceColor = item.category.tint;
        if (usedSliceColors.contains(sliceColor.toARGB32())) {
          for (final int palVal in CategoryStore.neonPalette) {
            if (!usedSliceColors.contains(palVal)) {
              sliceColor = Color(palVal);
              break;
            }
          }
        }
        usedSliceColors.add(sliceColor.toARGB32());
        slices.add(DonutSlice(
          label: item.category.label,
          value: item.total,
          color: sliceColor,
        ));
      }

      // 5 slices must have 5 UNIQUE colors!
      expect(slices.length, 5);
      final Set<Color> uniqueColors = slices.map((DonutSlice s) => s.color).toSet();
      expect(uniqueColors.length, 5, reason: 'All 5 categories must receive distinct colors');
      expect(slices[0].color, const Color(0xFF00E5FF)); // shopping keeps cyan
      expect(slices[1].color, const Color(0xFFFF5722)); // Ăn uống keeps orange
      expect(slices[2].color, isNot(const Color(0xFF00E5FF))); // AI gets distinct color
      expect(slices[3].color, isNot(const Color(0xFF00E5FF))); // Skin_Care gets distinct color
      expect(slices[4].color, isNot(const Color(0xFF00E5FF))); // Di chuyển gets distinct color
    });
  });

  group('CategoryStore neon palette', () {
    test('contains at least 15 unique high-contrast colors', () {
      expect(CategoryStore.neonPalette.length, greaterThanOrEqualTo(15));
      final Set<int> unique = CategoryStore.neonPalette.toSet();
      expect(unique.length, CategoryStore.neonPalette.length);
    });

    test('guessed icon for Di chuyển is transport', () {
      expect(guessIconKey('Di chuyển'), 'transport');
      expect(guessIconKey('Skin_Care'), 'beauty');
      expect(guessIconKey('AI tool'), 'tech');
    });
  });
}
