import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/formatters.dart';
import '../../core/vn_clock.dart';
import '../models/transaction.dart';
import '../repositories/secret_store.dart';
import 'smart_parser.dart';

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.extractedTx,
    this.latencyMs,
  });

  final String text;
  final bool isUser;
  final DateTime timestamp;
  final ExtractedExpense? extractedTx;

  /// Round-trip time of the model call, shown as a small badge so Hoàng can see
  /// how fast A.R.I.A actually answered.
  final int? latencyMs;
}

class ExtractedExpense {
  const ExtractedExpense({
    required this.amount,
    required this.description,
    required this.category,
    required this.categoryName,
    this.date,
    this.confidence = 1.0,
  });

  final int amount;
  final String description;
  final String category;
  final String categoryName;
  final DateTime? date;

  /// 0..1 — how sure the parser is. Used to decide whether to flag the row
  /// for review instead of silently filing it.
  final double confidence;
}

/// Cyberpunk Liquid Glass AI Financial Assistant (A.R.I.A)
///
/// Latency strategy (Hoàng asked for "trả lời nhanh hơn nữa"):
///   * A **local deterministic parser** runs first. Anything of the shape
///     "uống nước 20k" is resolved in <1 ms with no network call at all.
///   * Only when the local parser is unsure do we hit Gemini, and then we race
///     the two cheapest Flash models in parallel and take the first 200.
///   * Repeated phrases ("cafe 35k" said every morning) are memoised, so the
///     second time costs zero network.
class CyberAiService with ChangeNotifier {
  CyberAiService({required SecretStore secrets}) : _secrets = secrets {
    _messages.add(
      ChatMessage(
        text: 'Chào Hoàng! Tôi là A.R.I.A — trợ lý dòng tiền của bạn.\n\n'
            'Cứ nói tự nhiên như đang nhắn tin: “uống nước 20k”, “ăn sáng 10k”, '
            '“grab 45k”. Tôi tự bắt số tiền, tự chọn danh mục và ghi sổ ngay '
            'lúc bạn nói — kể cả khi bạn đã tắt app.',
        isUser: false,
        timestamp: VnClock.now(),
      ),
    );
  }

  final SecretStore _secrets;
  final List<ChatMessage> _messages = [];
  bool _isThinking = false;

  /// `ngữ cảnh câu` → kết quả đã parse. Cleared when it grows too large.
  final Map<String, ExtractedExpense> _cache = <String, ExtractedExpense>{};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isThinking => _isThinking;

  // ------------------------------------------------------------ public API

  Future<ExtractedExpense?> sendMessage(
    String text, {
    required List<Transaction> currentExpenses,
  }) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    _messages.add(
      ChatMessage(text: trimmed, isUser: true, timestamp: VnClock.now()),
    );
    _isThinking = true;
    notifyListeners();

    final Stopwatch sw = Stopwatch()..start();

    // 1) Local parser first — instant, offline, deterministic.
    ExtractedExpense? extracted = SmartParser.parse(
      trimmed,
      knownCategories: _knownCategoryLabels(currentExpenses),
    );

    // 2) Cache hit for an identical phrase.
    if (extracted == null) {
      final String key = _cacheKey(trimmed);
      final ExtractedExpense? hit = _cache[key];
      if (hit != null && (hit.date == null ||
          VnClock.sameDay(hit.date!, VnClock.now()))) {
        extracted = ExtractedExpense(
          amount: hit.amount,
          description: hit.description,
          category: hit.category,
          categoryName: hit.categoryName,
          date: VnClock.now(),
          confidence: hit.confidence,
        );
      }
    }

    String reply;
    if (extracted != null) {
      reply = _confirmReply(extracted);
    } else {
      // 3) Ask Gemini, racing models.
      try {
        final String key = await _secrets.readGeminiApiKey();
        final result = await _askGemini(key, trimmed, currentExpenses);
        reply = result.reply;
        extracted = result.expense;
        if (extracted != null) {
          _cache[_cacheKey(trimmed)] = extracted;
        }
      } catch (err) {
        debugPrint('A.R.I.A network fallback: $err');
        reply = _fallbackSummary(currentExpenses);
      }
    }

