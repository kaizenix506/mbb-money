import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models/tx_range.dart';
import '../stores/transaction_store.dart';

/// Horizontally scrollable chip row for picking how far back the transactions
/// tab looks: 7 ngày → 5 năm.
///
/// A scrollable row rather than `SegmentedButton` or a `Wrap`: eight options do
/// not fit on a 390pt phone, and wrapping onto two lines pushes the list down
/// on every launch. The selected chip is auto-scrolled into view so returning
/// to a far-right selection never leaves it off-screen.
class RangeSelector extends StatefulWidget {
  const RangeSelector({super.key});

  @override
  State<RangeSelector> createState() => _RangeSelectorState();
}

class _RangeSelectorState extends State<RangeSelector> {
  final ScrollController _controller = ScrollController();
  final Map<TxRange, GlobalKey> _keys = <TxRange, GlobalKey>{
    for (final TxRange r in TxRange.values) r: GlobalKey(),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reveal(TxRange range) {
    final BuildContext? ctx = _keys[range]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.watch<TransactionStore>();

    return SizedBox(
      height: 34,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: TxRange.values.length,
        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final TxRange r = TxRange.values[i];
          final bool selected = r == store.range;
          return _RangeChip(
            key: _keys[r],
            label: r.label,
            selected: selected,
            onTap: () {
              if (selected) return;
              store.setRange(r);
              _reveal(r);
            },
          );
        },
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            color: selected
                ? AppColors.neonCyan.withValues(alpha: 0.16)
                : AppColors.glassPanel,
            border: Border.all(
              color: selected ? AppColors.neonCyan : AppColors.glassBorder,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: 0.2,
              color: selected ? AppColors.neonCyan : AppColors.inkDim,
            ),
          ),
        ),
      ),
    );
  }
}
