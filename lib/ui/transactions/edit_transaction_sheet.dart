import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/vn_clock.dart';
import '../../data/models/transaction.dart';
import '../category_ref.dart';
import '../categories/manage_categories_page.dart';
import '../stores/transaction_store.dart';
import '../widgets/category_chip_grid.dart';

/// Interactive Sheet to Edit, Re-categorize, or Delete any Transaction
/// directly requested by Hoang: "chỉnh sửa phân loại các giao dịch, tùy chỉnh xóa hoặc thêm các mục"
class EditTransactionSheet extends StatefulWidget {
  const EditTransactionSheet({required this.transaction, super.key});

  final Transaction transaction;

  static Future<void> show(BuildContext context, Transaction transaction) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
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
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.transaction.description);
    _amountCtrl = TextEditingController(text: widget.transaction.amount.toString());
    _selectedCategoryId = widget.transaction.categoryId;
    _date = widget.transaction.occurredAt;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TransactionStore txStore = context.watch<TransactionStore>();
    final List<CategoryRef> choices =
        context.categories.choicesFor(isIncome: widget.transaction.isIncome);
    final double viewInsets = MediaQuery.of(context).viewInsets.bottom;

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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.glassBorder)),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.glassBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),

                // Category selector — laid out as a grid, because a wrapping
                // row of chips overflowed once there were more than a handful
                // of categories.
                const Text('PHÂN LOẠI DANH MỤC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkDim)),
                const SizedBox(height: 8),
                CategoryChipGrid(
                  categories: choices,
                  selectedId: _selectedCategoryId,
                  onSelected: (CategoryRef c) =>
                      setState(() => _selectedCategoryId = c.id),
                  onAddCategory: () async {
                    await Navigator.of(context).pushNamed(ManageCategoriesPage.route);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 18),

                // Date Time Field
                const Text('THỜI GIAN GIAO DỊCH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.inkDim)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0x6604060C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 18, color: AppColors.neonCyan),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${Fmt.fullDate(_date)} · ${Fmt.time(_date)}',
                            style: const TextStyle(
                              fontFamily: 'Courier New',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.inkFaint),
                      ],
                    ),
                  ),
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
                        occurredAt: _date,
                      );
                      await txStore.updateTransaction(updated);
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

  Future<void> _pickDate() async {
    final DateTime now = VnClock.localNow();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: 'Ngày giao dịch',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.neonCyan,
              surface: AppColors.bgMid,
              onSurface: AppColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;

    if (!mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Giờ giao dịch',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.neonCyan,
              surface: AppColors.bgMid,
              onSurface: AppColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return;

    setState(() {
      _date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }
}
