import 'package:flutter/foundation.dart';

import '../db/transaction_dao.dart';
import '../models/transaction.dart';
import 'notification_service.dart';

/// Decides when an unclassified transaction is genuinely new, and fires the
/// "gắn danh mục" banner for it.
///
/// Why a watermark and not a timestamp: rows arrive from three paths (SePay
/// polling, the Cloudflare relay, Manual/AI entry) and all of them end up in the
/// same table with an AUTOINCREMENT id. Comparing `id > watermark` is exact,
/// immune to clock skew and free of "same second" ambiguity.
///
/// The watermark lives in the DB's `internal_state` table rather than
/// SharedPreferences so it is wiped together with the ledger — a reset must not
/// leave a watermark pointing at rows that no longer exist.
///
/// Notification behaviour, in plain terms:
///  * The very first run only *arms* the watcher. Without this, an empty
///    watermark would announce every historical row on upgrade.
///  * A row the user already classified does not notify.
///  * Several rows found in one pass are announced as one banner.
class NewTransactionWatcher {
  NewTransactionWatcher({
    required TransactionDao dao,
    NotificationService? notifications,
  })  : _dao = dao,
        _notifications = notifications ?? NotificationService.instance;

  final TransactionDao _dao;
  final NotificationService _notifications;

  static const String _kWatermark = 'notify.watermark_tx_id';
  static const String _kArmed = 'notify.armed';

  /// Cap on how many rows a single banner mentions; the rest are folded into
  /// the "N giao dịch" count.
  static const int _sampleLimit = 3;

  bool _running = false;
  bool _seeded = false;

  /// Guards against two concurrent seeders. main() kicks off a seed and the
  /// foreground ticker immediately fires its first check; without this both
  /// could read the arm flag as missing and race on what the watermark means.
  Future<void>? _seeding;

  /// Arms the watermark without notifying, so upgrading users are not spammed
  /// with every transaction already in the database.
  ///
  /// Awaited by [checkAndNotify] before it reads the watermark, which is what
  /// stops the first check after launch from racing the arm step and treating
  /// the whole ledger as new.
  Future<void> seedIfNeeded() {
    if (_seeded) return Future<void>.value();
    return _seeding ??= _seed();
  }

  Future<void> _seed() async {
    try {
      final String? armed = await _dao.readInternal(_kArmed);
      if (armed != '1') {
        final int max = await _dao.maxId();
        await _dao.writeInternal(_kWatermark, '$max');
        await _dao.writeInternal(_kArmed, '1');
      }
      _seeded = true;
    } finally {
      _seeding = null;
    }
  }

  /// Checks for rows added since the last check and notifies if any of them
  /// still need a category. Returns how many new unclassified rows were seen.
  ///
  /// Safe to call from the UI, a background isolate or a timer: overlapping
  /// calls are dropped, and every call is wrapped so a notification failure can
  /// never break a sync.
  Future<int> checkAndNotify({int unclassifiedTotal = 0}) async {
    if (_running) return 0;
    _running = true;
    try {
      await seedIfNeeded();
      final int watermark =
          int.tryParse(await _dao.readInternal(_kWatermark) ?? '') ?? 0;
      final int max = await _dao.maxId();

      if (max <= watermark) return 0;

      // The watermark is a forward-only cursor, so the backlog has to be walked
      // OLDEST-first in pages. Reading a newest-first page and moving the
      // watermark to its head would strand every older row permanently, which
      // is what silently swallowed banners when a burst exceeded one page.
      final List<Transaction> fresh = <Transaction>[];
      int cursor = watermark;
      // Bounded so a pathological database cannot spin here; 50 pages is 1000
      // rows per check, far beyond any real bank sync.
      for (int page = 0; page < 50; page++) {
        final List<Transaction> batch = await _dao.rowsAbove(
          cursor,
          ascending: true,
        );
        if (batch.isEmpty) break;
        fresh.addAll(batch);
        cursor = batch.last.id;
        if (cursor >= max) break;
      }
      if (fresh.isEmpty) return 0;
      await _dao.writeInternal(_kWatermark, '$cursor');

      final List<Transaction> needingCategory = fresh
          .where((Transaction t) => _needsCategory(t))
          .toList(growable: false);
      if (needingCategory.isEmpty) return 0;

      final int total = unclassifiedTotal > 0
          ? unclassifiedTotal
          : needingCategory.fold<int>(0, (int sum, Transaction t) => sum + t.amount);

      await _notifications.notifyNewTransactions(
        newCount: needingCategory.length,
        unclassifiedTotal: total,
        samples: <String>[
          for (final Transaction t in needingCategory.take(_sampleLimit))
            _label(t),
        ],
      );
      return needingCategory.length;
    } on Object catch (e) {
      debugPrint('NewTransactionWatcher failed: $e');
      return 0;
    } finally {
      _running = false;
    }
  }

