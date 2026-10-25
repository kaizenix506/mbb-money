import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../repositories/secret_store.dart';
import '../repositories/settings_repository.dart';
import '../repositories/transaction_repository.dart';

/// Result of one inbox pull.
class WebhookPullReport {
  const WebhookPullReport({
    required this.added,
    required this.received,
    this.error,
  });

  final int added;
  final int received;
  final String? error;

  bool get ok => error == null;
  bool get isEmpty => received == 0;
}

/// Drains the Cloudflare Worker inbox (see `webhook/`) into the local database.
///
/// Why this exists: iOS cannot keep the app listening for a bank push. SePay
/// pushes to the Worker instead, the Worker parks each transaction in a KV
/// inbox, and this service pulls that inbox whenever the app gets a chance to
/// run. Nothing is lost while the app is closed — delivery is deferred, not
/// dropped.
///
/// Idempotency relies on the Worker sending `sepay:<id>` as [key], which the
/// repository stores as `reference_number`. Pulling overlapping windows is
/// therefore free, so [since] is intentionally generous rather than exact.
class WebhookIngestService {
  WebhookIngestService({
    required SecretStore secrets,
    required SettingsRepository settings,
    required TransactionRepository transactions,
    http.Client? client,
  })  : _secrets = secrets,
        _settings = settings,
        _transactions = transactions,
        _client = client ?? http.Client();

  final SecretStore _secrets;
  final SettingsRepository _settings;
  final TransactionRepository _transactions;
  final http.Client _client;

  /// How far back to ask each time. A day of overlap absorbs clock skew between
  /// the phone and the Worker; duplicates are removed by `reference_number`.
  static const Duration _overlap = Duration(days: 1);

  DateTime? _lastPull;

  Future<WebhookPullReport> pull() async {
    final String? base = _settings.webhookUrl;
    final String? token = await _secrets.readWebhookPullToken();
    if (base == null || base.isEmpty || token == null || token.isEmpty) {
      return const WebhookPullReport(
        added: 0,
        received: 0,
        error: 'Chưa cấu hình webhook',
      );
    }

    final DateTime since =
        _lastPull?.subtract(_overlap) ?? DateTime.now().subtract(const Duration(days: 30));

    final Uri uri = Uri.parse(
      '${base.replaceAll(RegExp(r'/+$'), '')}/pull'
      '?since=${since.millisecondsSinceEpoch}',
    );

    try {
      final http.Response res = await _client
          .get(uri, headers: <String, String>{'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 401) {
        return const WebhookPullReport(
          added: 0,
          received: 0,
          error: 'Webhook từ chối token',
        );
      }
      if (res.statusCode != 200) {
        return WebhookPullReport(
          added: 0,
          received: 0,
          error: 'Webhook lỗi ${res.statusCode}',
        );
      }

      final Map<String, Object?> body =
          jsonDecode(res.body) as Map<String, Object?>;
      final List<Object?> raw = (body['rows'] as List<Object?>?) ?? const <Object?>[];

      final List<
          ({
            int amount,
            bool isIncome,
            DateTime at,
            String content,
            String key,
            String? bank,
          })> rows = <({
        int amount,
        bool isIncome,
        DateTime at,
        String content,
        String key,
        String? bank,
      })>[];

      for (final Object? item in raw) {
        if (item is! Map<String, Object?>) continue;
        final int amount = (item['amount'] as num?)?.toInt() ?? 0;
        final String key = (item['key'] as String?) ?? '';
        if (amount <= 0 || key.isEmpty) continue;
        rows.add((
          amount: amount,
          isIncome: item['isIncome'] == true,
          at: DateTime.fromMillisecondsSinceEpoch(
            (item['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          ),
          content: (item['content'] as String?) ?? '',
          key: key,
          bank: item['bank'] as String?,
        ));
      }

      _lastPull = DateTime.now();
      if (rows.isEmpty) {
        return const WebhookPullReport(added: 0, received: 0);
      }

      final int added = await _transactions.ingestSepayRows(rows);
      return WebhookPullReport(added: added, received: rows.length);
    } on Object catch (e) {
      debugPrint('webhook pull failed: $e');
      return const WebhookPullReport(
        added: 0,
        received: 0,
        error: 'Không kết nối được webhook',
      );
    }
  }
}
