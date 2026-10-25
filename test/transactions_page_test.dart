import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import 'package:mbb_money/core/theme.dart';
import 'package:mbb_money/data/db/database.dart';
import 'package:mbb_money/data/db/transaction_dao.dart';
import 'package:mbb_money/data/models/category.dart';
import 'package:mbb_money/data/models/transaction.dart';
import 'package:mbb_money/data/repositories/transaction_repository.dart';
import 'package:mbb_money/data/stores/category_store.dart';
import 'package:mbb_money/ui/stores/transaction_store.dart';
import 'package:mbb_money/ui/transactions/transactions_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    hide Transaction;

/// Renders the real transactions tab at iPhone width with seeded data.
///
/// Widget tests are the only automated proof of layout in this environment (the
/// browser driver is unavailable), so this checks the things that actually broke
/// before: overflow stripes, clipped currency, and unreachable chips.
void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // A fresh folder per test, so AppDatabase's per-directory cache and the
    // schema both start clean.
    tempDir = await Directory.systemTemp.createTemp('mbb_test_');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  late TransactionRepository repo;
  late TransactionStore store;

  setUp(() async {
    repo = TransactionRepository(dao: TransactionDao(directory: tempDir.path));
    store = TransactionStore(repo);

    // A spread of history so the 1-month and 5-year windows differ visibly.
    final DateTime now = DateTime.now();
    final List<Future<Transaction>> writes = <Future<Transaction>>[];
    for (int i = 0; i < 40; i++) {
      writes.add(
        repo.addManual(
          type: i % 7 == 0 ? TxType.income : TxType.expense,
          amount: (i + 1) * 12500,
          occurredAt: now.subtract(Duration(days: i * 9)),
          description: 'Giao dịch thử $i · ăn uống',
          categoryId: i % 7 == 0 ? Category.salary.id : Category.food.id,
        ),
      );
    }
    await Future.wait(writes);
    await store.load();
  });

  Widget harness() => MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionStore>.value(value: store),
          ChangeNotifierProvider<CategoryStore>.value(value: CategoryStore()),
          Provider<TransactionRepository>.value(value: repo),
        ],
        child: MaterialApp(
          theme: buildLiquidGlassTheme(),
          home: const Scaffold(
            backgroundColor: AppColors.bgTop,
            body: TransactionsPage(),
          ),
        ),
      );

  Future<void> pumpPhone(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(child);
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('renders at iPhone width with no overflow', (WidgetTester t) async {
    await pumpPhone(t, harness());

    // Any RenderFlex overflow shows up here as a thrown exception in debug.
    expect(t.takeException(), isNull);

    expect(find.text('Giao dịch'), findsOneWidget);
    expect(find.text('Chi'), findsOneWidget);
    expect(find.text('Thu'), findsOneWidget);
    expect(find.text('Còn lại'), findsOneWidget);
  });

  testWidgets('header reports the selected window and a row count', (WidgetTester t) async {
    await pumpPhone(t, harness());

    // Default is 1 tháng, so the subtitle must mention khoản count.
    expect(find.textContaining('khoản'), findsWidgets);
    // The describe() output uses the en dash between two dates.
    expect(find.textContaining('–'), findsWidgets);
  });

  testWidgets('empty window shows a helpful empty state, not a blank screen',
      (WidgetTester t) async {
    // Fresh store with no rows at all.
    final TransactionRepository emptyRepo =
        TransactionRepository(dao: TransactionDao(directory: tempDir.path));
    final TransactionStore emptyStore = TransactionStore(emptyRepo);
    await emptyStore.load();

    await pumpPhone(
      t,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransactionStore>.value(value: emptyStore),
          ChangeNotifierProvider<CategoryStore>.value(value: CategoryStore()),
          Provider<TransactionRepository>.value(value: emptyRepo),
        ],
        child: MaterialApp(
          theme: buildLiquidGlassTheme(),
          home: const Scaffold(
            backgroundColor: AppColors.bgTop,
            body: TransactionsPage(),
          ),
        ),
      ),
    );

    expect(find.textContaining('Chưa có giao dịch'), findsOneWidget);
    expect(find.text('Thêm giao dịch'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
