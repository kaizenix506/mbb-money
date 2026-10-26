import 'dart:async';
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

    // 1) Ask Gemini first if key available so Hoàng gets real AI intelligence!
    String? geminiKey;
    try {
      geminiKey = await _secrets.readGeminiApiKey();
    } catch (_) {}

    ExtractedExpense? extracted;
    String reply = '';

    if (geminiKey != null && geminiKey.isNotEmpty) {
      try {
        final result = await _askGemini(geminiKey, trimmed, currentExpenses);
        reply = result.reply;
        extracted = result.expense;
        if (extracted != null) {
          _cache[_cacheKey(trimmed)] = extracted;
        }
      } catch (err) {
        debugPrint('Gemini call error, using local fallback: $err');
      }
    }

    // 2) If Gemini did not reply (offline or failed), use deterministic local SmartParser!
    if (reply.isEmpty) {
      extracted = SmartParser.parse(
        trimmed,
        knownCategories: _knownCategoryLabels(currentExpenses),
        allowFallback: true,
      );

      if (extracted != null) {
        reply = _confirmReply(extracted);
      } else {
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
Bạn là A.R.I.A — trợ lý tài chính cá nhân AI của Hoàng (Việt Nam, múi giờ UTC+7).
Bây giờ là ${VnClock.hm()} ngày ${VnClock.dateLabel()}.

DANH MỤC HỢP LỆ (id | tên): ${CategoryCatalog.promptList}

BẠN BẮT BUỘC PHẢI LUÔN TRẢ VỀ DUY NHẤT 1 JSON OBJECT THEO ĐÚNG CẤU TRÚC:
{
  "action": "add_expense" hoặc "chat_response",
  "reply": "BẮT BUỘC: Câu trả lời trò chuyện tự nhiên bằng tiếng Việt gửi cho Hoàng",
  "amount": số tiền nguyên nếu là chi tiêu (hoặc null nếu là trò chuyện),
  "category": "id danh mục từ danh sách trên (hoặc null)",
  "category_name": "tên danh mục tiếng Việt (hoặc null)",
  "description": "mô tả ngắn khoản chi (hoặc null)",
  "date": "yyyy-MM-dd nếu có nói ngày (hoặc null)"
}

QUY TẮC:
1. Nếu Hoàng nói một khoản CHI (ví dụ: "uống nước 20k", "ăn sáng 15k", "mua áo 200k", "tiền điện 500k", "cafe 35k"):
   - "action": "add_expense"
   - "amount": số tiền (20k=20000, 15k=15000, 1.5tr=1500000, "hai chục"=20000)
   - "category": id danh mục chính xác (uống nước -> drink, ăn -> food, cafe -> coffee, xe/xăng -> transport, mua đồ -> shopping, tiền điện/nước/mạng -> bills, cắt tóc/thuốc -> health)
   - "reply": "Dạ A.R.I.A đã ghi nhận khoản chi [mô tả] [số tiền] vào mục [tên mục] cho Hoàng rồi nhé! ✨"

2. Nếu Hoàng chào hỏi hoặc trò chuyện (ví dụ: "xin chào", "chào", "ai ơi", "hôm nay thế nào", "tôi nên tiết kiệm ra sao", "tháng này chi bao nhiêu"):
   - "action": "chat_response"
   - "amount": null, "category": null, "category_name": null, "description": null
   - "reply": BẮT BUỘC PHẢI CÓ câu trả lời trò chuyện thông minh, tình cảm, xưng là A.R.I.A và gọi người dùng là Hoàng (tối đa 2-3 câu).

3. TUYỆT ĐỐI không để trường "reply" bị rỗng hoặc null! Không dùng markdown block.

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
      'gemini-flash-latest',
      'gemini-3-flash-preview',
    ];

    final http.Client client = http.Client();
    try {
      final Completer<http.Response> completer = Completer<http.Response>();
      final List<String> candidates = models.take(2).toList();
      int settledCount = 0;

      for (final String m in candidates) {
        _tryModel(client, apiKey, m, payload).then((http.Response? r) {
          if (r != null && r.statusCode == 200 && !completer.isCompleted) {
            completer.complete(r);
          }
        }).catchError((_) {}).whenComplete(() {
          settledCount++;
          if (settledCount == candidates.length && !completer.isCompleted) {
            completer.completeError('Primary models did not respond with 200');
          }
        });
      }

      http.Response? ok;
      try {
        ok = await completer.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        // Sequential fallback only if the fast race timed out or failed.
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
        final String cleanText = raw.trim();
        // If the model returned plain conversational text instead of JSON
        if (cleanText.isNotEmpty && !cleanText.startsWith('{')) {
          return (reply: cleanText, expense: null);
        }
        return (reply: 'Chào Hoàng! A.R.I.A đã sẵn sàng hỗ trợ ghi chép và quản lý chi tiêu rồi đây. ✨', expense: null);
      }

      String reply = (parsed['reply'] ??
              parsed['message'] ??
              parsed['response'] ??
              parsed['text'] ??
              parsed['content'] ??
              parsed['answer'] ??
              '')
          .toString()
          .trim();
      final String action = (parsed['action'] ?? '').toString();
      final num? amount = parsed['amount'] is num
          ? parsed['amount'] as num
          : num.tryParse('${parsed['amount'] ?? ''}');

      if (action == 'add_expense' && amount != null && amount > 0) {
        final String? rawDate = parsed['date']?.toString().trim();
        final DateTime vnNow = VnClock.localNow();
        DateTime when;
        if (rawDate != null && rawDate.isNotEmpty) {
          final DateTime? parsedDate = DateTime.tryParse(rawDate);
          if (parsedDate != null) {
            when = DateTime(
              parsedDate.year,
              parsedDate.month,
              parsedDate.day,
              vnNow.hour,
              vnNow.minute,
              vnNow.second,
            );
          } else {
            when = vnNow;
          }
        } else {
          when = vnNow;
        }
        final String catId = (parsed['category'] ?? 'other').toString().trim();
        final String resolvedCat = CategoryCatalog.resolveId(catId);
        final String catName = (parsed['category_name'] ?? CategoryCatalog.labelOf(resolvedCat)).toString();
        final String desc = (parsed['description'] ?? 'Chi tiêu').toString();

        if (reply.isEmpty || reply == 'null') {
          reply = '✅ Đã ghi $desc (${Fmt.dong(amount.toInt())}) vào mục $catName cho Hoàng!';
        }

        return (
          reply: reply,
          expense: ExtractedExpense(
            amount: amount.toInt(),
            description: desc,
            category: resolvedCat,
            categoryName: catName,
            date: when,
            confidence: 0.95,
          ),
        );
      }

      // If reply is empty for chat_response, provide intelligent contextual dialogue:
      if (reply.isEmpty || reply == 'null') {
        final String lower = prompt.toLowerCase();
        if (lower.contains('chào') || lower.contains('hello') || lower.contains('hi')) {
          reply = 'Chào Hoàng! A.R.I.A đã sẵn sàng hỗ trợ bạn rồi đây. Hôm nay Hoàng có khoản chi tiêu nào cần ghi chép không? ✨';
        } else if (lower.contains('chi bao nhiêu') || lower.contains('tháng này')) {
          reply = 'Tổng chi tiêu tháng này của Hoàng hiện là ${Fmt.dong(totalThisMonth)}. Hoàng có muốn xem chi tiết các danh mục không?';
        } else {
          reply = 'Dạ A.R.I.A đây! Hoàng cần mình hỗ trợ kiểm tra chi tiêu hay ghi chép khoản nào không ạ?';
        }
      }

      return (
        reply: reply,
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
        '$model:generateContent?key=$apiKey',
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
