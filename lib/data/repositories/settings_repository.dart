import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which ingestion paths the user has switched on.
enum DataSource { shortcut, sepay }

/// Non-secret settings. The SePay **token** deliberately does not live here —
/// see SecretStore — because SharedPreferences is a plain unencrypted plist on
/// iOS and would leak the token on a jailbroken device or iCloud backup.
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _kShortcut = 'source.shortcut';
  static const String _kSepay = 'source.sepay';
  static const String _kSepayAccount = 'sepay.account_number';
  static const String _kLastSync = 'sync.last_at';
  static const String _kOnboarded = 'onboarding.done';
  static const String _kLastSeenTxId = 'sync.last_tx_id';

  bool get shortcutEnabled => _prefs.getBool(_kShortcut) ?? true;
  bool get sepayEnabled => _prefs.getBool(_kSepay) ?? false;

  bool isEnabled(DataSource source) => switch (source) {
        DataSource.shortcut => shortcutEnabled,
        DataSource.sepay => sepayEnabled,
      };

  Future<void> setEnabled(DataSource source, bool value) async {
    final String key =
        source == DataSource.shortcut ? _kShortcut : _kSepay;
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  String? get sepayAccountNumber => _prefs.getString(_kSepayAccount);

  Future<void> setSepayAccountNumber(String? account) async {
    if (account == null || account.isEmpty) {
      await _prefs.remove(_kSepayAccount);
    } else {
      await _prefs.setString(_kSepayAccount, account);
    }
    notifyListeners();
  }

  DateTime? get lastSyncAt {
    final int? ms = _prefs.getInt(_kLastSync);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markSynced(DateTime at) async {
    await _prefs.setInt(_kLastSync, at.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Highest local transaction id already shown to the user, so a bulk sync
  /// can tell the UI "you gained N new ones" even when nothing is new on
  /// screen.
  int get lastSeenTxId => _prefs.getInt(_kLastSeenTxId) ?? 0;

  Future<void> markSeen(int id) async {
    if (id <= lastSeenTxId) return;
    await _prefs.setInt(_kLastSeenTxId, id);
  }

  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> completeOnboarding() async {
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  // ------------------------------------------------------------- avatar

  static const String _kAvatarPath = 'profile.avatar_path';
  static const String _kDisplayName = 'profile.name';

  /// Absolute file path of the user's chosen avatar, or `null` for the default
  /// neon monogram.
  String? get avatarPath => _prefs.getString(_kAvatarPath);

  Future<void> setAvatarPath(String? path) async {
    if (path == null || path.isEmpty) {
      await _prefs.remove(_kAvatarPath);
    } else {
      await _prefs.setString(_kAvatarPath, path);
    }
    notifyListeners();
  }

  /// Defaults to Hoàng, but the header reads this so the user can rename.
  String get displayName {
    final String? n = _prefs.getString(_kDisplayName);
    return (n == null || n.trim().isEmpty) ? 'Hoàng' : n.trim();
  }

  Future<void> setDisplayName(String name) async {
    if (name.trim().isEmpty) {
      await _prefs.remove(_kDisplayName);
    } else {
      await _prefs.setString(_kDisplayName, name.trim());
    }
    notifyListeners();
  }

  // ------------------------------------------------------ notifications

  static const String _kBalanceAlerts = 'notify.balance_alerts';

  /// Ask Hoàng to categorise + describe a row when the balance moves.
  bool get balanceAlertsEnabled => _prefs.getBool(_kBalanceAlerts) ?? true;

  Future<void> setBalanceAlerts(bool value) async {
    await _prefs.setBool(_kBalanceAlerts, value);
    notifyListeners();
  }

  /// Drives the "có N giao dịch cần phân loại" nudge on the overview.
  static bool looksLikeMbNotice(String text) {
    // Kept here only so settings can show a live preview of the parser.
    return RegExp(r'\bMB\b', caseSensitive: false).hasMatch(text) &&
        text.contains(RegExp(r'VND|VNĐ|đ', caseSensitive: false));
  }

  /// Debug helper: dump all non-secret settings. Used by the "Xuất cấu hình"
  /// action when the user files a bug report.
  String exportAsJson() {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'shortcut': shortcutEnabled,
      'sepay': sepayEnabled,
      'sepayAccount': sepayAccountNumber,
      'lastSync': lastSyncAt?.toIso8601String(),
      'displayName': displayName,
      'hasAvatar': avatarPath != null,
      'balanceAlerts': balanceAlertsEnabled,
    });
  }
}
