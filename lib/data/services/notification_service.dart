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
      await _plugin.initialize(settings);
      _ready = true;
    } on Object catch (e) {
      debugPrint('NotificationService init failed: $e');
    }
  }

  /// Shows the iOS permission sheet once; safe to call repeatedly.
  Future<bool> ensurePermission() async {
    await init();
    if (!_ready) return false;
    if (_permissionAsked) return true;
    _permissionAsked = true;

    if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? ios =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      final bool? granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final bool? granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  /// Fires after a sync adds rows the user has not classified yet.
  Future<void> notifyBalanceChanged({
    required int newCount,
    required int total,
    String? sample,
  }) async {
    if (kIsWeb) return;
    final bool ok = await ensurePermission();
    if (!ok) return;

    final String title = newCount == 1
        ? 'Số dư vừa biến động'
        : '$newCount giao dịch mới';

    final String body = newCount == 1
        ? '${sample ?? 'Một khoản'} · ${_fmt(total)} — chạm để thêm danh mục '
            'và mô tả nhé Hoàng.'
        : 'Tổng ${_fmt(total)} chưa phân loại. Chạm để ghi mục và mô tả.';

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: 'review',
      );
    } on Object catch (e) {
      debugPrint('notifyBalanceChanged failed: $e');
    }
  }

  /// Nudge for a single row the AI was not sure about.
  Future<void> notifyNeedsReview(String description, int amount) async {
    if (kIsWeb) return;
    final bool ok = await ensurePermission();
    if (!ok) return;

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        'Cần Hoàng phân loại',
        '$description · ${_fmt(amount)} — chọn danh mục và mô tả giúp mình nhé.',
        details,
        payload: 'review',
      );
    } on Object catch (e) {
      debugPrint('notifyNeedsReview failed: $e');
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


