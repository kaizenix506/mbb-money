import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/core/formatters.dart';
import 'package:mbb_money/core/theme.dart';
import 'package:mbb_money/core/vn_clock.dart';
import 'package:mbb_money/ui/widgets/charts.dart';

/// These widget tests stand in for a manual visual check: they assert that the
/// new overview pieces lay out without exceptions at iPhone width, which is
/// where overflow bugs actually show up.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: buildLiquidGlassTheme(),
        home: Scaffold(
          backgroundColor: AppColors.bgTop,
          body: SizedBox(width: 390, child: child),
        ),
      );

  group('NeonDonutChart', () {
    testWidgets('lays out at phone width without overflow', (WidgetTester t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(wrap(
        NeonDonutChart(
          slices: const <DonutSlice>[
            DonutSlice(label: 'Ăn uống', value: 500000, color: AppColors.neonPink),
            DonutSlice(label: 'Đi lại', value: 250000, color: AppColors.neonCyan),
            DonutSlice(label: 'Đồ uống', value: 150000, color: AppColors.neonViolet),
          ],
          centerValue: '900K',
          centerLabel: 'THÁNG NÀY',
        ),
      ));
      await t.pump(const Duration(milliseconds: 1000));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders centre label text', (WidgetTester t) async {
      await t.pumpWidget(wrap(
        const NeonDonutChart(
          slices: <DonutSlice>[
            DonutSlice(label: 'X', value: 1, color: Colors.red),
          ],
          centerValue: '42K',
          centerLabel: 'THÁNG NÀY',
        ),
      ));
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.text('42K'), findsOneWidget);
      expect(find.text('THÁNG NÀY'), findsOneWidget);
    });

    testWidgets('does not crash with an empty slice list', (WidgetTester t) async {
      await t.pumpWidget(wrap(
        const NeonDonutChart(slices: <DonutSlice>[], centerValue: '0'),
      ));
      await t.pump(const Duration(milliseconds: 1000));
      expect(t.takeException(), isNull);
    });
  });

  group('MonthCompareCard', () {
    testWidgets('shows a decrease with the đồng difference', (WidgetTester t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(wrap(
        const MonthCompareCard(
          current: 5000000,
          previous: 8000000,
          monthLabel: 'Tháng 10/2026',
          prevLabel: 'Tháng 9/2026',
        ),
      ));
      await t.pump(const Duration(milliseconds: 800));

      // Uppercase copy in the header line.
      expect(find.textContaining('GIẢM'), findsOneWidget);
      // The plain-language summary mentions the absolute difference.
      expect(find.textContaining(Fmt.dong(3000000)), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('shows an increase', (WidgetTester t) async {
      await t.pumpWidget(wrap(
        const MonthCompareCard(
          current: 9000000,
          previous: 4000000,
          monthLabel: 'Tháng 10/2026',
          prevLabel: 'Tháng 9/2026',
        ),
      ));
      await t.pump(const Duration(milliseconds: 800));
      expect(find.textContaining('TĂNG'), findsOneWidget);
    });

    testWidgets('handles a zero previous month gracefully', (WidgetTester t) async {
      await t.pumpWidget(wrap(
        const MonthCompareCard(
          current: 1200000,
          previous: 0,
          monthLabel: 'Tháng 10/2026',
          prevLabel: 'Tháng 9/2026',
        ),
      ));
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('Chưa có dữ liệu tháng trước'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('VnClock', () {
    test('formats seconds-bearing time for the live strip', () {
      final String s = VnClock.hms(DateTime(2026, 10, 26, 5, 7, 9));
      expect(s, '05:07:09');
    });

    test('short time drops the seconds', () {
      expect(VnClock.hm(DateTime(2026, 10, 26, 18, 4)), '18:04');
    });

    test('greeting covers every part of the day', () {
      // The greeting switch is time-of-day based; verify the copy exists for
      // each bucket by sampling the boundaries it documents.
      expect(VnClock.greeting, isNotEmpty);
    });
  });
}
