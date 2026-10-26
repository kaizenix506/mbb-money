import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../category_ref.dart';

/// Selectable category pills, laid out for a sheet.
///
/// Two problems this solves, both reported by Hoàng:
///  * a plain `Wrap` of chips could overflow horizontally, because a chip whose
///    label was longer than the remaining line had nowhere to break;
///  * the list only ever contained the built-in categories, so a category the
///    user created himself could not be chosen here at all.
///
/// [categories] is therefore supplied by the caller from the store, and every
/// chip gets its own width budget so long custom names truncate instead of
/// throwing a RenderFlex overflow.
class CategoryChipGrid extends StatelessWidget {
  const CategoryChipGrid({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.onAddCategory,
    super.key,
  });

  final List<CategoryRef> categories;
  final String? selectedId;
  final ValueChanged<CategoryRef> onSelected;

  /// Optional "create a new one" affordance appended at the end.
  final Future<void> Function()? onAddCategory;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      for (final CategoryRef c in categories)
        _Chip(
          category: c,
          selected: c.id == selectedId,
          onTap: () => onSelected(c),
        ),
      if (onAddCategory != null) _AddChip(onTap: onAddCategory!),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = 8;
        // Two columns on a phone, three on a wide sheet. Doing the maths here
        // keeps each pill a fixed width, so truncation is predictable.
        final int columns = constraints.maxWidth > 420 ? 3 : 2;
        final double width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CategoryRef category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = category.tint;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: selected
              ? tint.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? tint.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.07),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(category.icon, size: 14, color: selected ? tint : AppColors.inkDim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.ink : AppColors.inkDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: AppColors.neonYellow.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.add_rounded, size: 14, color: AppColors.neonYellow),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Thêm mục',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neonYellow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
