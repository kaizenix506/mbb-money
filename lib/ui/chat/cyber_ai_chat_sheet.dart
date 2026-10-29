import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/vn_clock.dart';
import '../../data/models/transaction.dart';
import '../../data/services/cyber_ai_service.dart';
import '../category_ref.dart';
import '../stores/transaction_store.dart';
import '../../data/stores/wishlist_store.dart';
import '../transactions/edit_transaction_sheet.dart';

class CyberAiChatSheet extends StatefulWidget {
  const CyberAiChatSheet({super.key});

  static Future<void> show(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => const CyberAiChatSheet(),
    );
  }

  @override
  State<CyberAiChatSheet> createState() => _CyberAiChatSheetState();
}

class _CyberAiChatSheetState extends State<CyberAiChatSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<String> _quickPrompts = [
    'uống nước 20k',
    'ăn sáng 10k',
    'cafe 35k',
    'grab 45k',
    'đổi ngân sách mua sắm thành 5 triệu',
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    final aiService = context.read<CyberAiService>();
    final txStore = context.read<TransactionStore>();
    final wishlist = context.read<WishlistStore>();

    // The month list alone leaves "hôm nay" empty whenever today falls outside
    // the month currently loaded (or before the first fetch completes), which is
    // what produced the bogus "không có chi tiêu nào". Union it with the recent
    // window and de-duplicate by id.
    final Map<int, Transaction> byId = <int, Transaction>{};
    for (final Transaction t in txStore.monthTransactions) {
      if (t.isExpense) byId[t.id] = t;
    }
    final DateTime now = VnClock.localNow();
    final DateTime last7 = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    for (final Transaction t in txStore.rangeRows) {
      if (t.isExpense && !t.occurredAt.isBefore(last7)) {
        byId[t.id] = t;
      }
    }
    final expenses = byId.values.toList()
      ..sort((Transaction a, Transaction b) => b.occurredAt.compareTo(a.occurredAt));

    // id → label of every category Hoàng actually has, custom ones included,
    // so the model can answer with one of them instead of falling back to
    // "Khác".
    final Map<String, String> labels = <String, String>{
      for (final CategoryRef c in context.categories.choicesFor(isIncome: false))
        if (c.id != 'other') c.id: c.label,
    };

    _scrollToBottom();

    final started = DateTime.now();
    final turn = await aiService.sendMessage(
      text,
      currentExpenses: expenses,
      categoryLabels: labels,
      currentBudget: wishlist.totalBudget,
      committedBudget: wishlist.totalCommitted,
    );

    if (!mounted) return;

    // A budget command mutates the wishlist, not the ledger. Applying it here
    // is what makes "đổi ngân sách thành 5 triệu" actually work.
    if (turn.setBudget != null) {
      await wishlist.setTotalBudget(turn.setBudget!);
      if (!mounted) return;
      _scrollToBottom();
      _showSnack('Đã cập nhật ngân sách mua sắm: '
          '${Fmt.dong(wishlist.totalBudget)}');
    }

    final ExtractedExpense? extracted = turn.expense;
    if (extracted != null) {
      // Automatically commit the expense to SQLite!
      final tx = await txStore.addManual(
        type: TxType.expense,
        amount: extracted.amount,
        occurredAt: extracted.date ?? VnClock.localNow(),
        description: extracted.description,
        categoryId: extracted.category,
      );
      debugPrint('A.R.I.A ghi sổ trong '
          '${DateTime.now().difference(started).inMilliseconds}ms');
      if (!mounted) return;
      _scrollToBottom();
      _showSnack('Đã ghi vào sổ: ${extracted.description} · '
          '${Fmt.dong(extracted.amount)} → ${extracted.categoryName} '
          '(mã #${tx.id})');
    }
  }

  /// Small confirmation toast so an action taken by A.R.I.A is visible even
  /// when the chat bubble has already scrolled out of view.
  void _showSnack(String message) {
    if (!mounted) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Opens the category picker for a row the AI just filed, so a wrong guess is
  /// one tap away from being corrected rather than needing a manual edit.
  Future<void> _refile(ExtractedExpense e) async {
    final txStore = context.read<TransactionStore>();
    final match = txStore.monthTransactions
        .where((t) =>
            t.amount == e.amount && t.description == e.description)
        .toList(growable: false);
    if (match.isEmpty) return;
    await EditTransactionSheet.show(context, match.first);
  }

  @override
  Widget build(BuildContext context) {
    final aiService = context.watch<CyberAiService>();
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
        height: MediaQuery.of(context).size.height *
            (viewInsets > 0 ? 0.92 : 0.86),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xE0050812),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonViolet.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Top Header Handle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    border: const Border(bottom: BorderSide(color: AppColors.glassBorder)),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.neonViolet.withValues(alpha: 0.15),
                        Colors.transparent,
                        AppColors.neonCyan.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.neonViolet.withValues(alpha: 0.2),
                          border: Border.all(color: AppColors.neonViolet),
                        ),
                        child: const Icon(Icons.psychology, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'A.R.I.A COGNITIVE',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.neonGreen.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.neonGreen, width: 0.8),
                                  ),
                                  child: Text(
                                    aiService.activeModelLabel,
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.neonGreen,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'Trợ lý tự động phân loại & ghi sổ chi tiêu cho Hoàng',
                              style: TextStyle(fontSize: 11.5, color: AppColors.inkDim),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.inkDim),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Messages Scroll
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: aiService.messages.length + (aiService.isThinking ? 1 : 0),
                    itemBuilder: (context, idx) {
                      if (idx == aiService.messages.length) {
                        return _buildThinking();
                      }
                      final msg = aiService.messages[idx];
                      return _buildMessage(msg);
                    },
                  ),
                ),

                // Fast prompt chips
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickPrompts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final p = _quickPrompts[idx];
                      return ActionChip(
                        label: Text(
                          p,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.neonCyan,
                          ),
                        ),
                        backgroundColor: AppColors.glassPanel,
                        side: BorderSide(color: AppColors.neonCyan.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onPressed: () => _handleSend(p),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Bottom Input
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                  decoration: const BoxDecoration(
                    color: Color(0xE0050812),
                    border: Border(top: BorderSide(color: AppColors.glassBorder)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C1222),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: TextField(
                            controller: _textCtrl,
                            style: const TextStyle(color: AppColors.ink, fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'Nói với AI: "ăn trưa hết 35k", "mua sách 120k"...',
                              hintStyle: TextStyle(color: AppColors.inkFaint, fontSize: 13),
                              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: InputBorder.none,
                            ),
                            onSubmitted: _handleSend,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.neonCyan, Color(0xFFB52BFF)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppColors.liquidGlow(AppColors.neonCyan, blur: 12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                          onPressed: () => _handleSend(_textCtrl.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    final isUser = msg.isUser;
    final extracted = msg.extractedTx;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0x3DFF0055) : const Color(0x33101B30),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(
            color: isUser
                ? AppColors.neonPink.withValues(alpha: 0.6)
                : AppColors.neonCyan.withValues(alpha: 0.4),
          ),
          boxShadow: isUser
              ? AppColors.neonGlow(AppColors.neonPink, blur: 10)
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.neonCyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'A.R.I.A INTELLIGENCE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.neonCyan,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(
              msg.text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.ink,
                height: 1.45,
              ),
            ),
            if (extracted != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.neonGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.neonGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ĐÃ TỰ ĐỘNG LƯU: ${extracted.description} (${Fmt.dong(extracted.amount)}) → ${extracted.categoryName}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neonGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (msg.latencyMs != null && !isUser)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${msg.modelName != null ? "${msg.modelName} · " : ""}${msg.latencyMs}ms',
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: msg.latencyMs! < 900
                            ? AppColors.neonGreen
                            : AppColors.inkFaint,
                      ),
                    ),
                  ),
                if (!isUser && extracted != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _refile(extracted),
                      child: const Text(
                        'SỬA MỤC',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: AppColors.neonYellow,
                        ),
                      ),
                    ),
                  ),
                Text(
                  Fmt.time(msg.timestamp),
                  style: const TextStyle(fontSize: 10, color: AppColors.inkFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinking() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.glassPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonCyan),
            ),
            SizedBox(width: 10),
            Text(
              'A.R.I.A đang trích xuất dữ liệu chi tiêu cho Hoàng...',
              style: TextStyle(fontSize: 12, color: AppColors.neonCyan),
            ),
          ],
        ),
      ),
    );
  }
}
