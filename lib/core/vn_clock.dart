import 'dart:async';

import 'package:flutter/foundation.dart';

/// Clock helpers pinned to **UTC+7** (giờ Việt Nam).
///
/// The device may be set to any timezone, so every greeting, "today" check and
/// realtime clock in the UI reads through here instead of `DateTime.now()`,
/// which would otherwise show the wrong half of the day for Hoàng.
abstract final class VnClock {
  /// Vietnam never observes daylight saving, so a fixed offset is exact.
  static const Duration offset = Duration(hours: 7);

  /// Wall-clock time in Vietnam, expressed as a UTC `DateTime` so arithmetic
  /// never re-applies the device offset.
  static DateTime now() {
    final DateTime utc = DateTime.now().toUtc();
    return utc.add(offset);
  }

  /// Device "now" shifted into Vietnam wall-clock numbers.
  /// The returned object is a UTC [DateTime] whose fields are the VN fields.
  static DateTime fields() => now();

  static int get hour => now().hour;
  static int get minute => now().minute;
  static int get second => now().second;

  /// `14:07:32` — seconds included for the live header clock.
  static String hms([DateTime? at]) {
    final DateTime t = at ?? now();
    return '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  }

  /// `14:07`
  static String hm([DateTime? at]) {
    final DateTime t = at ?? now();
    return '${_two(t.hour)}:${_two(t.minute)}';
  }

  /// Time-of-day greeting, aligned to Vietnamese habits.
  static String get greeting => switch (hour) {
        >= 4 && < 11 => 'Chào buổi sáng',
        >= 11 && < 13 => 'Chào buổi trưa',
        >= 13 && < 18 => 'Chào buổi chiều',
        >= 18 && < 23 => 'Chào buổi tối',
        _ => 'Khuya rồi, nghỉ ngơi nhé',
      };

  /// `THỨ HAI` / ... for the given VN date.
  static String weekdayLabel([DateTime? at]) {
    final DateTime t = at ?? now();
    const List<String> names = <String>[
      'THỨ HAI',
      'THỨ BA',
      'THỨ TƯ',
      'THỨ NĂM',
      'THỨ SÁU',
      'THỨ BẢY',
      'CHỦ NHẬT',
    ];
    return names[t.weekday - 1];
  }

  /// `20/10/2026`
  static String dateLabel([DateTime? at]) {
    final DateTime t = at ?? now();
    return '${_two(t.day)}/${_two(t.month)}/${t.year}';
  }

  /// True when [a] and [b] fall on the same VN calendar day.
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// A `ChangeNotifier` that ticks once a second so any widget can paint a live
/// clock without each one owning its own [Timer].
class TickerClock extends ChangeNotifier {
  TickerClock({this.interval = const Duration(seconds: 1)}) {
    _start();
  }

  final Duration interval;
  Timer? _timer;
  DateTime _now = VnClock.now();

  DateTime get now => _now;
  String get hms => VnClock.hms(_now);
  String get hm => VnClock.hm(_now);

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      _now = VnClock.now();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
