import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../add/add_transaction_sheet.dart';
import '../stores/transaction_store.dart';
import '../widgets/common.dart';
import '../widgets/mini_chip.dart';
import 'range_selector.dart';

/// Full transaction list for the selected time window, grouped by day with a
/// running day total — mirrors how people actually reconcile a bank statement.
///
/// The window is chosen with [RangeSelector] (7 ngày → 5 năm) rather than the
/// calendar month used by the overview: reading history is a "last N days"
/// question, while budgeting is a "this month" question.
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Fires the next page a little before the bottom so scrolling feels endless.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final double remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 900) {
      context.read<TransactionStore>().loadMoreRange();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.watch<TransactionStore>();
    final List<({DateTime day, List<Transaction> items, int dayTotal})> groups =
        store.rangeGroupedByDay;
    final int rowCount =
        groups.fold<int>(0, (int n, var g) => n + g.items.length);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: store.refresh,
        color: AppColors.mint,
        backgroundColor: AppColors.bgMid,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Giao dịch',
                            style: AppText.sectionTitle.copyWith(
                              fontSize: 26,
                              letterSpacing: -0.8,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${store.range.describe(DateTime.now())} · '
                            '$rowCount khoản',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quản lý danh mục',
                      icon: const Icon(Icons.folder_rounded,
                          color: AppColors.neonCyan, size: 21),
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/categories'),
                    ),
                    if (store.rangeLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.mint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 12),
                child: const RangeSelector(),
              ),
            ),
            SliverToBoxAdapter(child: _RangeSummary(store: store)),
            if (groups.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.inbox_rounded,
                  title: 'Chưa có giao dịch trong ${store.range.label}',
                  subtitle: 'Mọi khoản thu chi sẽ hiện ở đây, kể cả khi '
                      'đến từ tin nhắn MB Bank.',
                  action: FilledButton.icon(
                    onPressed: () => AddTransactionSheet.show(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Thêm giao dịch'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintDeep,
                      foregroundColor: const Color(0xFF04231A),
                    ),
                  ),
                ),
              )
            else
              for (final ({DateTime day, List<Transaction> items, int dayTotal}) g
                  in groups)
                SliverToBoxAdapter(child: _DaySection(group: g)),
            SliverToBoxAdapter(
              child: _RangeFooter(
                hasMore: store.rangeHasMore,
                loading: store.rangeLoadingMore,
                onLoadMore: store.loadMoreRange,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

/// Income / expense / net for the chosen window, so the list answers
/// "how much did I spend in the last 2 years" without opening reports.
class _RangeSummary extends StatelessWidget {
  const _RangeSummary({required this.store});

  final TransactionStore store;

  @override
  Widget build(BuildContext context) {
    final totals = store.rangeTotals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: AppRadius.list,
        child: Row(
          children: <Widget>[
            _Stat(
              label: 'Chi',
              value: Fmt.dong(totals.expense),
              color: AppColors.neonPink,
            ),
            _Divider(),
            _Stat(
              label: 'Thu',
              value: Fmt.dong(totals.income),
              color: AppColors.neonGreen,
            ),
            _Divider(),
            _Stat(
              label: 'Còn lại',
              value: Fmt.signed(totals.net),
              color: totals.net >= 0 ? AppColors.neonCyan : AppColors.neonOrange,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.strokeFaint,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// End-of-list control: loads more on demand, or states that history is
/// exhausted so a long scroll never looks like a hang.
class _RangeFooter extends StatelessWidget {
  const _RangeFooter({
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool loading;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mint),
          ),
        ),
      );
    }
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton(
            onPressed: onLoadMore,
            child: const Text(
              'Tải thêm',
              style: TextStyle(fontSize: 12, color: AppColors.neonCyan),
            ),
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          'Đã hết lịch sử trong khoảng này',
          style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.group});

  final ({DateTime day, List<Transaction> items, int dayTotal}) group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          child: Row(
            children: <Widget>[
              Text(
                Fmt.relativeDay(group.day),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkDim,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Fmt.dayMonth(group.day),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.inkFaint,
                ),
              ),
              const Spacer(),
              Text(
                Fmt.signed(group.dayTotal),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: group.dayTotal >= 0
                      ? AppColors.mint
                      : AppColors.inkFaint,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: GlassCard(
            padding: EdgeInsets.zero,
            radius: AppRadius.list,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < group.items.length; i++)
                  TransactionRow(
                    transaction: group.items[i],
                    showDivider: i != group.items.length - 1,
                    onTap: () => _openActions(context, group.items[i]),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openActions(BuildContext context, Transaction tx) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => _TransactionActions(
        transaction: tx,
      ),
    );
  }
}

/// Recategorise / delete. Kept minimal: the detail view lives on the overview.
class _TransactionActions extends StatelessWidget {
  const _TransactionActions({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.read<TransactionStore>();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            transaction.description.isEmpty
                ? 'Giao dịch'
                : transaction.description,
            style: AppText.sectionTitle.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '${Fmt.fullDate(transaction.occurredAt)} · '
            '${Fmt.time(transaction.occurredAt)}',
            style: const TextStyle(fontSize: 12, color: AppColors.inkDim),
          ),
          const SizedBox(height: 20),
          const Text(
            'ĐỔI PHÂN LOẠI',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Category category in transaction.isIncome
                  ? Category.incomeChoices
                  : Category.expenseChoices)
                MiniChip(
                  label: category.label,
                  icon: category.icon,
                  tint: category.tint,
                  selected: transaction.categoryId == category.id,
                  onTap: () async {
                    await store.setCategory(transaction, category);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          TextButton.icon(
            onPressed: () async {
              await store.delete(transaction);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.coral),
            label: const Text(
              'Xoá giao dịch',
              style: TextStyle(color: AppColors.coral, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

}
