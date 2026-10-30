import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/models/category.dart';
import 'package:mbb_money/data/models/transaction.dart';
import 'package:mbb_money/data/models/tx_source.dart';
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
  });
}
