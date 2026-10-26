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

  /// Arms the watermark without notifying, so upgrading users are not spammed
  /// with every transaction already in the database.
  ///
  /// Awaited by [checkAndNotify] before it reads the watermark, which is what
  /// stops the first check after launch from racing the arm step and treating
  /// the whole ledger as new.
  Future<void> seedIfNeeded() async {
    if (_seeded) return;
    final String? armed = await _dao.readInternal(_kArmed);
    if (armed != '1') {
      final int max = await _dao.maxId();
      await _dao.writeInternal(_kWatermark, '$max');
      await _dao.writeInternal(_kArmed, '1');
    }
    _seeded = true;
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

      // Rows arrive newest-first; announce the newest ones and record the max.
      final List<Transaction> fresh = await _dao.rowsAbove(watermark);
      await _dao.writeInternal(_kWatermark, '$max');

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
    return '${dong}đ';
  }
}
