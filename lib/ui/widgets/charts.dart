import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../stores/transaction_store.dart';

/// Opens a scrollable list of the last five years of months and jumps the
/// shared [TransactionStore] to the chosen one. Used by both the transactions
/// and reports tabs so history is reachable from either.
Future<void> showMonthPicker(
  BuildContext context,
  TransactionStore store,
) async {
  final DateTime now = DateTime.now();
  final List<DateTime> months = <DateTime>[
    for (int y = now.year; y >= now.year - 4; y--)
      for (int m = 12; m >= 1; m--)
        if (!DateTime(y, m).isAfter(DateTime(now.year, now.month)))
          DateTime(y, m),
  ];

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgMid,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (BuildContext _, ScrollController scroller) {
          return ListView(
            controller: scroller,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            children: <Widget>[
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'CHỌN THÁNG',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: AppColors.inkDim,
                ),
              ),
              const SizedBox(height: 10),
              for (final DateTime m in months)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Fmt.monthYear(m),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          m.year == store.month.year && m.month == store.month.month
                              ? FontWeight.w900
                              : FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  trailing:
                      m.year == store.month.year && m.month == store.month.month
                          ? const Icon(Icons.check_rounded,
                              size: 18, color: AppColors.neonGreen)
                          : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    store.goToMonth(m);
                  },
                ),
            ],
          );
        },
      );
    },
  );
}

/// Animated neon donut used on the overview to show this month's category
/// split at a glance. Draws with a [CustomPainter] so it stays crisp at any
/// size and animates its sweep on first build.
class NeonDonutChart extends StatefulWidget {
  const NeonDonutChart({
    required this.slices,
    this.size = 132,
    this.stroke = 14,
    this.centerLabel,
    this.centerValue,
    super.key,
  });

  final List<DonutSlice> slices;
  final double size;
  final double stroke;
  final String? centerLabel;
  final String? centerValue;

  @override
  State<NeonDonutChart> createState() => _NeonDonutChartState();
}

class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _NeonDonutChartState extends State<NeonDonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _DonutPainter(
              slices: widget.slices,
              stroke: widget.stroke,
              progress: Curves.easeOutCubic.transform(_c.value),
            ),
            child: child,
          );
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.centerValue ?? '',
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  letterSpacing: -0.5,
                ),
              ),
              if (widget.centerLabel != null)
                Text(
                  widget.centerLabel!,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.inkFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.stroke,
    required this.progress,
  });

  final List<DonutSlice> slices;
  final double stroke;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (math.min(size.width, size.height) - stroke) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    // Track
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.05),
    );

    final int total =
        slices.fold<int>(0, (int s, DonutSlice d) => s + d.value);
    if (total <= 0) return;

    double start = -math.pi / 2;
    const double gap = 0.045;

    for (final DonutSlice s in slices) {
      final double sweep = (s.value / total) * math.pi * 2 * progress;
      if (sweep <= 0) continue;
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = s.color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawArc(rect, start + gap / 2, math.max(sweep - gap, 0.01), false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.slices != slices;
}

/// Two-tone comparison bar: this month vs last month, with the delta called
/// out in words ("ít hơn 12%") because a bare percentage is easy to misread.
class MonthCompareCard extends StatelessWidget {
  const MonthCompareCard({
    required this.current,
    required this.previous,
    required this.monthLabel,
    required this.prevLabel,
    super.key,
  });

  final int current;
  final int previous;
  final String monthLabel;
  final String prevLabel;

  @override
  Widget build(BuildContext context) {
    final int max = math.max(current, previous);
    final double curFrac = max == 0 ? 0 : current / max;
    final double prevFrac = max == 0 ? 0 : previous / max;

    final bool lower = current <= previous;
    final int diff = (current - previous).abs();
    final double pct = previous == 0 ? 0 : (diff / previous) * 100;
    final Color accent = lower ? AppColors.neonGreen : AppColors.neonPink;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        color: const Color(0x4D0A1120),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                lower ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  previous == 0
                      ? 'Chưa có dữ liệu tháng trước'
                      : '${lower ? 'GIẢM' : 'TĂNG'} ${pct.round()}% '
                          'SO VỚI ${prevLabel.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (previous > 0)
            Text(
              lower
                  ? 'Ít hơn ${Fmt.dong(diff)} — giữ nhịp này nhé Hoàng.'
                  : 'Nhiều hơn ${Fmt.dong(diff)} so với tháng trước.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkDim),
            ),
          const SizedBox(height: 14),
          _CompareRow(
            label: monthLabel,
            value: current,
            fraction: curFrac,
            color: lower ? AppColors.neonGreen : AppColors.neonPink,
            bold: true,
          ),
          const SizedBox(height: 9),
          _CompareRow(
            label: prevLabel,
            value: previous,
            fraction: prevFrac,
            color: AppColors.inkFaint,
            bold: false,
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    required this.bold,
  });

  final String label;
  final int value;
  final double fraction;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: bold ? AppColors.ink : AppColors.inkDim,
                ),
              ),
            ),
            Text(
              Fmt.compact(value),
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: bold ? AppColors.ink : AppColors.inkDim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: <Widget>[
              Container(
                height: 7,
                color: Colors.white.withValues(alpha: 0.05),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                height: 7,
                width: (MediaQuery.of(context).size.width - 92) *
                    fraction.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
