import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../data/stores/category_store.dart';

/// Screen allowing Hoang to manage, add custom categories, or delete existing categories.
class ManageCategoriesPage extends StatelessWidget {
  const ManageCategoriesPage({super.key});

  static const String route = '/categories';

  @override
  Widget build(BuildContext context) {
    final catStore = context.watch<CategoryStore>();

    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        title: const Text('QUẢN LÝ DANH MỤC CHI'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.neonCyan, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.neonCyan,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm danh mục mới', style: TextStyle(fontWeight: FontWeight.w800)),
        onPressed: () => _showAddDialog(context),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
        itemCount: catStore.all.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, idx) {
          final cat = catStore.all[idx];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x33101C32),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cat.tint.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
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
                    children: [
                      Text(
                        cat.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        cat.isCustom ? 'Danh mục tự tạo' : 'Danh mục hệ thống',
                        style: TextStyle(
                          fontSize: 11,
                          color: cat.isCustom ? AppColors.neonYellow : AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (cat.isCustom)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.neonPink, size: 20),
                    onPressed: () => catStore.removeCategory(cat.id),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final textCtrl = TextEditingController();
    Color selectedColor = AppColors.neonCyan;
    IconData selectedIcon = Icons.star_rounded;

    final List<Color> colors = [
      AppColors.neonCyan,
      AppColors.neonPink,
      AppColors.neonYellow,
      AppColors.neonGreen,
      AppColors.neonViolet,
      AppColors.neonOrange,
    ];

    final List<IconData> icons = [
      Icons.shopping_cart_rounded,
      Icons.flight_takeoff_rounded,
      Icons.pets_rounded,
      Icons.sports_soccer_rounded,
      Icons.music_note_rounded,
      Icons.work_outline_rounded,
      Icons.family_restroom_rounded,
      Icons.card_giftcard_rounded,
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Color(0xF00A0F1D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: AppColors.neonCyan)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TẠO DANH MỤC MỚI',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.neonCyan,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: textCtrl,
                style: const TextStyle(color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Tên danh mục (ví dụ: Nuôi mèo, Du lịch...)',
                  hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0x6604060C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Chọn màu sắc:', style: TextStyle(fontSize: 12, color: AppColors.inkDim)),
              const SizedBox(height: 6),
              Row(
                children: colors.map((c) {
                  final active = selectedColor == c;
                  return GestureDetector(
                    onTap: () => setModalState(() => selectedColor = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: active ? Border.all(color: Colors.white, width: 2.5) : null,
                        boxShadow: active ? AppColors.neonGlow(c, blur: 10) : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const Text('Chọn biểu tượng:', style: TextStyle(fontSize: 12, color: AppColors.inkDim)),
              const SizedBox(height: 6),
              Row(
                children: icons.map((ic) {
                  final active = selectedIcon == ic;
                  return GestureDetector(
                    onTap: () => setModalState(() => selectedIcon = ic),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: active ? selectedColor.withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? selectedColor : AppColors.strokeFaint),
                      ),
                      child: Icon(ic, color: active ? selectedColor : AppColors.inkDim, size: 20),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.neonCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () {
                    final label = textCtrl.text.trim();
                    if (label.isNotEmpty) {
                      context.read<CategoryStore>().addCategory(
                            label: label,
                            iconKey: 'pet',
                            color: selectedColor,
                          );
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: const Text('THÊM DANH MỤC', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
