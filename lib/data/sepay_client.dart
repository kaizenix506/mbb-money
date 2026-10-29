import 'dart:convert';
import 'dart:io' show HttpClient, HttpClientRequest, HttpClientResponse, HttpHeaders, SocketException;


/// Lean client for SePay's **user API** (the one that reads your own linked
/// bank accounts — not the merchant payment-gateway API).
///
/// Endpoint: `GET https://my.sepay.vn/userapi/transactions/list`
/// Auth:     `Authorization: Bearer <token>` — token is created at
///           my.sepay.vn ▸ Công ty ▸ API Access.
///
/// Notes that shaped this implementation:
///  * SePay returns amounts as **strings with decimals** ("18067000.00"),
///    so we parse to a rational rather than trusting an int cast.
///  * A transaction may be inbound (`amount_in`) or outbound (`amount_out`);
///    exactly one of the two carries the value.
///  * Dates come as local time `yyyy-MM-dd HH:mm:ss` with no timezone.
///
/// This client only *reads*. The app never sends money anywhere.
class SepayClient {
  SepayClient({required this.token, HttpClientFactory? httpClient})
      : _httpClient = httpClient;

  static const String baseUrl = 'https://my.sepay.vn/userapi';
  static const int pageSize = 100;

  final String token;
  final HttpClientFactory? _httpClient;

  /// Throws [SepayException] with a message safe to show in a SnackBar.
  Future<List<SepayTransaction>> fetchTransactions({
    DateTime? since,
    int limit = pageSize,
    String? accountNumber,
  }) async {
    if (token.trim().isEmpty) {
      throw const SepayException('Chưa có API token');
    }

    final Uri uri = Uri.parse('$baseUrl/transactions/list').replace(
      queryParameters: <String, String>{
        'limit': '$limit',
        if (since != null) 'transaction_date_min': _formatDate(since),
        if (accountNumber != null) 'account_number': accountNumber,
      },
    );

    final String body;
    try {
      body = await _get(uri);
    } on SocketException {
      throw const SepayException(
        'Không kết nối được SePay. Kiểm tra mạng rồi thử lại.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const SepayException('SePay trả về dữ liệu không đọc được.');
    }

    if (decoded is! Map<String, Object?>) {
      throw const SepayException('SePay trả về dữ liệu không đọc được.');
    }

    final int status = (decoded['status'] as num?)?.toInt() ?? 0;
    if (status != 200) {
      throw SepayException(_friendlyError(status, decoded));
    }

    final Object? list = decoded['transactions'];
    if (list is! List<Object?>) {
      return const <SepayTransaction>[];
    }

    return list
        .whereType<Map<String, Object?>>()
        .map(SepayTransaction.fromJson)
        .where((SepayTransaction t) => t.amount > 0)
        .toList(growable: false);
  }

  /// Cheap health check for the "Kiểm tra kết nối" button in Settings.
  /// Fetches a single row to confirm the token and bank link are live.
  Future<int> verify() async {
    final List<SepayTransaction> probe =
        await fetchTransactions(limit: 1);
    return probe.length;
  }

  // ------------------------------------------------------------- transport

  Future<String> _get(Uri uri) async {
    final HttpClient client = _httpClient?.call() ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse res = await req.close();
      final String body = await res.transform(utf8.decoder).join();

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const SepayException(
          'Token không hợp lệ hoặc đã bị thu hồi. Tạo token mới trên SePay.',
        );
      }
      if (res.statusCode == 429) {
        throw const SepayException(
          'Gọi SePay quá nhanh, chờ vài giây rồi thử lại.',
        );
      }
      if (res.statusCode >= 500) {
        throw const SepayException('SePay đang lỗi, thử lại sau ít phút.');
      }
      return body;
    } finally {
      client.close(force: false);
    }
  }

  static String _friendlyError(int status, Map<String, Object?> body) {
    if (status == 401) {
      return 'Token không hợp lệ hoặc đã bị thu hồi.';
    }
    final Object? err = body['error'];
    if (err is String && err.isNotEmpty) {
      return 'SePay: $err';
    }
    return 'SePay trả về mã lỗi $status.';
  }

  static String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

/// One row from SePay's `transactions/list` response.
///
/// Only the fields the app uses are modelled; the rest stay in [_raw] so a
/// future screen (e.g. "xem tin nhắn gốc") can reach them.
class SepayTransaction {
  const SepayTransaction({
    required this.id,
    required this.amount,
    required this.isIncome,
    required this.occurredAt,
    required this.content,
    this.referenceNumber,
    this.bankBrandName,
    this.accountNumber,
    Map<String, Object?>? raw,
  }) : _raw = raw ?? const <String, Object?>{};

  final String id;

  /// Always positive, in đồng.
  final int amount;
  final bool isIncome;
  final DateTime occurredAt;

  /// SePay's `transaction_content` — the bank's transfer memo.
  final String content;

  final String? referenceNumber;
  final String? bankBrandName;
  final String? accountNumber;
  // Kept verbatim so an unexpected bank field can still be inspected without
  // re-fetching; not read by the app itself.
  // ignore: unused_field
  final Map<String, Object?> _raw;

  /// Stable de-dupe key. Prefixed so it cannot collide with an SMS reference.
  String get dedupeKey => 'sepay:$id';

  static SepayTransaction fromJson(Map<String, Object?> json) {
    final int amountIn = _money(json['amount_in']);
    final int amountOut = _money(json['amount_out']);
    final bool isIncome = amountIn > 0;

    return SepayTransaction(
      id: '${json['id']}',
      amount: isIncome ? amountIn : amountOut,
      isIncome: isIncome,
      occurredAt: _dateTime(json['transaction_date']),
      content: (json['transaction_content'] as String? ?? '').trim(),
      referenceNumber: (json['reference_number'] as String?)?.trim(),
      bankBrandName: json['bank_brand_name'] as String?,
      accountNumber: json['account_number'] as String?,
      raw: json,
    );
  }

  /// `"18067000.00"` / `18067000` / `null` → 18067000.
  static int _money(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.round();
    final String s = value.toString().replaceAll(',', '').trim();
    final double? parsed = double.tryParse(s);
    return parsed == null ? 0 : parsed.round();
  }

  /// SePay sends local Vietnamese time with no offset, e.g.
  /// `"2026-10-24 14:30:15"`.
  static DateTime _dateTime(Object? value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return DateTime.now();

    final List<String> parts = raw.split(RegExp(r'[\sT]+'));
    final List<String> ymd = parts.first.split('-');
    if (ymd.length != 3) return DateTime.now();

    int pick(List<String> src, int index) =>
        index < src.length ? (int.tryParse(src[index]) ?? 0) : 0;

    final List<String> hms =
        parts.length > 1 ? parts[1].split(':') : const <String>[];

    return DateTime(
      pick(ymd, 0),
      pick(ymd, 1),
      pick(ymd, 2),
      pick(hms, 0),
      pick(hms, 1),
      pick(hms, 2),
    );
  }
}

class SepayException implements Exception {
  const SepayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Injectable transport so tests can stub the HTTP layer.
typedef HttpClientFactory = HttpClient Function();
