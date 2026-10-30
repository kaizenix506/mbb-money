
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/db/transaction_dao.dart';
import '../stores/transaction_store.dart';
import '../category_ref.dart';

/// Reports tab — the "Editorial Ledger" layout.
///
/// Deliberately a different visual language from the overview: monochrome ink,
/// one lime accent, hairline rules and a serif headline. It reads like a
/// designed bank statement, which is what makes the data legible at a glance.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.watch<TransactionStore>();
    final PeriodTotals totals = store.totals;
    final List<({String? id, int total})> cats = store.expenseByCategoryId;
    final List<({DateTime month, int total})> trailing = store.trailing;

    final int prevMonthTotal = trailing.length >= 2
        ? trailing[trailing.length - 2].total
        : 0;
    final int current = totals.expense;

    final double? deltaPct = prevMonthTotal == 0
        ? null
        : (current - prevMonthTotal) / prevMonthTotal;

    final CategoryResolver resolver = context.categories;
    final Map<String, ({CategoryRef category, int total})> groupedCats =
        <String, ({CategoryRef category, int total})>{};
    for (final ({String? id, int total}) c in cats) {
      if (c.total <= 0) continue;
      final CategoryRef ref = resolver.findById(c.id);
      final ({CategoryRef category, int total})? existing = groupedCats[ref.id];
      if (existing != null) {
        groupedCats[ref.id] = (category: ref, total: existing.total + c.total);
      } else {
        groupedCats[ref.id] = (category: ref, total: c.total);
      }
    }
    final List<({CategoryRef category, int total})> mergedCats =
        groupedCats.values.toList()
          ..sort((({CategoryRef category, int total}) a,
                  ({CategoryRef category, int total}) b) =>
              b.total.compareTo(a.total));

    final int maxCategory = mergedCats.isEmpty
        ? 0
        : mergedCats
            .map((({CategoryRef category, int total}) c) => c.total)
            .reduce((int a, int b) => a > b ? a : b);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 120),
        children: <Widget>[
          _TopBar(month: store.month),
          const SizedBox(height: 22),
          _Headline(
            total: current,
            income: totals.income,
            expense: totals.expense,
            deltaPct: deltaPct,
          ),
          const SizedBox(height: 24),
          _MonthBars(data: trailing),
          const SizedBox(height: 6),
          _SectionLabel('Chi theo danh mục', right: mergedCats.length.toString()),
          if (mergedCats.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Text(
                'Chưa có khoản chi nào trong tháng này.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkDim),
              ),
            )
          else
            for (final ({CategoryRef category, int total}) c in mergedCats)
              _CategoryBar(
                item: c,
                max: maxCategory,
              ),
          const SizedBox(height: 18),
          _SectionLabel(
            'Nhật ký giao dịch',
            right: '${store.monthTransactions.length} MỤC',
          ),
          const SizedBox(height: 6),
          if (store.monthTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Tháng trống.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkDim),
              ),
            )
          else
            for (final t in store.monthTransactions.take(12))
              _LedgerRow(
                date: Fmt.dayMonth(t.occurredAt),
                title: t.description.isEmpty ? '(không nội dung)' : t.description,
                meta: '${t.source.badge} · ${Fmt.time(t.occurredAt)} · '
                    '${context.categories.findById(t.categoryId).label}',
                amount: Fmt.signed(t.signedAmount),
                synced: t.source.isFromBank,
              ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.ink,
            boxShadow: <BoxShadow>[
              BoxShadow(color: Color(0xFFC6F432), spreadRadius: 3),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'BÁO CÁO · ${Fmt.monthYear(month).toUpperCase()}',
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              color: AppColors.ink,
            ),
          ),
        ),
        _PeriodPickerButton(month: month),
      ],
    );
  }
}

