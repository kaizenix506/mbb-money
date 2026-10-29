import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/transaction.dart';
import '../../data/models/wishlist_item.dart';
import '../../data/stores/wishlist_store.dart';
import '../stores/transaction_store.dart';
import '../widgets/common.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  static const String route = '/wishlist';

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  int _tabFilter = 0; // 0: Tất cả, 1: Muốn mua, 2: Đã mua

  @override
  Widget build(BuildContext context) {
    final WishlistStore store = context.watch<WishlistStore>();

    final List<WishlistItem> filtered = switch (_tabFilter) {
      1 => store.planned,
      2 => store.bought,
      _ => store.all,
    };

    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'DỰ TOÁN MUA SẮM & WISHLIST',
          style: TextStyle(
            fontFamily: 'Courier New',
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.neonCyan,
            letterSpacing: 1.2,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.neonCyan, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          if (store.bought.isNotEmpty)
            IconButton(
              tooltip: 'Xóa các món đã mua',
              icon: const Icon(Icons.cleaning_services_rounded,
                  color: AppColors.neonPink, size: 20),
              onPressed: () => _confirmClearBought(context, store),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.neonCyan,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text(
          'Thêm món muốn mua',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        onPressed: () => _showAddOrEditSheet(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: <Widget>[
          // Budget Hero Card
          _BudgetSummaryCard(store: store),
          const SizedBox(height: 18),

          // Filter chips
          _FilterBar(
            selected: _tabFilter,
            counts: [store.all.length, store.planned.length, store.bought.length],
            onChanged: (int index) => setState(() => _tabFilter = index),
          ),
          const SizedBox(height: 14),

          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: GlassCard(
                child: EmptyHint(
                  icon: Icons.shopping_bag_outlined,
                  title: _tabFilter == 2
                      ? 'Chưa có món nào đã mua'
                      : 'Chưa có món đồ nào trong danh sách',
                  subtitle:
                      'Thêm các món bạn dự định mua kèm giá dự kiến để app tự tính ngân sách còn lại.',
                  action: FilledButton.icon(
                    onPressed: () => _showAddOrEditSheet(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Thêm món đồ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.mintDeep,
                      foregroundColor: const Color(0xFF04231A),
                    ),
                  ),
                ),
              ),
            )
          else
            for (final WishlistItem item in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _WishlistTile(
                  item: item,
                  onToggle: (bool val) => store.toggleBought(item.id, val),
                  onDelete: () => store.deleteItem(item.id),
                  onEdit: () => _showAddOrEditSheet(context, existing: item),
                  onConvertToTx: () => _recordAsTransaction(context, item),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _recordAsTransaction(
      BuildContext context, WishlistItem item) async {
    final TransactionStore txStore = context.read<TransactionStore>();
    final int amount = item.effectivePrice;
    await txStore.addManual(
      type: TxType.expense,
      amount: amount,
      occurredAt: item.boughtAt ?? DateTime.now(),
      description: item.title,
      categoryId: 'shopping',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.bgMid,
        content: Text(
          'Đã ghi nhận "${item.title}" (${Fmt.dong(amount)}) vào sổ chi tiêu!',
          style: const TextStyle(color: AppColors.neonGreen),
        ),
      ),
    );
  }

  Future<void> _confirmClearBought(
      BuildContext context, WishlistStore store) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.bgMid,
        title: const Text('XÓA MÓN ĐÃ MUA',
            style: TextStyle(color: AppColors.ink)),
        content: Text(
          'Bạn có chắc muốn xóa toàn bộ ${store.bought.length} món đồ đã mua khỏi danh sách?',
          style: const TextStyle(color: AppColors.inkDim),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy', style: TextStyle(color: AppColors.inkFaint)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.neonPink),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa hết', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.clearBought();
    }
  }

  Future<void> _showAddOrEditSheet(BuildContext context,
      {WishlistItem? existing}) async {
    final TextEditingController titleCtrl =
        TextEditingController(text: existing?.title ?? '');
    final TextEditingController priceCtrl = TextEditingController(
      text: existing != null ? existing.expectedPrice.toString() : '',
    );
    final TextEditingController notesCtrl =
        TextEditingController(text: existing?.notes ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: Color(0xF20A0F1D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border:
                  Border(top: BorderSide(color: AppColors.neonCyan, width: 1.4)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    existing == null
                        ? 'THÊM MÓN ĐỒ MUỐN MUA'
                        : 'CHỈNH SỬA MÓN ĐỒ',
                    style: const TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonCyan,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(
                        color: AppColors.ink, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Tên món đồ',
                      labelStyle: const TextStyle(color: AppColors.inkDim),
                      hintText: 'Ví dụ: Tai nghe AirPods, Giày sneaker...',
                      hintStyle: const TextStyle(color: AppColors.inkFaint),
                      filled: true,
                      fillColor: const Color(0x6604060C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.glassBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.neonYellow,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Giá dự kiến (VNĐ)',
                      labelStyle: const TextStyle(color: AppColors.inkDim),
                      hintText: '500000',
                      hintStyle: const TextStyle(color: AppColors.inkFaint),
                      filled: true,
                      fillColor: const Color(0x6604060C),
                      suffixText: 'đ',
                      suffixStyle: const TextStyle(color: AppColors.neonYellow),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.glassBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Quick price shortcuts
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final int p in [
                          100000,
                          200000,
                          500000,
                          1000000,
                          2000000,
                          5000000,
                          10000000
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              backgroundColor: const Color(0x33101C32),
                              side: const BorderSide(
                                  color: AppColors.strokeFaint),
                              label: Text(
                                Fmt.compact(p),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.neonCyan,
                                    fontWeight: FontWeight.w700),
                              ),
                              onPressed: () => priceCtrl.text = p.toString(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    style: const TextStyle(color: AppColors.ink),
                    decoration: InputDecoration(
                      labelText: 'Ghi chú thêm (tuỳ chọn)',
                      labelStyle: const TextStyle(color: AppColors.inkDim),
                      hintText: 'Link mua hàng, màu sắc, nơi bán...',
                      hintStyle: const TextStyle(color: AppColors.inkFaint),
                      filled: true,
                      fillColor: const Color(0x6604060C),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.glassBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.neonCyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        final String title = titleCtrl.text.trim();
                        final int? price =
                            int.tryParse(priceCtrl.text.replaceAll(RegExp(r'\D'), ''));
                        if (title.isEmpty) return;
                        final WishlistStore store = context.read<WishlistStore>();
                        if (existing == null) {
                          await store.addItem(
                            title: title,
                            expectedPrice: price ?? 0,
                            notes: notesCtrl.text.trim(),
                          );
                        } else {
                          await store.updateItem(
                            existing.copyWith(
                              title: title,
                              expectedPrice: price ?? existing.expectedPrice,
                              notes: notesCtrl.text.trim(),
                            ),
                          );
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: Text(
                        existing == null ? 'LƯU MÓN ĐỒ' : 'CẬP NHẬT',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({required this.store});

  final WishlistStore store;

  @override
  Widget build(BuildContext context) {
    final int remaining = store.remainingBudget;
    final int budget = store.totalBudget;
    final int planned = store.totalPlanned;
    final int bought = store.totalBought;
    final bool isOverBudget = remaining < 0;

    final double progress = budget <= 0
        ? 0.0
        : (store.totalCommitted / budget).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xB00B1120),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isOverBudget
              ? AppColors.neonPink.withValues(alpha: 0.6)
              : AppColors.neonCyan.withValues(alpha: 0.5),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: isOverBudget
                ? AppColors.neonPink.withValues(alpha: 0.18)
                : AppColors.neonCyan.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header: Edit Budget Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOverBudget
                          ? AppColors.neonPink
                          : AppColors.neonGreen,
                      boxShadow: [
                        BoxShadow(
                          color: isOverBudget
                              ? AppColors.neonPink
                              : AppColors.neonGreen,
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOverBudget
                        ? 'CẢNH BÁO: VƯỢT NGÂN SÁCH'
                        : 'TỔNG NGÂN SÁCH CÒN LẠI',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: isOverBudget
                          ? AppColors.neonPink
                          : AppColors.neonGreen,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _editBudgetDialog(context, store),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x6604060C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.strokeFaint),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note_rounded,
                          size: 15, color: AppColors.neonCyan),
                      SizedBox(width: 4),
                      Text(
                        'Điền ngân sách',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neonCyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Main Remaining Amount
          Text(
            Fmt.dong(remaining),
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: isOverBudget ? AppColors.neonPink : AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                isOverBudget ? AppColors.neonPink : AppColors.neonCyan,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3 sub-metrics in horizontal glass box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x6604060C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.strokeFaint),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _SubStat(
                  label: 'TỔNG NGÂN SÁCH',
                  value: Fmt.dong(budget),
                  color: AppColors.neonCyan,
                ),
                Container(width: 1, height: 26, color: AppColors.strokeFaint),
                _SubStat(
                  label: 'DỰ KIẾN MUA',
                  value: Fmt.dong(planned),
                  color: AppColors.neonYellow,
                ),
                Container(width: 1, height: 26, color: AppColors.strokeFaint),
                _SubStat(
                  label: 'ĐÃ MUA',
                  value: Fmt.dong(bought),
                  color: AppColors.neonGreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editBudgetDialog(
      BuildContext context, WishlistStore store) async {
    final TextEditingController ctrl = TextEditingController(
      text: store.totalBudget > 0 ? store.totalBudget.toString() : '',
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: Color(0xF20A0F1D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border:
                  Border(top: BorderSide(color: AppColors.neonCyan, width: 1.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'ĐIỀN TỔNG NGÂN SÁCH MUA SẮM',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonCyan,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Số tiền bạn dự định chi tiêu cho các món đồ. Mỗi khi bạn thêm món muốn mua kèm giá, hệ thống sẽ tự động trừ bớt để hiển thị số tiền còn lại. Khi bạn tích "đã mua", khoản tiền đó vẫn bị trừ khỏi ngân sách (không được hoàn lại).',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.inkDim, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonGreen,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Nhập ngân sách (ví dụ: 10000000)',
                    hintStyle:
                        const TextStyle(fontSize: 14, color: AppColors.inkFaint),
                    suffixText: 'đ',
                    suffixStyle: const TextStyle(color: AppColors.neonGreen),
                    filled: true,
                    fillColor: const Color(0x6604060C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.glassBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final int b in [
                        1000000,
                        2000000,
                        5000000,
                        10000000,
                        20000000,
                        50000000
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            backgroundColor: const Color(0x33101C32),
                            side: const BorderSide(color: AppColors.strokeFaint),
                            label: Text(
                              Fmt.compact(b),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.neonCyan,
                                  fontWeight: FontWeight.w700),
                            ),
                            onPressed: () => ctrl.text = b.toString(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.neonCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      final int amount = int.tryParse(
                              ctrl.text.replaceAll(RegExp(r'\D'), '')) ??
                          0;
                      await store.setTotalBudget(amount);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text('LƯU NGÂN SÁCH',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubStat extends StatelessWidget {
  const _SubStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Courier New',
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final int selected;
  final List<int> counts;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = ['Tất cả', 'Chưa mua', 'Đã mua'];
    return Row(
      children: [
        for (int i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < labels.length - 1 ? 8 : 0),
              child: InkWell(
                onTap: () => onChanged(i),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? AppColors.neonCyan.withValues(alpha: 0.18)
                        : const Color(0x33101C32),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected == i
                          ? AppColors.neonCyan
                          : AppColors.strokeFaint,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${labels[i]} (${counts[i]})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected == i
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: selected == i
                            ? AppColors.neonCyan
                            : AppColors.inkDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WishlistTile extends StatelessWidget {
  const _WishlistTile({
    required this.item,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
    required this.onConvertToTx,
  });

  final WishlistItem item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onConvertToTx;

  @override
  Widget build(BuildContext context) {
    final bool bought = item.isBought;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bought
            ? const Color(0x22101C32)
            : const Color(0x44101C32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: bought
              ? AppColors.neonGreen.withValues(alpha: 0.3)
              : AppColors.glassBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Checkbox toggle
          InkWell(
            onTap: () => onToggle(!bought),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bought
                    ? AppColors.neonGreen.withValues(alpha: 0.2)
                    : Colors.transparent,
                border: Border.all(
                  color: bought ? AppColors.neonGreen : AppColors.inkDim,
                  width: 1.8,
                ),
              ),
              child: bought
                  ? const Icon(Icons.check_rounded,
                      size: 18, color: AppColors.neonGreen)
                  : null,
            ),
          ),
          const SizedBox(width: 12),

          // Title & Price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: bought ? AppColors.inkDim : AppColors.ink,
                    decoration: bought ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      Fmt.dong(item.expectedPrice),
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: bought
                            ? AppColors.inkFaint
                            : AppColors.neonYellow,
                      ),
                    ),
                    if (bought) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.neonGreen, width: 0.8),
                        ),
                        child: const Text(
                          'ĐÃ MUA',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: AppColors.neonGreen,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.notes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.inkFaint),
                  ),
                ],
              ],
            ),
          ),

          // Action buttons
          if (bought)
            IconButton(
              tooltip: 'Ghi vào Sổ chi tiêu',
              icon: const Icon(Icons.playlist_add_check_rounded,
                  color: AppColors.neonGreen, size: 22),
              onPressed: onConvertToTx,
            ),
          IconButton(
            tooltip: 'Sửa',
            icon: const Icon(Icons.edit_outlined,
                color: AppColors.inkDim, size: 18),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Xóa món này',
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.neonPink, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
