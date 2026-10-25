import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/models/tx_range.dart';

/// The range picker drives SQL bounds, so an off-by-one here silently hides a
/// day of spending. These tests pin the exact window edges.
void main() {
  group('TxRange.windowAt', () {
    test('7 ngày includes today and the six days before it', () {
      // Mid-afternoon so a naive "days since midnight" bug would show up.
      final DateTime now = DateTime(2026, 10, 26, 15, 30);
      final ({DateTime from, DateTime to}) w = TxRange.days7.windowAt(now);

      // `to` is exclusive and lands on midnight of the day after today, so
      // today's rows (at any hour) are always inside the window.
      expect(w.to, DateTime(2026, 10, 27));
      expect(w.from, DateTime(2026, 10, 20));
      expect(w.to.difference(w.from).inDays, 7);
    });

    test('2 tuần is fourteen days, not fifteen', () {
      final DateTime now = DateTime(2026, 10, 26, 9);
      final ({DateTime from, DateTime to}) w = TxRange.weeks2.windowAt(now);
      expect(w.to.difference(w.from).inDays, 14);
    });

    test('crosses a month boundary correctly', () {
      final DateTime now = DateTime(2026, 3, 3, 8);
      final ({DateTime from, DateTime to}) w = TxRange.days7.windowAt(now);
      expect(w.from, DateTime(2026, 2, 25));
      expect(w.to, DateTime(2026, 3, 4));
    });

    test('crosses a leap-day boundary correctly', () {
      final DateTime now = DateTime(2028, 3, 1, 10);
      final ({DateTime from, DateTime to}) w = TxRange.days7.windowAt(now);
      // 2028 is a leap year, so subtracting 7 from 1 Mar lands on 24 Feb.
      expect(w.from, DateTime(2028, 2, 24));
    });

    test('5 năm reaches back five years', () {
      final DateTime now = DateTime(2026, 10, 26, 12);
      final ({DateTime from, DateTime to}) w = TxRange.years5.windowAt(now);
      expect(w.to.difference(w.from).inDays, 1825);
      expect(w.from.isBefore(DateTime(2022, 1, 1)), isTrue);
    });

    test('every range has a strictly growing window', () {
      final DateTime now = DateTime(2026, 10, 26, 12);
      int previous = 0;
      for (final TxRange r in TxRange.values) {
        final int days = r.windowAt(now).to.difference(r.windowAt(now).from).inDays;
        expect(days, greaterThan(previous), reason: 'range ${r.name}');
        previous = days;
      }
    });
  });

  group('TxRange.describe', () {
    test('formats same-year windows as dd/MM – dd/MM', () {
      expect(
        TxRange.days7.describe(DateTime(2026, 10, 26, 12)),
        '20/10 – 26/10',
      );
    });

    test('includes years when the window spans two years', () {
      expect(
        TxRange.months3.describe(DateTime(2027, 1, 15, 12)),
        '18/10/2026 – 15/01/2027',
      );
    });

    test('pads single-digit days and months', () {
      expect(
        TxRange.days7.describe(DateTime(2026, 1, 5, 12)),
        '30/12/2025 – 05/01/2026',
      );
    });
  });

  group('TxRange metadata', () {
    test('labels match the eight options Hoàng asked for', () {
      expect(
        TxRange.values.map((TxRange r) => r.label).toList(),
        <String>[
          '7 ngày',
          '2 tuần',
          '1 tháng',
          '3 tháng',
          '6 tháng',
          '1 năm',
          '2 năm',
          '5 năm',
        ],
      );
    });

    test('row caps never decrease as the window grows', () {
      int previous = 0;
      for (final TxRange r in TxRange.values) {
        expect(r.maxRows, greaterThan(previous));
        previous = r.maxRows;
      }
    });

    test('all exposes every value', () {
      expect(TxRange.all.length, TxRange.values.length);
    });
  });
}
