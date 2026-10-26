import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for balance movements.
///
/// Hoàng asked to be nudged whenever the balance changes so he can add a
/// category + description to the row the bank just pushed. iOS is the primary
/// target, so this uses the Darwin plugin and asks for permission lazily —
/// never at cold start, which would show a permission alert before the app has
/// explained itself.
///
/// The same notification is fired from three places, which is deliberate:
///  * the foreground poller, while the app is open;
///  * the background worker that wakes when the OS gives the app CPU time;
///  * the webhook pull, which also runs on wake.
///
/// Only the new-row watcher decides *whether* something is new (see
/// `NewTransactionWatcher`); this class only decides what it looks like.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _permissionAsked = false;

  static const String _channelId = 'mbb_money_balance';
  static const String _channelName = 'Biến động số dư';
  static const String _channelDesc =
      'Nhắc Hoàng phân loại khi số dư thay đổi';

  /// Reused so a burst of rows collapses into one banner instead of spamming
  /// the lock screen with a notification per transaction.
  static const int _summaryId = 4021;

  Future<void> init() async {
    if (_ready || kIsWeb) return;

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const InitializationSettings settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onTap,
        onDidReceiveBackgroundNotificationResponse: _onTapBackground,
      );
      _ready = true;
    } on Object catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  void _onTap(NotificationResponse response) {
    // The payload is only ever "review"; the app itself decides where to land
    // (it opens the review queue when there are pending rows). Keeping the
    // navigation out of this callback avoids needing a navigator key here.
    debugPrint('notification tapped: ${response.payload}');
  }

  @pragma('vm:entry-point')
  static void _onTapBackground(NotificationResponse response) {
    debugPrint('notification tapped in background: ${response.payload}');
  }

  /// Shows the iOS permission sheet once; safe to call repeatedly.
  ///
  /// Returns the *current* authorisation state rather than "did we just ask",
  /// so a user who declined earlier is not silently treated as opted in.
  Future<bool> ensurePermission() async {
    await init();
    if (!_ready) return false;

    if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? ios =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (!_permissionAsked) {
        _permissionAsked = true;
        final bool? granted = await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
      final NotificationsEnabledOptions? options =
          await ios?.checkPermissions();
      return options?.isEnabled ?? false;
    }

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (!_permissionAsked) {
        _permissionAsked = true;
        final bool? granted = await android?.requestNotificationsPermission();
        if (granted != null) return granted;
      }
      final bool? enabled = await android?.areNotificationsEnabled();
      return enabled ?? false;
    }
    return false;
  }

  /// Whether banners can currently be delivered, without prompting.
  Future<bool> hasPermission() async {
    await init();
    if (!_ready) return false;
    try {
      if (Platform.isIOS) {
        final IOSFlutterLocalNotificationsPlugin? ios =
            _plugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        return (await ios?.checkPermissions())?.isEnabled ?? false;
      }
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? android = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? false;
      }
    } on Object catch (e) {
      debugPrint('hasPermission failed: $e');
    }
    return false;
  }

  NotificationDetails _details({Importance importance = Importance.high}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: importance,
        priority: importance == Importance.high
            ? Priority.high
            : Priority.defaultPriority,
        // A single ongoing style keeps the tray readable when several rows
        // arrive from one bank push.
        styleInformation: const BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: importance == Importance.high
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
      ),
    );
  }

  /// Fires after a sync adds rows the user has not classified yet.
  ///
  /// [samples] are the newest descriptions, used to make the banner concrete
  /// ("Highlands Coffee") instead of generic.
  Future<void> notifyNewTransactions({
    required int newCount,
    required int unclassifiedTotal,
    List<String> samples = const <String>[],
  }) async {
    if (kIsWeb || newCount <= 0) return;
    final bool ok = await ensurePermission();
    if (!ok) return;

    final String title = newCount == 1
        ? 'Giao dịch mới cần gắn danh mục'
        : '$newCount giao dịch mới cần gắn danh mục';

    final String first = samples.isEmpty ? '' : samples.first;
    final String body = newCount == 1
        ? '${first.isEmpty ? 'Một khoản' : first} · ${_fmt(unclassifiedTotal)}'
            ' — chạm để chọn danh mục nhé Hoàng.'
        : '${samples.take(2).join(' · ')}'
            '${newCount > samples.take(2).length ? ' …' : ''}'
            '\nTổng ${_fmt(unclassifiedTotal)} chưa phân loại. Chạm để phân loại.';

    try {
      await _plugin.show(_summaryId, title, body, _details(), payload: 'review');
    } on Object catch (e) {
      debugPrint('notifyNewTransactions failed: $e');
    }
  }

  /// Kept for callers that only know counts it already computed.
  Future<void> notifyBalanceChanged({
    required int newCount,
    required int total,
    String? sample,
  }) =>
      notifyNewTransactions(
        newCount: newCount,
        unclassifiedTotal: total,
        samples: <String>[if (sample != null && sample.isNotEmpty) sample],
      );

  /// Nudge for a single row the AI was not sure about.
  Future<void> notifyNeedsReview(String description, int amount) async {
    if (kIsWeb) return;
    final bool ok = await ensurePermission();
    if (!ok) return;

    try {
      await _plugin.show(
        _summaryId,
        'Cần Hoàng phân loại',
        '$description · ${_fmt(amount)} — chọn danh mục và mô tả giúp mình nhé.',
        _details(importance: Importance.defaultImportance),
        payload: 'review',
      );
    } on Object catch (e) {
      debugPrint('notifyNeedsReview failed: $e');
    }
  }

  /// Clears the pending banner(s) once the user has dealt with the queue, so
  /// the tray does not keep advertising work that is already done.
  Future<void> clearReviewNotifications() async {
    if (kIsWeb) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(_summaryId);
    } on Object catch (e) {
      debugPrint('clearReviewNotifications failed: $e');
    }
  }

  String _fmt(int dong) {
    final String digits = dong.toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return '${buf.toString()} ₫';
  }
}
