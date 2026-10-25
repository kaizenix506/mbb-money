import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mbb_money/core/theme.dart';
import 'package:mbb_money/data/db/transaction_dao.dart';
import 'package:mbb_money/data/models/tx_range.dart';
import 'package:mbb_money/data/repositories/transaction_repository.dart';
import 'package:mbb_money/ui/stores/transaction_store.dart';
import 'package:mbb_money/ui/transactions/range_selector.dart';

/// The selector is the only way to change the history window, so it has to be
/// fully reachable on a phone-sized screen and the chips must not overflow.
void main() {
  // Tapping a chip triggers a real query, so the store needs a working database.
  // In-memory FFI keeps the test hermetic.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Widget harness(TransactionStore store) => MaterialApp(
        theme: buildLiquidGlassTheme(),
        home: ChangeNotifierProvider<TransactionStore>.value(
          value: store,
          child: const Scaffold(
            backgroundColor: AppColors.bgTop,
            body: SizedBox(width: 390, height: 120, child: RangeSelector()),
          ),
        ),
      );

  TransactionStore newStore() => TransactionStore(
        TransactionRepository(dao: TransactionDao(directory: inMemoryDatabasePath)),
      );

  testWidgets('renders the leading ranges without overflowing', (WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(harness(newStore()));
    await t.pump(const Duration(milliseconds: 300));

    expect(t.takeException(), isNull);
    // The row is a lazy horizontal list, so only the visible chips are built.
    // The first ones must always be present.
    expect(find.text('7 ngày'), findsOneWidget);
    expect(find.text('2 tuần'), findsOneWidget);
    expect(find.text('1 tháng'), findsOneWidget);
  });

  testWidgets('scrolling right reveals the long ranges', (WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(harness(newStore()));
    await t.pump(const Duration(milliseconds: 300));

    // Drag repeatedly until the last chip is reachable rather than assuming a
    // single drag distance, which depends on the sum of chip widths.
    await t.scrollUntilVisible(
      find.text('5 năm'),
      120,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await t.pumpAndSettle();

    expect(find.text('5 năm'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('defaults to the 1 tháng chip', (WidgetTester t) async {
    final TransactionStore store = newStore();
    await t.pumpWidget(harness(store));
    await t.pump(const Duration(milliseconds: 300));

    expect(store.range, TxRange.months1);
  });

  testWidgets('tapping a chip changes the selected range', (WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final TransactionStore store = newStore();
    await t.pumpWidget(harness(store));
    await t.pump(const Duration(milliseconds: 300));

    // "7 ngày" is the first chip and always on screen.
    await t.tap(find.text('7 ngày'));
    await t.pumpAndSettle();

    expect(store.range, TxRange.days7);
    expect(t.takeException(), isNull);
  });
}
