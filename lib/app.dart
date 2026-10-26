import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'main.dart' show DeepLinkHandler;
import 'ui/add/add_transaction_sheet.dart';
import 'ui/categories/manage_categories_page.dart';
import 'ui/new_transaction_ticker.dart';
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
      // iOS swipe-back / swipe-forward: MaterialApp already installs the
      // Cupertino back gesture on iOS. What was missing was horizontal swipe
      // between the three bottom tabs, handled in AppShell's GestureDetector.
      // Taps on empty space unfocus the keyboard via the shell's TapRegion.
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
  late final PageController _pageController = PageController(initialPage: _index);

  static const List<String> _titles = <String>['Tổng quan', 'Giao dịch', 'Báo cáo'];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNavTap(int i) {
    if (_index == i) return;
    setState(() => _index = i);
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.watch<TransactionStore>();

    final List<Widget> pages = <Widget>[
      OverviewPage(
        onOpenAll: () => _onNavTap(1),
        onAdd: () => AddTransactionSheet.show(context),
      ),
      const TransactionsPage(),
      const ReportsPage(),
    ];

    return NewTransactionTicker(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: MidnightBackground(
                // TapRegion: tapping outside any text field closes the keyboard
                child: TapRegion(
                  onTapOutside: (PointerDownEvent _) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (int i) => setState(() => _index = i),
                    children: pages,
                  ),
                ),
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
          onChanged: _onNavTap,
          onAdd: () => AddTransactionSheet.show(context),
        ),
      ),
    );
  }
}
