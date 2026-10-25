import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../data/stores/category_store.dart';
import '../stores/transaction_store.dart';

/// Screen allowing Hoang to manage, add, edit, or delete ANY expense category
/// — including the built-in ones. Deleting a category re-buckets its existing
/// transactions into "Khác" so nothing is ever lost.
class ManageCategoriesPage extends StatelessWidget {
  const ManageCategoriesPage({super.key});

  static const String route = '/categories';

  @override
  Widget build(BuildContext context) {
    final CategoryStore catStore = context.watch<CategoryStore>();
    final List<CategoryItem> items = catStore.all;

    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        title: const Text('QUẢN LÝ DANH MỤC'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.neonCyan, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          if (catStore.hasDeletedDefaults)
            IconButton(
              tooltip: 'Khôi phục danh mục mặc định',
              icon: const Icon(Icons.restore_rounded, color: AppColors.neonYellow),
              onPressed: () => _confirmRestore(context),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.neonCyan,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm danh mục', style: TextStyle(fontWeight: FontWeight.w800)),
        onPressed: () => _showCategoryEditor(context),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
        itemCount: items.length + 1,
        separatorBuilder: (_, int i) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) {
          if (index == items.length) return const _DeleteHint();

          final CategoryItem cat = items[index];
          final bool locked = cat.id == 'other';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x33101C32),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cat.tint.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cat.tint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cat.tint.withValues(alpha: 0.5)),
                  ),
                  child: Icon(cat.icon, color: cat.tint, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        cat.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        locked
                            ? 'Danh mục dự phòng · không thể xóa'
                            : cat.isCustom
                                ? 'Danh mục tự tạo'
                                : 'Danh mục mặc định',
                        style: TextStyle(
                          fontSize: 11,
                          color: locked
                              ? AppColors.inkFaint
                              : cat.isCustom
                                  ? AppColors.neonYellow
                                  : AppColors.inkDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!locked) ...<Widget>[
                  IconButton(
                    tooltip: 'Sửa',
                    icon: const Icon(Icons.edit_outlined, color: AppColors.neonCyan, size: 19),
                    onPressed: () => _showCategoryEditor(context, existing: cat),
                  ),
                  IconButton(
                    tooltip: 'Xóa',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.neonPink, size: 20),
                    onPressed: () => _confirmDelete(context, cat),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Deletes a category, first moving every one of its transactions into the
  /// "Khác" bucket so the month totals never silently drop.
  Future<void> _confirmDelete(BuildContext context, CategoryItem cat) async {
    final TransactionStore txStore = context.read<TransactionStore>();
    final CategoryStore catStore = context.read<CategoryStore>();

    final int count = txStore.monthTransactions
        .where((dynamic t) => t.categoryId == cat.id)
        .length;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Xóa "${cat.label}"?', style: const TextStyle(color: AppColors.ink)),
        content: Text(
          count > 0
              ? '$count giao dịch trong tháng này đang dùng danh mục này.\n'
                  'Chúng sẽ được chuyển sang "Khác" — không mất số tiền nào.'
              : 'Danh mục này chưa có giao dịch nào trong tháng. Xóa luôn?',
          style: const TextStyle(color: AppColors.inkDim, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.neonPink),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    final int moved = await txStore.migrateCategoryTransactions(cat.id, catStore.fallback.id);
    await catStore.removeCategory(cat.id);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0A0F1D),
        content: Text(
          moved > 0
              ? 'Đã xóa "${cat.label}" và chuyển $moved giao dịch sang "Khác".'
              : 'Đã xóa danh mục "${cat.label}".',
          style: const TextStyle(color: AppColors.ink),
        ),
      ),
    );
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final CategoryStore catStore = context.read<CategoryStore>();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Khôi phục danh mục mặc định?', style: TextStyle(color: AppColors.ink)),
        content: const Text(
          'Tất cả danh mục hệ thống sẽ xuất hiện lại.\nDanh mục tự tạo của bạn vẫn được giữ.',
          style: TextStyle(color: AppColors.inkDim, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.neonCyan),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );
    if (ok == true) await catStore.restoreDefaults();
  }

  Future<void> _showCategoryEditor(BuildContext context, {CategoryItem? existing}) async {
    final TextEditingController textCtrl = TextEditingController(text: existing?.label ?? '');
    Color selectedColor = existing != null ? Color(existing.colorValue) : AppColors.neonCyan;
    String selectedIconKey = existing?.iconKey ?? 'food';

    const List<Color> colors = <Color>[
      AppColors.neonCyan,
      AppColors.neonPink,
      AppColors.neonYellow,
      AppColors.neonGreen,
      AppColors.neonViolet,
      AppColors.neonOrange,
    ];

    const List<String> iconKeys = <String>[
      'food',
      'coffee',
      'shopping',
      'flight',
      'pet',
      'sport',
      'music',
      'gift',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setModalState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              decoration: const BoxDecoration(
                color: Color(0xF20A0F1D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: AppColors.neonCyan, width: 1.4)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      existing == null ? 'TẠO DANH MỤC MỚI' : 'SỬA DANH MỤC',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.neonCyan,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: textCtrl,
                      autofocus: existing == null,
                      style: const TextStyle(color: AppColors.ink),
                      decoration: InputDecoration(
                        hintText: 'Tên danh mục (ví dụ: Nuôi mèo, Du lịch...)',
                        hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0x6604060C),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Màu sắc', style: TextStyle(fontSize: 12, color: AppColors.inkDim)),
                    const SizedBox(height: 8),
                    Row(
                      children: colors.map((Color c) {
                        final bool active = selectedColor == c;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedColor = c),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: active ? Border.all(color: Colors.white, width: 2.5) : null,
                              boxShadow: active ? AppColors.liquidGlow(c, blur: 12) : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Biểu tượng', style: TextStyle(fontSize: 12, color: AppColors.inkDim)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: iconKeys.map((String key) {
                        final bool active = selectedIconKey == key;
                        final IconData ic = categoryIconMap[key] ?? Icons.category_rounded;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedIconKey = key),
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: active ? selectedColor.withValues(alpha: 0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: active ? selectedColor : AppColors.strokeFaint,
                                width: active ? 1.6 : 1,
                              ),
                            ),
                            child: Icon(ic, color: active ? selectedColor : AppColors.inkDim, size: 21),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.neonCyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          final String label = textCtrl.text.trim();
                          if (label.isEmpty) return;
                          final CategoryStore store = context.read<CategoryStore>();
                          if (existing == null) {
                            await store.addCategory(
                              label: label,
                              iconKey: selectedIconKey,
                              color: selectedColor,
                            );
                          } else {
                            await store.updateCategory(
                              existing.id,
                              label: label,
                              iconKey: selectedIconKey,
                              color: selectedColor,
                            );
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: Text(
                          existing == null ? 'THÊM DANH MỤC' : 'LƯU THAY ĐỔI',
                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
                        ),
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
}

class _DeleteHint extends StatelessWidget {
  const _DeleteHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.neonYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, color: AppColors.neonYellow, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bấm 🗑️ để xóa bất kỳ danh mục nào. Giao dịch cũ của danh mục bị xóa sẽ '
              'tự động chuyển sang "Khác" — tổng chi tiêu không thay đổi.\n'
              'Tổng đang quản lý: ${context.watch<CategoryStore>().all.length} danh mục.',
              style: const TextStyle(fontSize: 11.5, height: 1.5, color: AppColors.inkDim),
            ),
          ),
        ],
      ),
    );
  }
}