  /// How many stored rows still need a category.
  ///
  /// Used by the foreground ticker to decide whether a reminder is worth
  /// raising at all, so an empty queue never produces a banner.
  Future<int> pendingCount() async {
    try {
      await seedIfNeeded();
      final List<Transaction> waiting = await _dao.rowsNeedingCategory(limit: 100);
      return waiting.length;
    } on Object catch (e) {
      debugPrint('NewTransactionWatcher.pendingCount failed: $e');
      return 0;
    }
  }

  /// Re-raises the banner for rows that were already seen but are still
  /// unclassified.
  ///
  /// The watermark only advances forwards, so a banner that was dismissed — or
  /// never seen because the phone was locked — would otherwise be lost for
  /// good. This is the only path that notifies about rows below the watermark,
  /// which is why the ticker calls it on a slow cadence only.
  Future<int> remindPending() async {
    if (_running) return 0;
    _running = true;
    try {
      await seedIfNeeded();
      final List<Transaction> waiting = await _dao.rowsNeedingCategory(limit: 100);
      if (waiting.isEmpty) return 0;

      final int total =
          waiting.fold<int>(0, (int sum, Transaction t) => sum + t.amount);
      await _notifications.notifyNewTransactions(
        newCount: waiting.length,
        unclassifiedTotal: total,
        samples: <String>[
          for (final Transaction t in waiting.take(_sampleLimit)) _label(t),
        ],
      );
      return waiting.length;
    } on Object catch (e) {
      debugPrint('NewTransactionWatcher.remindPending failed: $e');
      return 0;
    } finally {
      _running = false;
    }
  }

  // --------------------------------------------------- write-through hooks

  /// Called by the ledger *after* a row was inserted by a path that does not go
  /// through the (periodically-run) sync watcher — manual entry and the AI chat.
  ///
  /// Advancing the watermark here is what stops the foreground ticker from
  /// reading such a row as "new" and announcing it a second time. The row is
  /// still covered by [remindPending], which re-surfaces anything left without a
  /// category, so nothing is lost by moving the cursor forward.
  Future<void> noteInserted(int id) async {
    if (id <= 0) return;
    try {
      await seedIfNeeded();
      final int watermark =
          int.tryParse(await _dao.readInternal(_kWatermark) ?? '') ?? 0;
      if (id > watermark) {
        await _dao.writeInternal(_kWatermark, '$id');
      }
    } on Object catch (e) {
      debugPrint('NewTransactionWatcher.noteInserted failed: $e');
    }
  }

  /// Called after an existing row was edited, so classifying a row stops the
  /// periodic reminder without needing another ledger scan.
  Future<void> noteUpdated(int id) async {
    if (id <= 0) return;
    try {
      await seedIfNeeded();
      final int watermark =
          int.tryParse(await _dao.readInternal(_kWatermark) ?? '') ?? 0;
      if (id > watermark) {
        await _dao.writeInternal(_kWatermark, '$id');
      }
    } on Object catch (e) {
      debugPrint('NewTransactionWatcher.noteUpdated failed: $e');
    }
  }

  /// A row is worth a nudge when it is still waiting for a category.
  ///
  /// `pending_review` is the explicit flag the parsers set when they were not
  /// confident, so it is the most reliable signal; rows ingested without any
  /// category id are treated the same way.
  static bool _needsCategory(Transaction t) {
    if (t.isPendingReview) return true;
    final String? id = t.categoryId;
    return id == null || id.isEmpty;
  }

  static String _label(Transaction t) {
    final String desc = t.description.trim();
    final String amount = _short(t.amount);
    if (desc.isEmpty) return amount;
    final String clipped = desc.length > 34 ? '${desc.substring(0, 33)}…' : desc;
    return '$clipped · $amount';
  }

  static String _short(int dong) {
    if (dong >= 1000000) {
      final double millions = dong / 1000000;
      final String text = millions == millions.roundToDouble()
          ? millions.toStringAsFixed(0)
          : millions.toStringAsFixed(1);
      return '${text}tr';
    }
    if (dong >= 1000) return '${(dong / 1000).round()}k';
    return '$dong' 'đ';
  }
}
