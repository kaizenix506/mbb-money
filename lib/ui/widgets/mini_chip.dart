import 'package:flutter/material.dart';

/// Small selectable pill used in sheets.
class MiniChip extends StatelessWidget {
  const MiniChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tint,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final Color accent = tint ?? const Color(0xFF3DE8B0);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: selected
              ? accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 13,
                color: selected ? accent : const Color(0xFF8B93A5),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFFF2F4F8)
                    : const Color(0xFF8B93A5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
