import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/core/formatters.dart';
import 'package:mbb_money/data/auto_categorizer.dart';
import 'package:mbb_money/data/models/category.dart';
import 'package:mbb_money/data/models/transaction.dart';
import 'package:mbb_money/data/models/tx_source.dart';

void main() {
  group('Fmt', () {
    test('amount uses dots as thousands separators', () {
      expect(Fmt.amount(42815300), '42.815.300');
      expect(Fmt.amount(58000), '58.000');
      expect(Fmt.amount(0), '0');
    });

    test('signed uses a typographic minus', () {
      expect(Fmt.signed(-58000), '\u221258.000');
      expect(Fmt.signed(28500000), '+28.500.000');
      expect(Fmt.signed(0), '0');
    });

    test('compact abbreviates for narrow stat columns', () {
      expect(Fmt.compact(28500000), '28,5tr');
      expect(Fmt.compact(1900000), '1,9tr');
      expect(Fmt.compact(2500000000), '2,5tỷ');
      expect(Fmt.compact(900), '900');
    });

    test('previousMonth clamps short months', () {
      expect(Fmt.previousMonth(DateTime(2026, 3, 31)), DateTime(2026, 2, 28));
      expect(Fmt.previousMonth(DateTime(2026, 1, 15)), DateTime(2025, 12, 15));
    });

    test('daysInMonth handles leap years', () {
      expect(Fmt.daysInMonth(DateTime(2024, 2)), 29);
      expect(Fmt.daysInMonth(DateTime(2026, 2)), 28);
    });
  });

  group('AutoCategorizer', () {
    test('picks specific merchant rules over generic ones', () {
      expect(
        AutoCategorizer.categorize('GRABFOOD order', isIncome: false),
        Category.food,
      );
      expect(
        AutoCategorizer.categorize('GrabBike to office', isIncome: false),
        Category.transport,
      );
      expect(
        AutoCategorizer.categorize('HIGHLANDS COFFEE Q1', isIncome: false),
        Category.coffee,
      );
    });

    test('never files an outgoing transfer as salary', () {
      expect(
        AutoCategorizer.categorize('chuyen khoan luong', isIncome: false),
        isNot(Category.salary),
      );
    });

    test('returns null rather than guessing', () {
      expect(AutoCategorizer.categorize('ZQX 99812', isIncome: false), isNull);
    });
  });

  group('Transaction', () {
    final Transaction base = Transaction(
      id: 1,
      type: TxType.expense,
      amount: 58000,
      occurredAt: DateTime(2026, 10, 24, 9, 41),
      description: 'Highlands',
      categoryId: 'coffee',
    );

    test('signedAmount respects direction', () {
      expect(base.signedAmount, -58000);
      expect(base.copyWith(type: TxType.income).signedAmount, 58000);
    });

    test('round-trips through map', () {
      final Transaction copy = Transaction.fromMap(base.toMap());
      expect(copy.amount, base.amount);
      expect(copy.type, base.type);
      expect(copy.categoryId, base.categoryId);
      expect(copy.occurredAt, base.occurredAt);
    });

    test('copyWith can clear a nullable field', () {
      expect(base.copyWith(categoryId: null).categoryId, isNull);
      expect(base.copyWith().categoryId, 'coffee');
    });

    test('dedupes by reference number', () {
      final Transaction a = base.copyWith(referenceNumber: 'FT123456789');
      final Transaction b = base.copyWith(
        id: 2,
        referenceNumber: 'FT123456789',
        amount: 999,
      );
      expect(a.looksSameAs(b), isTrue);
    });

    test('dedupes by amount and near-identical time without a reference', () {
      final Transaction b = base.copyWith(
        id: 2,
        occurredAt: base.occurredAt.add(const Duration(seconds: 30)),
      );
      expect(base.looksSameAs(b), isTrue);
    });

    test('does not dedupe different amounts', () {
      expect(base.looksSameAs(base.copyWith(id: 2, amount: 1000)), isFalse);
    });
  });

  group('TxSource', () {
    test('maps storage keys defensively', () {
      expect(TxSource.fromKey('shortcut'), TxSource.shortcut);
      expect(TxSource.fromKey('sepay'), TxSource.sepay);
      expect(TxSource.fromKey(null), TxSource.manual);
      expect(TxSource.fromKey('garbage'), TxSource.manual);
    });

    test('only bank sources carry the MB badge', () {
      expect(TxSource.shortcut.isFromBank, isTrue);
      expect(TxSource.manual.isFromBank, isFalse);
    });
  });
}
