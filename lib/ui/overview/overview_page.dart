import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/db/transaction_dao.dart';
import '../../data/models/transaction.dart';
import '../../data/models/tx_source.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/sync_service.dart';
import '../categories/manage_categories_page.dart';
import '../settings/settings_page.dart';
import '../stores/transaction_store.dart';
import '../transactions/edit_transaction_sheet.dart';
import '../widgets/balance_hero_card.dart';
import '../widgets/common.dart';

/// Home tab — the "Midnight Glass" screen.
class OverviewPage extends StatefulWidget {
  const OverviewPage({this.onOpenAll, this.onAdd, super.key});

  final VoidCallback? onOpenAll;
  final VoidCallback? onAdd;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Pull-to-refresh covers the manual case; this makes a cold launch show
      // fresh SePay rows when the user has that source enabled.
      _autoSync(quiet: true);
    });
  }

  Future<void> _autoSync({bool quiet = false}) async {
    final SettingsRepository settings =
        context.read<SettingsRepository>();
    if (!settings.sepayEnabled || _syncing) return;

    setState(() => _syncing = true);
    final SyncService sync = context.read<SyncService>();
    final SyncReport report = await sync.syncSepay(
      accountNumber: settings.sepayAccountNumber,
    );
    if (report.added > 0) {
      await settings.markSynced(DateTime.now());
      if (mounted) {
        await context.read<TransactionStore>().afterExternalIngest();
      }
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    if (!quiet) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SyncService.describe(report))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.watch<TransactionStore>();
    final PeriodTotals totals = store.totals;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await store.refresh();
            await _autoSync(quiet: true);
          },
          color: AppColors.mint,
          backgroundColor: AppColors.bgMid,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              const _Header(),
              const SizedBox(height: 18),
              BalanceHeroCard(
                income: totals.income,
                expense: totals.expense,
                month: store.month,
                txCount: store.monthTransactions.where((t) => t.isExpense).length,
                canGoForward: store.canGoForward,
                dailyBudgetLeft: store.dailyBudgetLeft,
                onPreviousMonth: store.previousMonth,
                onNextMonth: store.nextMonth,
                onSyncTap: () => _autoSync(quiet: false),
              ),
              if (store.pendingReviewCount > 0)
                _ReviewBanner(count: store.pendingReviewCount),
              SectionHeader(
                title: 'Giao dịch gần đây',
                actionLabel: 'Xem tất cả',
                onAction: widget.onOpenAll,
              ),
              if (store.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                )
              else if (store.recent.isEmpty)
                GlassCard(
                  child: EmptyHint(
                    icon: Icons.receipt_long_rounded,
                    title: 'Chưa có giao dịch nào',
                    subtitle: 'Thêm tay hoặc bật đọc MB Bank trong Cài đặt '
                        'để app tự ghi mọi khoản.',
                    action: _GlowButton(
                      label: 'Thêm giao dịch',
                      icon: Icons.add_rounded,
                      onTap: widget.onAdd,
                    ),
                  ),
                )
              else
                GlassCard(
                  padding: EdgeInsets.zero,
                  radius: AppRadius.list,
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < store.recent.length; i++)
                        TransactionRow(
                          transaction: store.recent[i],
                          showDivider: i != store.recent.length - 1,
                          onTap: () => _showDetail(store.recent[i]),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              const _SourceFooter(),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(Transaction tx) {
    EditTransactionSheet.show(context, tx);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final String greeting = switch (DateTime.now().hour) {
      >= 5 && < 11 => 'Chào buổi sáng',
      >= 11 && < 14 => 'Chào buổi trưa',
      >= 14 && < 18 => 'Chào buổi chiều',
      _ => 'Chào buổi tối',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [AppColors.neonCyan, Color(0xFF0077FF)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
              boxShadow: AppColors.liquidGlow(AppColors.neonCyan, blur: 12),
            ),
            alignment: Alignment.center,
            child: const Text(
              'H',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$greeting, Hoàng',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.neonCyan,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.fullDate(DateTime.now()).split(',').first,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            icon: Icons.category_rounded,
            label: 'Danh mục',
            onTap: () => Navigator.of(context).pushNamed(ManageCategoriesPage.route),
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: Icons.tune_rounded,
            label: 'Cài đặt',
            onTap: () => Navigator.of(context).pushNamed(SettingsPage.route),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: AppColors.strokeFaint),
          ),
          child: Icon(icon, size: 18, color: AppColors.inkDim),
        ),
      ),
    );
  }
}

/// Nudge to fix rows the parser could not confidently categorise.
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pushNamed('/review'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            color: AppColors.coral.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.coral.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppColors.coral),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count giao dịch cần bạn xác nhận phân loại',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.coral),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceFooter extends StatelessWidget {
  const _SourceFooter();

  @override
  Widget build(BuildContext context) {
    final SettingsRepository s = context.watch<SettingsRepository>();
    final bool sepay = s.sepayEnabled;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: sepay ? AppColors.neonCyan : AppColors.inkFaint,
            boxShadow: sepay ? AppColors.neonGlow(AppColors.neonCyan, blur: 6) : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          sepay
              ? 'TỰ ĐỘNG KÉO CHI TIÊU QUA SEPAY (MB BANK)'
              : 'CHƯA KÍCH HOẠT SEPAY · CHẠM CÀI ĐẶT ĐỂ BẬT',
          style: const TextStyle(
            fontFamily: 'Courier New',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.inkDim,
          ),
        ),
      ],
    );
  }
}

class _GlowButton extends StatelessWidget {
  const _GlowButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.mintDeep,
        foregroundColor: const Color(0xFF04231A),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}

/// Minimal detail sheet with the raw SMS visible — important when a parse was
/// wrong and the user wants to see exactly what the bank said.
class _QuickDetailSheet extends StatelessWidget {
  const _QuickDetailSheet({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final String amount = transaction.type == TxType.transfer
        ? Fmt.amount(transaction.amount)
        : Fmt.signed(transaction.signedAmount);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgMid,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        22 + MediaQuery.of(context).padding.bottom,
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
          const SizedBox(height: 20),
          Text(
            amount,
            style: AppText.balance.copyWith(
              fontSize: 28,
              color: transaction.isIncome ? AppColors.mint : AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            transaction.description,
            style: const TextStyle(fontSize: 14, color: AppColors.ink),
          ),
          const SizedBox(height: 18),
          _DetailRow('Thời gian', Fmt.fullDate(transaction.occurredAt) +
              ' · ${Fmt.time(transaction.occurredAt)}'),
          _DetailRow('Nguồn', transaction.source.badge),
          if (transaction.referenceNumber != null)
            _DetailRow('Mã tham chiếu', transaction.referenceNumber!),
          if (transaction.rawText != null) ...<Widget>[
            const SizedBox(height: 14),
            const Text(
              'Tin nhắn gốc',
              style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: AppColors.strokeFaint),
              ),
              child: SelectableText(
                transaction.rawText!,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.55,
                  color: AppColors.inkDim,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
