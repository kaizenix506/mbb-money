/// A selectable window for the transactions list.
///
/// Deliberately separate from the month concept used by the hero card and the
/// reports tab: those are calendar-anchored (a specific tháng), while a range is
/// *relative to now* ("7 ngày qua"). Mixing the two into one field would make
/// "xem tháng 3/2026" and "xem 2 tuần qua" fight over the same state.
enum TxRange {
  days7('7 ngày', 7),
  weeks2('2 tuần', 14),
  months1('1 tháng', 30),
  months3('3 tháng', 90),
  months6('6 tháng', 180),
  year1('1 năm', 365),
  years2('2 năm', 730),
  years5('5 năm', 1825);

  const TxRange(this.label, this.days);

  /// Short label for the segmented chip row.
  final String label;

  /// Window length in days, counted back from *now* (not from the start of
  /// today) so "7 ngày" always contains seven full days of history.
  final int days;

  /// `[from, to)` for this window. [to] is exclusive and points at midnight
  /// after today, so today's transactions are included at any hour.
  ({DateTime from, DateTime to}) windowAt(DateTime now) {
    final DateTime end = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    // `to - from` must equal [days]. Because [end] is already one day past
    // today, subtracting the full [days] from it would drop a day and make
    // "7 ngày" cover only six.
    return (from: end.subtract(Duration(days: days)), to: end);
  }

  /// Row cap per range. Long windows could return tens of thousands of rows,
  /// which would stall the list on a phone; the cap keeps scrolling smooth and
  /// is generous enough that the cap is never the limit in practice.
  int get maxRows => switch (this) {
        TxRange.days7 => 500,
        TxRange.weeks2 => 1000,
        TxRange.months1 => 2000,
        TxRange.months3 => 5000,
        TxRange.months6 => 8000,
        TxRange.year1 => 12000,
        TxRange.years2 => 20000,
        TxRange.years5 => 40000,
      };

  /// Human description of the window, e.g. "12/10 – 26/10".
  String describe(DateTime now) {
    final ({DateTime from, DateTime to}) w = windowAt(now);
    final DateTime lastDay = w.to.subtract(const Duration(days: 1));
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
    if (w.from.year != lastDay.year) {
      return '${d(w.from)}/${w.from.year} – ${d(lastDay)}/${lastDay.year}';
    }
    return '${d(w.from)} – ${d(lastDay)}';
  }

  /// Compares sensible ordering for the UI chip row without relying on
  /// declaration order (which would break if a range is inserted).
  static List<TxRange> get all => List<TxRange>.unmodifiable(values);
}
