import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../add/add_transaction_sheet.dart';
import '../stores/transaction_store.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/mini_chip.dart';

/// Full transaction list for the selected month, grouped by day with a running
/// day total — mirrors how people actually reconcile a bank statement.
class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.watch<TransactionStore>();
    final List<({DateTime day, List<Transaction> items, int dayTotal})> groups =
        store.groupedByDay;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: store.refresh,
        color: AppColors.mint,
        backgroundColor: AppColors.bgMid,
        child: CustomScrollView(
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
                          // Same swipe/pick affordance as reports: tap the month
                          // to jump anywhere in history.
                          GestureDetector(
                            onTap: () => showMonthPicker(context, store),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  Fmt.monthYear(store.month),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.inkDim,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.expand_more_rounded,
                                  size: 14,
                                  color: AppColors.inkFaint,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quản lý danh mục',
                      icon: const Icon(Icons.folder_rounded, color: AppColors.neonCyan, size: 21),
                      onPressed: () => Navigator.of(context).pushNamed('/categories'),
                    ),
                    if (store.isLoading)
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
            if (groups.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.inbox_rounded,
                  title: 'Tháng này chưa có giao dịch',
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
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
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
