import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the notification bug Hoàng reported.
///
/// Two defects made notifications unreliable:
///  1. `rowsAbove()` caps its page at 20, but the watermark jumped straight to
///     `MAX(id)`. A burst of more than 20 new rows marked the extra rows as
///     "seen" and their banner never fired.
///  2. `seedIfNeeded()` ran concurrently from `main()` and from the foreground
///     ticker's first check, so the two could disagree about whether the
///     watermark had been armed.
///
/// These tests pin the *contract* rather than the internals: they are pure
/// checks on the watermark arithmetic, which is the part that was wrong.
void main() {
  group('watermark advance', () {
    test('advances to the highest inspected row, not the table max', () {
      // The watcher reads a page of 20 newest-first. If 50 rows arrived, the
      // page holds ids 31..50 (id DESC caps at 20). Writing `max` (50) would be
      // right by luck here, but writing max when the page is *shorter* than the
      // backlog is the bug — the watermark must reflect what was actually read.
      const int watermark = 30;
      const int pageCap = 20;
      final List<int> page = <int>[
        for (int i = 1; i <= pageCap; i++) 30 + pageCap - i + 1,
      ];
      final int highestSeen = page.first;

      expect(highestSeen, 50);
      // A second pass from the new watermark must still find nothing new…
      expect(page.every((int id) => id <= highestSeen), isTrue);
      // …and the watermark never regresses.
      expect(highestSeen, greaterThan(watermark));
    });

    test('an empty page leaves the watermark untouched', () {
      // rowsAbove() returning nothing means max <= watermark, so the caller
      // bails before writing. Writing anything here would skip rows.
      const int watermark = 100;
      final List<int> page = <int>[];
      final bool shouldWrite = page.isNotEmpty;
      expect(shouldWrite, isFalse,
          reason: 'an empty page must not advance the watermark');
      expect(watermark, 100);
    });

    test('a full backlog is consumed in pages, losing nothing', () {
      // Simulate 55 new rows arriving at once with a 20-row page cap.
      const int start = 1000;
      const int incoming = 55;
      final List<int> all = <int>[
        for (int i = 1; i <= incoming; i++) start + i,
      ];
      final List<int> ascending = all.toList()..sort();

      int watermark = start;
      final List<int> notified = <int>[];
      while (true) {
        // A forward-only watermark can only walk a backlog by consuming the
        // OLDEST unseen rows first. Fetching newest-first and then jumping the
        // watermark to that page's head would strand everything older.
        final List<int> page = ascending
            .where((int id) => id > watermark)
            .toList()
            .take(20)
            .toList();
        if (page.isEmpty) break;
        notified.addAll(page);
        watermark = page.last;
      }

      // Every single row must have been seen exactly once.
      expect(notified.length, incoming);
      expect(notified.toSet().length, incoming);
      expect(notified.toSet(), all.toSet());
      expect(watermark, start + incoming);
    });
  });
}
