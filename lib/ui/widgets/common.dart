import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../../data/models/tx_source.dart';

export 'share_ring.dart';

/// The little tinted square with a category glyph used on every list row.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    required this.category,
    this.size = 44,
    this.iconSize = 20,
    super.key,
  });

  final Category? category;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final Category c = category ?? Category.other;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        color: c.tint.withValues(alpha: 0.14),
      ),
      child: Icon(c.icon, size: iconSize, color: c.tint),
    );
  }
}

/// A transaction row: tile, merchant, meta line, amount, source badge.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    required this.transaction,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final Transaction transaction;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final Category? cat = Category.byId(transaction.categoryId);
    final bool income = transaction.isIncome;

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: <Widget>[
          CategoryTile(category: cat),
          const SizedBox(width: 14),
          Expanded(child: _Middle(transaction: transaction, cat: cat)),
          const SizedBox(width: 10),
          _AmountColumn(transaction: transaction, income: income),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: <Widget>[
            content,
            if (showDivider)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 74,
                color: AppColors.strokeFaint,
              ),
          ],
        ),
      ),
    );
  }
}

class _Middle extends StatelessWidget {
  const _Middle({required this.transaction, required this.cat});

  final Transaction transaction;
  final Category? cat;

  @override
  Widget build(BuildContext context) {
    final String meta =
        '${cat?.label ?? 'Chưa phân loại'} · ${Fmt.time(transaction.occurredAt)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          transaction.description.isEmpty ? '(không nội dung)' : transaction.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.rowTitle.copyWith(
            color: transaction.description.isEmpty
                ? AppColors.inkDim
                : AppColors.ink,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: <Widget>[
            if (transaction.isPendingReview) ...<Widget>[
              const _ReviewDot(),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowMeta.copyWith(color: AppColors.inkDim),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReviewDot extends StatelessWidget {
  const _ReviewDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: AppColors.coral,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({required this.transaction, required this.income});

  final Transaction transaction;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final String value = transaction.type == TxType.transfer
        ? Fmt.amount(transaction.amount)
        : Fmt.signed(transaction.signedAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: AppText.amount.copyWith(
            color: income ? AppColors.mint : AppColors.ink,
          ),
        ),
        if (transaction.source.isFromBank) ...<Widget>[
          const SizedBox(height: 4),
          SourceBadge(source: transaction.source),
        ],
      ],
    );
  }
}

/// "MB" / "Tay" tag under an amount.
class SourceBadge extends StatelessWidget {
  const SourceBadge({required this.source, super.key});

  final TxSource source;

  @override
  Widget build(BuildContext context) {
    final bool bank = source.isFromBank;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: bank
            ? AppColors.mint.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.07),
      ),
      child: Text(
        source.badge,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: bank ? AppColors.mint : AppColors.inkDim,
        ),
      ),
    );
  }
}

/// Section header row: title left, optional action right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: AppText.sectionTitle.copyWith(color: AppColors.ink),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mint,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Empty state used by several screens.
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: AppColors.strokeFaint),
            ),
            child: Icon(icon, color: AppColors.inkFaint, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.inkDim,
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Liquid Glass Panel Card with BackdropFilter frosted blur and neon glow
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.card,
    this.borderColor,
    this.glowColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? AppColors.glassBorder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0x380C1424),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 1.2),
            boxShadow: [
              if (glowColor != null)
                BoxShadow(
                  color: glowColor!.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Cyberpunk Dark Matrix background with subtle neon grid/glow
class MidnightBackground extends StatelessWidget {
  const MidnightBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgTop,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.bgTop,
            AppColors.bgMid,
            AppColors.bgBottom,
          ],
        ),
      ),
      child: child,
    );
  }
}
