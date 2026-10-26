import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/vn_clock.dart';
import '../db/transaction_dao.dart';
import '../repositories/secret_store.dart';
import '../repositories/settings_repository.dart';
import '../repositories/sync_service.dart';
import '../repositories/transaction_repository.dart';
import 'new_transaction_watcher.dart';
import 'webhook_ingest_service.dart';

/// Keeps SePay polling alive while the app is backgrounded.
///
/// How far this can go is dictated by iOS, so the real behaviour matters:
///
///  * **Backgrounded (vừa vuốt ra home)** — a periodic timer keeps syncing for
///    roughly 30 s before iOS suspends the process. That is the window where
///    "tắt app vẫn thêm vào" genuinely works.
///  * **Killed (vuốt khỏi app switcher)** — no third-party code can poll a URL.
///    The SePay webhook is the always-on path; the app reconciles the gap on
///    every resume, so nothing is lost.
///
/// The service also hooks app lifecycle so every resume triggers a catch-up.
class BackgroundSyncService with WidgetsBindingObserver {
  BackgroundSyncService({
    required SyncService sync,
    required SecretStore secrets,
    required SettingsRepository settings,
    required TransactionRepository repository,
    required TransactionDao dao,
    WebhookIngestService? webhook,
    NewTransactionWatcher? watcher,
  })  : _sync = sync,
        _secrets = secrets,
        _settings = settings,
        _repository = repository,
        _dao = dao,
        _webhook = webhook,
        _watcher = watcher ??
            NewTransactionWatcher(dao: dao);

  final SyncService _sync;
  final SecretStore _secrets;
  final SettingsRepository _settings;
  final TransactionRepository _repository;
  final TransactionDao _dao;
  final WebhookIngestService? _webhook;
  final NewTransactionWatcher _watcher;

  Timer? _timer;
  bool _busy = false;
  DateTime? _lastRun;
  int _consecutiveFailures = 0;

  /// Surfaced in settings so Hoàng can see the worker is alive.
  DateTime? get lastRun => _lastRun;
  bool get isRunning => _timer?.isActive ?? false;

  /// 45 s keeps the SePay rate limit comfortable while still feeling instant.
  static const Duration interval = Duration(seconds: 45);

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await _ensureTimer();
    unawaited(tick(force: true));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_ensureTimer());
        unawaited(tick(force: true));
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // iOS grants a short grace period here — exactly when a fresh bank
        // push should still be filed.
        unawaited(_ensureTimer());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _ensureTimer() async {
    if (kIsWeb) return;
    if (!_settings.sepayEnabled) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    final String? token = await _secrets.readSepayToken();
    if (token == null || token.isEmpty) return;
    if (_timer?.isActive ?? false) return;

    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
  }

  /// One polling pass. Safe to call from anywhere; it self-serialises.
  Future<void> tick({bool force = false}) async {
    if (kIsWeb || _busy) return;
    if (!_settings.sepayEnabled) return;

    final String? token = await _secrets.readSepayToken();
    if (token == null || token.isEmpty) return;

    if (!force && _consecutiveFailures >= 3) {
      _consecutiveFailures = 0;
      return;
    }

    _busy = true;
    try {
      // Webhook inbox first: those rows already carry the authoritative SePay id
      // and arrive without an API call. Whatever is left (a nested app that was
      // closed while the webhook was not yet configured) comes from polling.
      int added = 0;
      if (_webhook != null) {
        final WebhookPullReport report = await _webhook.pull();
        added += report.added;
      }

      final SyncReport report = await _sync.syncSepay();
      added += report.added;
      _lastRun = VnClock.now();
      _consecutiveFailures = 0;

      if (added > 0) {
        await _settings.markSynced(VnClock.now());

        if (_settings.balanceAlertsEnabled) {
          // The watcher decides what is genuinely new and unclassified; `added`
          // alone would re-announce a row the user already categorised.
          final int pending = await _dao.countPendingReview();
          await _watcher.checkAndNotify(unclassifiedTotal: pending);
        }
      }
    } on Object catch (e) {
      _consecutiveFailures++;
      debugPrint('background sync failed ($_consecutiveFailures): $e');
    } finally {
      _busy = false;
    }
  }
}
