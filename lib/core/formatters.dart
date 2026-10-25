import 'package:intl/intl.dart';

/// Vietnamese money and date formatting.
///
/// All amounts are stored in SQLite as integer **đồng** — VND has no subunit in
/// practice — so the app never deals with floating-point rounding errors.
///
/// Note: we build the patterns by hand rather than relying on `vi_VN` locale
/// data, which is only available after `initializeDateFormatting('vi_VN')` and
/// is easy to forget. The result is identical for the formats we use.
abstract final class Fmt {
  static final NumberFormat _vnd = _grouped();
  static final NumberFormat _oneDecimal = NumberFormat('#,##0.0', 'en_US');
  static const List<String> _weekdays = <String>[
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  static const List<String> _months = <String>[
    'tháng 1',
    'tháng 2',
    'tháng 3',
    'tháng 4',
    'tháng 5',
    'tháng 6',
    'tháng 7',
    'tháng 8',
    'tháng 9',
    'tháng 10',
    'tháng 11',
    'tháng 12',
  ];

  static NumberFormat _grouped() {
    // Vietnamese uses '.' as the thousands separator and ',' for decimals,
    // exactly what the pattern below produces without locale data.
    return NumberFormat('#,##0', 'en_US');
  }

  static String _withDots(String grouped) => grouped.replaceAll(',', '.');

  /// `42815300` → `42.815.300`
  static String amount(int dong) => _withDots(_vnd.format(dong));

  /// `42815300` → `42.815.300 ₫`
  static String money(int dong) => '${amount(dong)} ₫';
  static String dong(int val) => money(val);

  /// Ledger form: `−58.000` / `+28.500.000` / `0`.
  /// Uses U+2212 MINUS SIGN so it aligns visually with `+`.
  static String signed(int dong) {
    if (dong == 0) return '0';
    return dong > 0 ? '+${amount(dong)}' : '\u2212${amount(dong.abs())}';
  }

  /// `28500000` → `28,5tr`; `1900000` → `1,9tr`; `900` → `900`.
  ///
  /// Vietnamese readers parse "tr"/"tỷ" instantly and the stat column stays
  /// narrow, which is what the overview hero needs.
  static String compact(int dong) {
    final String sign = dong < 0 ? '\u2212' : '';
    final int abs = dong.abs();
    if (abs >= 1000000000) {
      return '$sign${_trim(abs / 1000000000)}tỷ';
    }
    if (abs >= 1000000) {
      return '$sign${_trim(abs / 1000000)}tr';
    }
    if (abs >= 1000) {
      return '$sign${_trim(abs / 1000)}k';
    }
    return '$sign${amount(abs)}';
  }

  static String _trim(double value) {
    final String s = _oneDecimal.format(value).replaceAll('.', ',');
    return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  }

  /// `09:41`
  static String time(DateTime d) =>
      '${_two(d.hour)}:${_two(d.minute)}';

  /// `20/10`
  static String dayMonth(DateTime d) => '${_two(d.day)}/${_two(d.month)}';

  /// `Thứ Hai`
  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  /// `Thứ Hai, 20 tháng 10 2026`
  static String fullDate(DateTime d) =>
      '${weekday(d)}, ${d.day} ${_months[d.month - 1]} ${d.year}';

  /// `Tháng 10 2026` — used in the hero month pill.
  static String monthYear(DateTime d) {
    final String m = _months[d.month - 1];
    return '${m[0].toUpperCase()}${m.substring(1)} ${d.year}';
  }

  /// `T10`
  static String monthShort(DateTime d) => 'T${d.month}';

  /// "Hôm nay" / "Hôm qua" / weekday name.
  static String relativeDay(DateTime d, {DateTime? now}) {
    final DateTime today = _dateOnly(now ?? DateTime.now());
    final int diff = today.difference(_dateOnly(d)).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    return weekday(d);
  }

  /// `1234` → `•• 1234` for account labels.
  static String last4(String accountNumber) {
    final String digits =
        accountNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return digits;
    return '•• ${digits.substring(digits.length - 4)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // --------------------------------------------------------- date arithmetic

  /// First instant of the month containing [d].
  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

  /// First instant of the following month.
  static DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);

  /// The same day one month earlier, clamped for short months.
  static DateTime previousMonth(DateTime d) {
    final int m = d.month == 1 ? 12 : d.month - 1;
    final int y = d.month == 1 ? d.year - 1 : d.year;
    final int lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
  }

  /// Days in the month containing [d].
  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;
}
