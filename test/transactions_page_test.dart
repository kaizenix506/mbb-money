import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbb_money/core/theme.dart';
import 'package:mbb_money/data/db/transaction_dao.dart';
import 'package:mbb_money/data/repositories/transaction_repository.dart';
import 'package:mbb_money/data/stores/category_store.dart';
import 'package:mbb_money/ui/stores/transaction_store.dart';
import 'package:mbb_money/ui/transactions/transactions_page.dart';

/// Layout tests for TransactionsPage.
///
/// These run hermetically without SQLite calls, using the store's initial state
/// so timers never deadlock under fake-async.
void main() {
  Widget harness({required TransactionStore store}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionStore>.value(value: store),
          ChangeNotifierProvider<CategoryStore>.value(value: CategoryStore()),
          Provider<TransactionRepository>.value(
            value: TransactionRepository(dao: TransactionDao()),
          ),
        ],
        child: MaterialApp(
          theme: buildLiquidGlassTheme(),
          home: const Scaffold(
            backgroundColor: AppColors.bgTop,
            body: TransactionsPage(),
          ),
        ),
      );

  testWidgets('renders at iPhone width with no overflow', (WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final TransactionStore store =
        TransactionStore(TransactionRepository(dao: TransactionDao()));

    await t.pumpWidget(harness(store: store));
    await t.pump(const Duration(milliseconds: 100));

    // Any RenderFlex overflow shows up here as a thrown exception in debug.
    expect(t.takeException(), isNull);
    expect(find.text('Giao dịch'), findsOneWidget);
    expect(find.text('Chi'), findsOneWidget);
    expect(find.text('Thu'), findsOneWidget);
    expect(find.text('Còn lại'), findsOneWidget);
  });

  testWidgets('header reports the selected window and a row count', (WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final TransactionStore store =
        TransactionStore(TransactionRepository(dao: TransactionDao()));

    await t.pumpWidget(harness(store: store));
    await t.pump(const Duration(milliseconds: 100));

    // Default is 1 tháng, subtitle shows the count and the date range with en dash.
    expect(find.textContaining('khoản'), findsWidgets);
    expect(find.textContaining('–'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('empty window shows the empty-state card with add button',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final TransactionStore store =
        TransactionStore(TransactionRepository(dao: TransactionDao()));

    await t.pumpWidget(harness(store: store));
    await t.pump(const Duration(milliseconds: 100));

    // Fresh store has no rows, so the empty state must appear.
    expect(find.textContaining('Chưa có giao dịch'), findsOneWidget);
    expect(find.text('Thêm giao dịch'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
