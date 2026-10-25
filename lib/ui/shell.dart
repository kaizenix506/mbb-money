import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'chat/cyber_ai_chat_sheet.dart';

/// Floating Liquid Glass Navigation Bar
/// User requested: "cái nút dấu AI để ra giữa đi" -> AI Button is placed prominently in the DEAD CENTER!
/// With liquid frosted blur, neon glowing active states, and glowing outer aura.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    required this.index,
    required this.titles,
    required this.onChanged,
    required this.onAdd,
    super.key,
  });

  final int index;
  final List<String> titles;
  final ValueChanged<int> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                color: const Color(0xB8090E1B),
                border: Border.all(color: AppColors.glassBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.neonCyan.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: -2,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  // 1. Home / Overview Tab
                  _LiquidNavTab(
                    icon: Icons.grid_view_rounded,
                    label: titles.isNotEmpty ? titles[0] : 'Tổng quan',
                    selected: index == 0,
                    onTap: () => onChanged(0),
                  ),

                  // 2. Transactions List Tab
                  _LiquidNavTab(
                    icon: Icons.receipt_long_rounded,
                    label: titles.length > 1 ? titles[1] : 'Sổ chi',
                    selected: index == 1,
                    onTap: () => onChanged(1),
                  ),

                  // ⭐ CENTER: AI COGNITIVE CHATBOT BUTTON (A.R.I.A)
                  _CenterAiButton(
                    onTap: () => CyberAiChatSheet.show(context),
                  ),

                  // 3. Analytics / Reports Tab
                  _LiquidNavTab(
                    icon: Icons.analytics_outlined,
                    label: titles.length > 2 ? titles[2] : 'Báo cáo',
                    selected: index == 2,
                    onTap: () => onChanged(2),
                  ),

                  // 4. Quick Add Expense (+)
                  _QuickAddButton(onTap: onAdd),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidNavTab extends StatelessWidget {
  const _LiquidNavTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: selected ? AppColors.neonCyan.withValues(alpha: 0.16) : Colors.transparent,
          border: selected
              ? Border.all(color: AppColors.neonCyan.withValues(alpha: 0.6), width: 1)
              : null,
          boxShadow: selected ? AppColors.neonGlow(AppColors.neonCyan, blur: 10) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.neonCyan : AppColors.inkDim,
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.neonCyan,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Center AI Trigger Button
class _CenterAiButton extends StatelessWidget {
  const _CenterAiButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFB52BFF), Color(0xFF6B00D7)],
          ),
          border: Border.all(color: const Color(0xFFE580FF), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9D00FF).withValues(alpha: 0.6),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.psychology, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}

/// Quick Add Button
class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.neonPink.withValues(alpha: 0.2),
          border: Border.all(color: AppColors.neonPink.withValues(alpha: 0.6), width: 1.2),
          boxShadow: AppColors.neonGlow(AppColors.neonPink, blur: 8),
        ),
        child: const Icon(Icons.add_rounded, size: 22, color: AppColors.neonPink),
      ),
    );
  }
}