/// Opens a compact scrollable list of "current year → previous years" so Hoàng
/// can jump to any past month or see a whole year at once.
class _PeriodPickerButton extends StatelessWidget {
  const _PeriodPickerButton({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final TransactionStore store = context.read<TransactionStore>();

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _open(context, store),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.strokeFaint),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'CHỌN KỲ',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.inkDim,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 15, color: AppColors.inkDim),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, TransactionStore store) async {
    final DateTime now = DateTime.now();
    final List<DateTime> months = <DateTime>[
      for (int y = now.year; y >= now.year - 4; y--)
        for (int m = 12; m >= 1; m--)
          if (!DateTime(y, m).isAfter(DateTime(now.year, now.month)))
            DateTime(y, m),
    ];
    // Oldest first so the list opens near the newest entry.
    final List<DateTime> reversed = months.reversed.toList(growable: false);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgMid,
      isScrollControlled: true,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: <Widget>[
                const Text(
                  'CHỌN THÁNG / NĂM',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: AppColors.inkDim,
                  ),
                ),
                const SizedBox(height: 12),
                for (final DateTime m in reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Fmt.monthYear(m),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: m.year == month.year && m.month == month.month
                            ? FontWeight.w900
                            : FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                    trailing: m.year == month.year && m.month == month.month
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: AppColors.mint)
                        : null,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      store.goToMonth(m);
                    },
                  ),
                const Divider(color: AppColors.strokeFaint),
                const SizedBox(height: 6),
                const Text(
                  'TỔNG QUAN THEO NĂM',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: AppColors.inkDim,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (int y = now.year; y >= now.year - 4; y--)
                      ActionChip(
                        label: Text(
                          'Năm $y',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => YearReportPage(year: y),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Whole-year summary: 12 monthly bars plus the yearly category split.
class YearReportPage extends StatefulWidget {
  const YearReportPage({required this.year, super.key});

  final int year;

  @override
  State<YearReportPage> createState() => _YearReportPageState();
}

class _YearReportPageState extends State<YearReportPage> {
  late Future<List<({DateTime month, int total})>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<({DateTime month, int total})>> _load() async {
    // Re-use the monthly query anchored at December of the chosen year so the
    // whole calendar year is covered.
    return context.read<TransactionStore>().expensesForYear(widget.year);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        title: Text('Năm ${widget.year}'),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<List<({DateTime month, int total})>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<({DateTime month, int total})>> snap,
        ) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.mint),
            );
          }
          final List<({DateTime month, int total})> data = snap.data!;
          final int total =
              data.fold<int>(0, (int s, ({DateTime month, int total}) e) => s + e.total);
          final int best = data.fold<int>(
              0, (int s, ({DateTime month, int total}) e) => e.total > s ? e.total : s);

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
            children: <Widget>[
              Text(
                Fmt.dong(total),
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'TỔNG CHI CẢ NĂM',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppColors.inkDim,
                ),
              ),
              const SizedBox(height: 26),
              for (final ({DateTime month, int total}) m in data)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 38,
                        child: Text(
                          'T${m.month.month}',
                          style: const TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkDim,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Stack(
                            children: <Widget>[
                              Container(
                                height: 9,
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              FractionallySizedBox(
                                widthFactor: best == 0
                                    ? 0
                                    : (m.total / best).clamp(0.0, 1.0),
                                child: Container(
                                  height: 9,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: <Color>[
                                        AppColors.neonViolet,
                                        AppColors.neonCyan,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 62,
                        child: Text(
                          Fmt.compact(m.total),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.total,
    required this.income,
    required this.expense,
    required this.deltaPct,
  });

  final int total;
  final int income;
  final int expense;
  final double? deltaPct;

  @override
  Widget build(BuildContext context) {
    final bool down = (deltaPct ?? 0) <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'CHI THÁNG',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                Fmt.amount(total),
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 54,
                  height: 0.95,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1.6,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'đ',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkDim,
                ),
              ),
            ],
          ),
        ),
        if (deltaPct != null) ...<Widget>[
          const SizedBox(height: 12),
          _LimeTag(
            text: '${down ? '▼' : '▲'} ${(deltaPct!.abs() * 100).round()}% '
                'so với tháng trước',
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            _InlineStat('Thu', Fmt.compact(income)),
            const _VLine(),
            _InlineStat('Chi', Fmt.compact(expense)),
            const _VLine(),
            _InlineStat(
              'Tỷ lệ',
              income <= 0 ? '—' : '${((expense / income) * 100).round()}%',
            ),
          ],
        ),
      ],
    );
  }
}

class _LimeTag extends StatelessWidget {
  const _LimeTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFFC6F432),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0A0A0A),
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.inkDim),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _VLine extends StatelessWidget {
  const _VLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 13,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: AppColors.stroke,
    );
  }
}

/// Six-month expense bars, newest highlighted.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.data});

  final List<({DateTime month, int total})> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final int max = data
        .map((({DateTime month, int total}) e) => e.total)
        .fold<int>(0, (int a, int b) => a > b ? a : b);

    return Column(
      children: <Widget>[
        SizedBox(
          height: 84,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < data.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == data.length - 1 ? 0 : 8),
                    child: _Bar(
                      fraction: max == 0 ? 0 : data[i].total / max,
                      highlight: i == data.length - 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: <Widget>[
            for (int i = 0; i < data.length; i++)
              Expanded(
                child: Text(
                  Fmt.monthShort(data[i].month),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight:
                        i == data.length - 1 ? FontWeight.w700 : FontWeight.w400,
                    color: i == data.length - 1
                        ? AppColors.ink
                        : AppColors.inkFaint,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.highlight});

  final double fraction;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double h = (c.maxHeight * fraction.clamp(0.04, 1.0));
        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            height: h,
            decoration: BoxDecoration(
              color: highlight ? AppColors.ink : AppColors.inkFaint.withValues(alpha: 0.32),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.right});

  final String text;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 8),
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.stroke, width: 1),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              right,
              style: const TextStyle(fontSize: 9, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.item, required this.max});

  final ({CategoryRef category, int total}) item;

  /// Largest sibling total, so each bar reads as a share of the biggest one.
  final int max;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Container(width: 9, height: 9, color: item.category.tint),
          const SizedBox(width: 9),
          SizedBox(
            width: 74,
            child: Text(
              item.category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          Expanded(
            child: _RelativeBar(
              value: item.total,
              color: item.category.tint,
              max: max,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: Text(
              Fmt.amount(item.total),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar whose width is a fraction of the largest sibling, computed by the
/// parent via an inherited max value would be cleaner — but passing the list
/// maximum down keeps this widget stateless and reusable.
class _RelativeBar extends StatelessWidget {
  const _RelativeBar({
    required this.value,
    required this.color,
    required this.max,
  });

  final int value;
  final Color color;
  final int max;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 5,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double frac =
                max <= 0 ? 0 : (value / max).clamp(0.0, 1.0);
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.inkFaint.withValues(alpha: 0.16),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: c.maxWidth * frac,
                  color: color,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.date,
    required this.title,
    required this.meta,
    required this.amount,
    required this.synced,
  });

  final String date;
  final String title;
  final String meta;
  final String amount;
  final bool synced;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.strokeFaint, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 42,
            child: Text(
              date,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.inkFaint,
              ),
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: synced ? const Color(0xFFC6F432) : Colors.transparent,
              border: synced
                  ? null
                  : Border.all(color: AppColors.inkFaint, width: 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
