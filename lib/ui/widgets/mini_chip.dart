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
              ? accent.withValues(alpha: 0.28)
              : accent.withValues(alpha: 0.08),
          border: Border.all(
            color: selected
                ? accent
                : accent.withValues(alpha: 0.28),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 13.5,
                color: accent,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? const Color(0xFFF2F4F8)
                    : const Color(0xFFD0D7E5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
