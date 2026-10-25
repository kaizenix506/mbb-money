import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../../data/stores/category_store.dart';
import '../stores/transaction_store.dart';

/// Interactive Sheet to Edit, Re-categorize, or Delete any Transaction
/// directly requested by Hoang: "chỉnh sửa phân loại các giao dịch, tùy chỉnh xóa hoặc thêm các mục"
class EditTransactionSheet extends StatefulWidget {
  const EditTransactionSheet({required this.transaction, super.key});

  final Transaction transaction;

  static Future<void> show(BuildContext context, Transaction transaction) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditTransactionSheet(transaction: transaction),
    );
  }

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  late TextEditingController _descCtrl;
  late TextEditingController _amountCtrl;
  late String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.transaction.description);
    _amountCtrl = TextEditingController(text: widget.transaction.amount.toString());
    _selectedCategoryId = widget.transaction.categoryId;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catStore = context.watch<CategoryStore>();
    final txStore = context.watch<TransactionStore>();
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: viewInsets),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
            decoration: BoxDecoration(
              color: const Color(0xF00A0F1D),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.all(color: AppColors.glassBorder, width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.inkFaint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'CHỈNH SỬA CHI TIÊU',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.neonCyan,
                        letterSpacing: 1.2,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.neonPink),
                      tooltip: 'Xóa giao dịch này',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF0F172A),
                            title: const Text('Xác nhận xóa?', style: TextStyle(color: AppColors.ink)),
                            content: const Text(
                              'Khoản chi này sẽ bị xóa vĩnh viễn khỏi sổ.',
                              style: TextStyle(color: AppColors.inkDim),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Hủy'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: AppColors.neonPink),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Xóa ngay'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          await txStore.delete(widget.transaction);
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Amount Field
                const Text('SỐ TIỀN (VNĐ)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkDim)),
                const SizedBox(height: 6),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonPink,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0x6604060C),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.glassBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),

                // Description Field
                const Text('NỘI DUNG CHI TIÊU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkDim)),
                const SizedBox(height: 6),
                TextField(
                  controller: _descCtrl,
                  style: const TextStyle(color: AppColors.ink, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0x6604060C),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.glassBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),

                // Category Selector Chips
                const Text('PHÂN LOẠI DANH MỤC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkDim)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: catStore.all.map((c) {
                    final selected = _selectedCategoryId == c.id;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon, size: 14, color: selected ? Colors.black : c.tint),
                          const SizedBox(width: 6),
                          Text(c.label),
                        ],
                      ),
                      selected: selected,
                      selectedColor: c.tint,
                      backgroundColor: const Color(0x40162238),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.black : AppColors.ink,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategoryId = c.id);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final newAmt = int.tryParse(_amountCtrl.text.trim()) ?? widget.transaction.amount;
                      final newDesc = _descCtrl.text.trim();
                      final updated = widget.transaction.copyWith(
                        amount: newAmt,
                        description: newDesc.isEmpty ? widget.transaction.description : newDesc,
                        categoryId: _selectedCategoryId,
                      );
                      await txStore.setCategory(updated, Category.byId(_selectedCategoryId));
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.neonCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      shadowColor: AppColors.neonCyan.withValues(alpha: 0.5),
                    ),
                    child: const Text(
                      'LƯU THAY ĐỔI',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0),
                    ),
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
