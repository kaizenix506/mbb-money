/// Where a transaction came from. Used for the "MB" badge in the UI and to
/// decide whether a row can be safely de-duplicated during sync.
enum TxSource {
  /// Typed in by the user.
  manual,

  /// Arrived through the iOS Shortcut deep link (`mbbmoney://add`).
  shortcut,

  /// Pulled from the SePay transactions API.
  sepay;

  String get storageKey => name;

  static TxSource fromKey(String? key) {
    return switch (key) {
      'shortcut' => TxSource.shortcut,
      'sepay' => TxSource.sepay,
      _ => TxSource.manual,
    };
  }

  /// Short label shown next to auto-imported rows.
  String get badge => switch (this) {
        TxSource.manual => 'Tay',
        TxSource.shortcut || TxSource.sepay => 'MB',
      };

  bool get isFromBank => this != TxSource.manual;
}
