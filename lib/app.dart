import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/formatters.dart';
import 'core/theme.dart';
import 'main.dart' show DeepLinkHandler;
import 'ui/add/add_transaction_sheet.dart';
import 'ui/categories/manage_categories_page.dart';
import 'ui/overview/overview_page.dart';
import 'ui/reports/reports_page.dart';
import 'ui/review/review_page.dart';
import 'ui/settings/settings_page.dart';
import 'ui/shell.dart';
import 'ui/stores/transaction_store.dart';
import 'ui/transactions/transactions_page.dart';
import 'ui/widgets/common.dart';

class MbbMoneyApp extends StatelessWidget {
  const MbbMoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MBB Money',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: DeepLinkHandler.messengerKey,
      theme: buildLiquidGlassTheme(),
      home: const AppShell(),
      routes: <String, WidgetBuilder>{
        ReviewPage.route: (_) => const _Slate(ReviewPage()),
        SettingsPage.route: (_) => const _Slate(SettingsPage()),
        ManageCategoriesPage.route: (_) => const _Slate(ManageCategoriesPage()),
      },
    );
  }
}

/// Wraps pushed screens in the shared gradient so navigation never flashes a
/// white background between pages.
class _Slate extends StatelessWidget {
  const _Slate(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MidnightBackground(child: child);
  }
}

/// Bottom navigation: a floating glass pill with three tabs and a central
/// add button, exactly as in the chosen mockup.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<String> _titles = <String>['Tổng quan', 'Giao dịch', 'Báo cáo'];

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.watch<TransactionStore>();

    final List<Widget> pages = <Widget>[
      OverviewPage(
        onOpenAll: () => setState(() => _index = 1),
        onAdd: () => AddTransactionSheet.show(context),
      ),
      const TransactionsPage(),
      const ReportsPage(),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: MidnightBackground(
              child: IndexedStack(index: _index, children: pages),
            ),
          ),
          if (store.isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: AppColors.mint,
              ),
            ),
        ],
      ),
      bottomNavigationBar: GlassNavBar(
        index: _index,
        titles: _titles,
        onChanged: (int i) => setState(() => _index = i),
        onAdd: () => AddTransactionSheet.show(context),
      ),
    );
  }
}
