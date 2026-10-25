import 'package:flutter/foundation.dart';

import '../../core/formatters.dart';
import '../sepay_client.dart';
import 'secret_store.dart';
import 'transaction_repository.dart';

class SyncReport {
  const SyncReport({
    required this.added,
    required this.fetched,
    this.error,
  });

  final int added;
  final int fetched;
  final String? error;

  bool get ok => error == null;
}

/// Pulls transactions from SePay and hands them to the repository.
///
/// Overlap window: we re-fetch the last 3 days on every sync instead of
/// trusting a cursor. SePay can post a transaction minutes after it happened,
/// so an exact `since` would silently drop late arrivals. De-duplication by
/// `sepay:<id>` key makes the overlap free.
class SyncService {
  SyncService({
    required SecretStore secrets,
    required TransactionRepository transactions,
    SepayClient Function(String token)? clientFactory,
  })  : _secrets = secrets,
        _transactions = transactions,
        _clientFactory = clientFactory;

  static const Duration _overlap = Duration(days: 3);
  static const int _pageSize = 100;

  final SecretStore _secrets;
  final TransactionRepository _transactions;
  final SepayClient Function(String token)? _clientFactory;

  SepayClient _client(String token) =>
      _clientFactory?.call(token) ?? SepayClient(token: token);

  Future<SyncReport> syncSepay({String? accountNumber}) async {
    final String? token = await _secrets.readSepayToken();
    if (token == null || token.isEmpty) {
      return const SyncReport(
        added: 0,
        fetched: 0,
        error: 'Chưa kết nối SePay',
      );
    }

    try {
      final List<SepayTransaction> remote =
          await _client(token).fetchTransactions(
        since: DateTime.now().subtract(_overlap),
        limit: _pageSize,
        accountNumber: accountNumber,
      );

      // User only wants expense tracking (chỉ thu thập chi). Filter out income rows.
      final List<SepayTransaction> expensesOnly =
          remote.where((SepayTransaction t) => !t.isIncome).toList();

      final int added = await _transactions.ingestSepayRows(
        expensesOnly
            .map(
              (SepayTransaction t) => (
                amount: t.amount,
                isIncome: false,
                at: t.occurredAt,
                content: t.content,
                key: t.dedupeKey,
                bank: t.bankBrandName,
              ),
            )
            .toList(growable: false),
      );

      return SyncReport(added: added, fetched: remote.length);
    } on SepayException catch (e) {
      debugPrint('SePay sync failed: ${e.message}');
      return SyncReport(added: 0, fetched: 0, error: e.message);
    } on Object catch (e) {
      debugPrint('SePay sync crashed: $e');
      return const SyncReport(
        added: 0,
        fetched: 0,
        error: 'Đồng bộ thất bại, thử lại sau.',
      );
    }
  }

  /// Verifies the token without importing anything.
  Future<SyncReport> testConnection(String token) async {
    try {
      final List<SepayTransaction> probe =
          await _client(token).fetchTransactions(limit: 1);
      return SyncReport(added: 0, fetched: probe.length);
    } on SepayException catch (e) {
      return SyncReport(added: 0, fetched: 0, error: e.message);
    }
  }

  /// Human summary used by SnackBars.
  static String describe(SyncReport report) {
    if (!report.ok) return report.error!;
    if (report.added == 0) {
      return 'Không có giao dịch mới (đã kiểm tra ${report.fetched})';
    }
    return 'Đã thêm ${report.added} giao dịch mới';
  }

  /// Timestamps are shown in the settings screen; kept here so formatting
  /// stays next to the sync semantics.
  static String lastSyncLabel(DateTime? at) {
    if (at == null) return 'Chưa đồng bộ';
    return 'Cập nhật ${Fmt.dayMonth(at)} · ${Fmt.time(at)}';
  }
}