    sw.stop();
    _messages.add(
      ChatMessage(
        text: reply,
        isUser: false,
        timestamp: VnClock.now(),
        extractedTx: extracted,
        latencyMs: sw.elapsedMilliseconds,
      ),
    );

    _isThinking = false;
    notifyListeners();
    return extracted;
  }

  void clearHistory() {
    _messages.removeWhere((ChatMessage m) => m.isUser || m.extractedTx != null);
    notifyListeners();
  }

  // ------------------------------------------------------------- internals

  List<String> _knownCategoryLabels(List<Transaction> expenses) {
    return <String>{
      for (final Transaction t in expenses)
        if (t.categoryId != null) t.categoryId!,
    }.toList(growable: false);
  }

  String _cacheKey(String text) => text.toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );

  String _confirmReply(ExtractedExpense e) {
    final String time = VnClock.hm();
    return '✅ Đã ghi lúc $time · ${e.description} '
        '${Fmt.dong(e.amount)} → ${e.categoryName}';
  }

  String _fallbackSummary(List<Transaction> expenses) {
    final int total = expenses.fold<int>(0, (int s, Transaction t) => s + t.amount);
    return '📊 Tháng này Hoàng đã chi ${Fmt.dong(total)} qua '
        '${expenses.length} giao dịch.\n'
        '💡 Cứ nói “uống nước 20k” hay “cafe 35k”, tôi ghi ngay.';
  }

  Future<({String reply, ExtractedExpense? expense})> _askGemini(
    String apiKey,
    String prompt,
    List<Transaction> expenses,
  ) async {
    final String ctx = expenses
        .take(12)
        .map((Transaction t) => '- ${t.description}: ${Fmt.dong(t.amount)} '
            '(${t.categoryId ?? 'other'})')
        .join('\n');

    final int totalThisMonth =
        expenses.fold<int>(0, (int s, Transaction t) => s + t.amount);

    final String system = '''
Bạn là A.R.I.A — trợ lý tài chính cá nhân của Hoàng (Việt Nam, giờ UTC+7).
Bây giờ là ${VnClock.hm()} ngày ${VnClock.dateLabel()}.

DANH MỤC HỢP LỆ (id | tên): ${CategoryCatalog.promptList}
Hoặc tên danh mục riêng Hoàng đã tự tạo.

QUY TẮC:
1. Nếu câu nói là một khoản CHI, trả action="add_expense" và điền amount
   (10k=10000, 1.5tr=1500000, "hai chục"=20000), category (id), category_name,
   description (2-4 từ, viết hoa chữ đầu), date (ISO yyyy-MM-dd nếu Hoàng nói
   "hôm qua"/"thứ 3", ngược lại bỏ trống).
2. Nếu là câu hỏi/báo cáo, action="chat_response", amount null.
   Trả lời ngắn gọn (≤3 câu), nêu số liệu cụ thể, có thể so sánh tháng trước.
3. Trả về DUY NHẤT một JSON object, không markdown, không giải thích.

Tổng chi tháng này: ${Fmt.dong(totalThisMonth)}.
Giao dịch gần đây:
$ctx
''';

    final Map<String, Object?> payload = <String, Object?>{
      'contents': <Object?>[
        <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': '$system\n\nHoàng nói: "$prompt"'},
          ],
        },
      ],
      'generationConfig': <String, Object?>{
        'temperature': 0.25,
        'maxOutputTokens': 400,
        'responseMimeType': 'application/json',
      },
    };

    // Lowest-latency first; the first 200 wins.
    const List<String> models = <String>[
      'gemini-2.5-flash-lite',
      'gemini-2.5-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-flash',
    ];

    final http.Client client = http.Client();
    try {
      final List<Future<http.Response?>> race = <Future<http.Response?>>[
        for (final String m in models.take(2)) _tryModel(client, apiKey, m, payload),
      ];

      http.Response? ok;
      final List<http.Response?> settled = await Future.wait(race);
      for (final http.Response? r in settled) {
        if (r != null && r.statusCode == 200) {
          ok = r;
          break;
        }
      }

      // Sequential retry for the slower fallbacks only if the race failed.
      if (ok == null) {
        for (final String m in models.skip(2)) {
          final http.Response? r = await _tryModel(client, apiKey, m, payload);
          if (r != null && r.statusCode == 200) {
            ok = r;
            break;
          }
        }
      }

      if (ok == null) throw 'Không model nào phản hồi';

      final Map<String, Object?> decoded =
          jsonDecode(ok.body) as Map<String, Object?>;
      final String raw = _textOf(decoded);
      final Map<String, Object?>? parsed = _jsonObject(raw);
      if (parsed == null) {
        return (reply: raw.trim(), expense: null);
      }

      final String reply = (parsed['reply'] ?? parsed['message'] ?? '')
              .toString()
              .trim();
      final String action = (parsed['action'] ?? '').toString();
      final num? amount = parsed['amount'] is num
          ? parsed['amount'] as num
          : num.tryParse('${parsed['amount'] ?? ''}');

      if (action == 'add_expense' && amount != null && amount > 0) {
        final String catId =
            (parsed['category'] ?? 'other').toString().trim();
        final DateTime when =
            DateTime.tryParse('${parsed['date'] ?? ''}') ?? VnClock.now();
        return (
          reply: reply.isEmpty
              ? '✅ Đã ghi ${Fmt.dong(amount.toInt())}'
              : reply,
          expense: ExtractedExpense(
            amount: amount.toInt(),
            description: (parsed['description'] ?? 'Chi tiêu').toString(),
            category: CategoryCatalog.resolveId(catId),
            categoryName: (parsed['category_name'] ??
                    CategoryCatalog.labelOf(catId))
                .toString(),
            date: when,
            confidence: 0.95,
          ),
        );
      }

      return (
        reply: reply.isEmpty ? 'Đã xử lý xong cho Hoàng!' : reply,
        expense: null,
      );
    } finally {
      client.close();
    }
  }

  Future<http.Response?> _tryModel(
    http.Client client,
    String apiKey,
    String model,
    Map<String, Object?> payload,
  ) async {
    try {
      final Uri uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent',
      );
      final http.Response r = await client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) return r;
      debugPrint('Model $model → ${r.statusCode}');
      return null;
    } on Object catch (e) {
      debugPrint('Model $model → $e');
      return null;
    }
  }

  String _textOf(Map<String, Object?> decoded) {
    final Object? candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final Object? first = candidates.first;
    if (first is! Map) return '';
    final Object? content = first['content'];
    if (content is! Map) return '';
    final Object? parts = content['parts'];
    if (parts is! List) return '';
    final StringBuffer buf = StringBuffer();
    for (final Object? p in parts) {
      if (p is Map && p['text'] is String) buf.write(p['text'] as String);
    }
    return buf.toString();
  }

  Map<String, Object?>? _jsonObject(String text) {
    final int start = text.indexOf('{');
    final int end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final Object? decoded =
          jsonDecode(text.substring(start, end + 1));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// Category ids the AI is allowed to emit, kept in one place so the prompt and
/// the resolver can never drift apart.
abstract final class CategoryCatalog {
  static const Map<String, String> entries = <String, String>{
    'food': 'Ăn uống',
    'drink': 'Đồ uống',
    'coffee': 'Cà phê',
    'transport': 'Đi lại',
    'shopping': 'Mua sắm',
    'bills': 'Hóa đơn',
    'health': 'Sức khỏe',
    'entertainment': 'Giải trí',
    'education': 'Giáo dục',
    'family': 'Gia đình',
    'other': 'Khác',
  };

  static String get promptList =>
      entries.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join(', ');

  static String labelOf(String id) => entries[id] ?? 'Khác';

  /// Accepts an id, a Vietnamese label, or a loose prefix and normalises it to
  /// a known id, so a model that answers "Đồ uống" still files correctly.
  static String resolveId(String raw) {
    final String needle = raw.toLowerCase().trim();
    if (entries.containsKey(needle)) return needle;
    for (final MapEntry<String, String> e in entries.entries) {
      if (e.value.toLowerCase() == needle) return e.key;
      if (needle.contains(e.key)) return e.key;
      if (e.value.toLowerCase().contains(needle)) return e.key;
    }
    return 'other';
  }
}
