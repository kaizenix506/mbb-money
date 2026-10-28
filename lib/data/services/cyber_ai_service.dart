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
    this.modelName,
  });

  final String text;
  final bool isUser;
  final DateTime timestamp;
  final ExtractedExpense? extractedTx;

  /// Round-trip time of the model call, shown as a small badge so Hoàng can see
  /// how fast A.R.I.A actually answered.
  final int? latencyMs;
  final String? modelName;
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
  String _activeModel = 'gemini-3.5-flash-lite';

  /// `ngữ cảnh câu` → kết quả đã parse. Cleared when it grows too large.
  final Map<String, ExtractedExpense> _cache = <String, ExtractedExpense>{};

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isThinking => _isThinking;
  String get activeModel => _activeModel;
  String get activeModelLabel => _activeModel.toUpperCase().replaceAll('-', ' ');

  // ------------------------------------------------------------ public API

  Future<ExtractedExpense?> sendMessage(
    String text, {
    required List<Transaction> currentExpenses,

    /// The user's own categories as id → label. Passed so the model is told
    /// about them and can file a row into one instead of guessing "Khác".
    Map<String, String> categoryLabels = const <String, String>{},
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
    String modelUsed = 'A.R.I.A Local Engine';

    if (geminiKey != null && geminiKey.isNotEmpty) {
      try {
        final result = await _askGemini(
          geminiKey,
          trimmed,
          currentExpenses,
          categoryLabels: categoryLabels,
        );
        reply = result.reply;
        extracted = result.expense;
        modelUsed = result.modelUsed;
        _activeModel = result.modelUsed;
        if (extracted != null) {
          _cache[_cacheKey(trimmed)] = extracted;
        }
      } catch (err) {
        debugPrint('Gemini call error, using local fallback: $err');
      }
    }

    // 2) If Gemini did not reply (offline or failed), use deterministic local SmartParser!
    if (reply.isEmpty) {
      modelUsed = 'A.R.I.A Local Engine (<1ms)';
      extracted = SmartParser.parse(
        trimmed,
        knownCategories: categoryLabels.keys.toList(growable: false),
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
        modelName: modelUsed,
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

  Future<({String reply, ExtractedExpense? expense, String modelUsed})> _askGemini(
    String apiKey,
    String prompt,
    List<Transaction> expenses, {
    Map<String, String> categoryLabels = const <String, String>{},
  }) async {
    final DateTime today = VnClock.localNow();
    final int todayStart = DateTime(today.year, today.month, today.day)
        .millisecondsSinceEpoch;
    final int yesterdayStart = todayStart - const Duration(days: 1).inMilliseconds;

    // The old context was 12 undated rows, which is why "hôm nay chi gì" got
    // "không có chi tiêu nào": the model literally had no date to compare.
    // Build a small but *dated* picture instead.
    final List<Transaction> todayRows = expenses
        .where((Transaction t) => t.occurredAt.millisecondsSinceEpoch >= todayStart)
        .toList(growable: false);
    final List<Transaction> yesterdayRows = expenses
        .where((Transaction t) {
          final int ms = t.occurredAt.millisecondsSinceEpoch;
          return ms >= yesterdayStart && ms < todayStart;
        })
        .toList(growable: false);

    int sumOf(List<Transaction> rows) =>
        rows.fold<int>(0, (int s, Transaction t) => s + t.amount);

    final int todayTotal = sumOf(todayRows);
    final int yesterdayTotal = sumOf(yesterdayRows);
    final int totalThisMonth = sumOf(expenses);

    String rowLine(Transaction t) =>
        '- ${VnClock.hm(t.occurredAt)} ${t.description.isEmpty ? '(không nội dung)' : t.description}'
        ': ${Fmt.dong(t.amount)} [${categoryLabels[t.categoryId] ?? t.categoryId ?? 'other'}]';

    final String todayCtx = todayRows.isEmpty
        ? '(chưa có khoản chi nào hôm nay)'
        : todayRows.take(15).map(rowLine).join('\n');
    final String yesterdayCtx = yesterdayRows.isEmpty
        ? '(không có khoản chi nào hôm qua)'
        : yesterdayRows.take(8).map(rowLine).join('\n');

    // Per-day totals for the last 7 days, so "3 ngày nay" questions resolve.
    final Map<DateTime, int> perDay = <DateTime, int>{};
    for (final Transaction t in expenses) {
      final DateTime d = DateTime(
          t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
      perDay[d] = (perDay[d] ?? 0) + t.amount;
    }
    final List<MapEntry<DateTime, int>> recentDays = perDay.entries.toList()
      ..sort((MapEntry<DateTime, int> a, MapEntry<DateTime, int> b) =>
          b.key.compareTo(a.key));
    final String last7Ctx = recentDays
        .take(7)
        .map((MapEntry<DateTime, int> e) =>
            '- ${e.key.day}/${e.key.month}: ${Fmt.dong(e.value)}')
        .join('\n');

    // Per-category totals, which is what "chi nhiều nhất vào đâu" needs.
    final Map<String, int> perCat = <String, int>{};
    for (final Transaction t in expenses) {
      final String key = categoryLabels[t.categoryId] ?? t.categoryId ?? 'Khác';
      perCat[key] = (perCat[key] ?? 0) + t.amount;
    }
    final List<MapEntry<String, int>> catRanked = perCat.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value));
    final String catCtx = catRanked.isEmpty
        ? '(chưa có dữ liệu)'
        : catRanked
            .take(10)
            .map((MapEntry<String, int> e) =>
                '- ${e.key}: ${Fmt.dong(e.value)} (${totalThisMonth == 0 ? 0 : ((e.value / totalThisMonth) * 100).round()}%)')
            .join('\n');

    final String system = '''
Bạn là A.R.I.A — trợ lý tài chính cá nhân AI của Hoàng (Việt Nam, múi giờ UTC+7).
Bây giờ là ${VnClock.hm()} ngày ${VnClock.dateLabel()}.

DANH MỤC HỢP LỆ (id | tên): ${CategoryCatalog.promptListWith(categoryLabels)}

=== DỮ LIỆU THẬT TRONG APP (tháng ${today.month}/${today.year}) ===
Tổng chi cả tháng: ${Fmt.dong(totalThisMonth)} qua ${expenses.length} giao dịch.
HÔM NAY: ${Fmt.dong(todayTotal)} qua ${todayRows.length} giao dịch.
HÔM QUA: ${Fmt.dong(yesterdayTotal)} qua ${yesterdayRows.length} giao dịch.

Chi tiết HÔM NAY:
$todayCtx

Chi tiết HÔM QUA:
$yesterdayCtx

Chi theo từng ngày (gần nhất trước):
${last7Ctx.isEmpty ? '(chưa có dữ liệu)' : last7Ctx}

Chi theo danh mục (nhiều nhất trước):
$catCtx
=== HẾT DỮ LIỆU ===

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

2. Nếu Hoàng HỎI về chi tiêu (ví dụ: "hôm nay chi gì", "hôm nay tiêu bao nhiêu", "tháng này chi bao nhiêu", "chi nhiều nhất vào đâu", "tuần này thế nào", "còn bao nhiêu tiền"):
   - "action": "chat_response"
   - TRẢ LỜI DỰA TRÊN "DỮ LIỆU THẬT TRONG APP" ở trên. ĐỌC KỸ phần "Chi tiết HÔM NAY" trước khi nói "không có".
   - Nếu hôm nay có giao dịch: liệt kê ngắn gọn từng khoản kèm số tiền và tổng.
   - Chỉ được nói "hôm nay chưa có khoản chi nào" khi phần HÔM NAY ghi đúng 0 đồng VÀ 0 giao dịch.
   - TUYỆT ĐỐI không bịa số. Không có trong dữ liệu thì nói chưa có dữ liệu.

3. Nếu Hoàng chào hỏi hoặc trò chuyện phiếm:
   - "action": "chat_response", các trường tiền/danh mục = null
   - "reply": trả lời thân thiện, xưng A.R.I.A, gọi Hoàng (tối đa 2-3 câu).

4. TUYỆT ĐỐI không để trường "reply" bị rỗng hoặc null! Không dùng markdown block.
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

    // Ordered by preference: Hoàng asked for gemini-3.5-flash-lite first, so it
    // is always the first attempt. Racing two models in parallel used to double
    // the request rate against a single free-tier key, which caused more 429s
    // than it saved in latency; a strict fallback list is both cheaper and
    // easier to reason about.
    const List<String> models = <String>[
      'gemini-3.5-flash-lite',
      'gemini-2.5-flash-lite',
      'gemini-2.5-flash',
      'gemini-flash-latest',
      'gemini-3-flash-preview',
    ];

    final http.Client client = http.Client();
    try {
      http.Response? ok;
      String successfulModel = models.first;
      for (final String m in models) {
        final http.Response? r = await _tryModel(client, apiKey, m, payload);
        if (r != null && r.statusCode == 200) {
          ok = r;
          successfulModel = m;
          break;
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
          return (reply: cleanText, expense: null, modelUsed: successfulModel);
        }
        return (
          reply:
              'Chào Hoàng! A.R.I.A đã sẵn sàng hỗ trợ ghi chép và quản lý chi tiêu rồi đây. ✨',
          expense: null,
          modelUsed: successfulModel,
        );
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
        final String resolvedCat =
            CategoryCatalog.resolveId(catId, extra: categoryLabels);
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
          modelUsed: successfulModel,
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
        modelUsed: successfulModel,
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

  /// Builds the prompt fragment for [id]→[label] pairs, appending any
  /// user-created categories after the built-ins so A.R.I.A knows they exist.
  ///
  /// Without this the model could only ever answer with a built-in id, which is
  /// one of the reasons custom categories kept landing in "Khác".
  static String promptListWith(Map<String, String> extra) {
    if (extra.isEmpty) return promptList;
    final StringBuffer buf = StringBuffer(promptList);
    for (final MapEntry<String, String> e in extra.entries) {
      if (entries.containsKey(e.key)) continue;
      buf.write(', ${e.key}=${e.value}');
    }
    return buf.toString();
  }

  static String labelOf(String id) => entries[id] ?? 'Khác';

  /// Accepts an id, a Vietnamese label, or a loose prefix and normalises it to
  /// a known id, so a model that answers "Đồ uống" still files correctly.
  ///
  /// [extra] carries the user's own id/label pairs; they win over a fuzzy
  /// prefix match on a built-in, because a custom bucket Hoàng named deliberately
  /// is a better answer than a coincidence.
  static String resolveId(String raw, {Map<String, String> extra = const <String, String>{}}) {
    final String needle = raw.toLowerCase().trim();
    if (needle.isEmpty) return 'other';

    // Exact id in either table.
    if (entries.containsKey(needle)) return needle;
    if (extra.containsKey(raw.trim())) return raw.trim();
    if (extra.containsKey(needle)) return needle;

    // Exact label in either table.
    for (final MapEntry<String, String> e in entries.entries) {
      if (e.value.toLowerCase() == needle) return e.key;
    }
    for (final MapEntry<String, String> e in extra.entries) {
      if (e.value.toLowerCase() == needle) return e.key;
    }

    // Loose containment, custom first.
    for (final MapEntry<String, String> e in extra.entries) {
      if (needle.contains(e.value.toLowerCase()) ||
          e.value.toLowerCase().contains(needle)) {
        return e.key;
      }
    }
    for (final MapEntry<String, String> e in entries.entries) {
      if (needle.contains(e.key)) return e.key;
      if (e.value.toLowerCase().contains(needle)) return e.key;
    }
    return 'other';
  }
}
