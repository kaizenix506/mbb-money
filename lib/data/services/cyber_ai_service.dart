import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';
import '../repositories/secret_store.dart';
import '../../core/formatters.dart';

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.extractedTx,
  });

  final String text;
  final bool isUser;
  final DateTime timestamp;
  final ExtractedExpense? extractedTx;
}

class ExtractedExpense {
  const ExtractedExpense({
    required this.amount,
    required this.description,
    required this.category,
    required this.categoryName,
    this.date,
  });

  final int amount;
  final String description;
  final String category;
  final String categoryName;
  final DateTime? date;
}

/// Cyberpunk Liquid Glass AI Financial Assistant (A.R.I.A)
/// Powered by Google Gemini 2.5 Flash Lite API with 3 verified keys from Hoang.
/// Automatically extracts natural language expenses (e.g. "ăn sáng hết 10k")
/// and creates actual transactions in SQLite!
class CyberAiService with ChangeNotifier {
  CyberAiService({required SecretStore secrets}) : _secrets = secrets {
    _messages.add(
      ChatMessage(
        text: 'Chào Hoàng! Tôi là A.R.I.A 2077 — Trợ lý AI chuyên quản lý dòng tiền chi tiêu cho bạn.\n\n'
            '💡 Bạn có thể nói tự nhiên: *"ăn sáng hết 10k"*, *"mua trà sữa 35k"*, *"đổ xăng 50k"*, tôi sẽ tự động trích xuất số tiền, phân loại danh mục và ghi sổ cho bạn ngay lập tức!',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  final SecretStore _secrets;
  final List<ChatMessage> _messages = [];
  bool _isThinking = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isThinking => _isThinking;

  Future<ExtractedExpense?> sendMessage(
    String text, {
    required List<Transaction> currentExpenses,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    _messages.add(ChatMessage(text: trimmed, isUser: true, timestamp: DateTime.now()));
    _isThinking = true;
    notifyListeners();

    ExtractedExpense? extracted;
    String botReply;

    try {
      final geminiKey = await _secrets.readGeminiApiKey();
      final aiResult = await _callGeminiFlashLite(geminiKey, trimmed, currentExpenses);

      botReply = aiResult.reply;
      extracted = aiResult.expense;
    } catch (err) {
      debugPrint('Gemini Flash Lite API error: $err, falling back to smart local heuristics');
      final fallbackResult = _evaluateLocalEngine(trimmed, currentExpenses);
      botReply = fallbackResult.reply;
      extracted = fallbackResult.expense;
    }

    _messages.add(
      ChatMessage(
        text: botReply,
        isUser: false,
        timestamp: DateTime.now(),
        extractedTx: extracted,
      ),
    );

    _isThinking = false;
    notifyListeners();
    return extracted;
  }

  Future<({String reply, ExtractedExpense? expense})> _callGeminiFlashLite(
    String apiKey,
    String prompt,
    List<Transaction> expenses,
  ) async {
    final recentHistory = expenses
        .take(10)
        .map((t) => '- ${t.description}: ${Fmt.dong(t.amount)} (${t.categoryId ?? 'other'})')
        .join('\n');

    final systemInstruction = '''
Bạn là A.R.I.A - Trợ lý AI tài chính cá nhân thông minh phong cách Liquid Glass / Cyberpunk 2077 cho người dùng tên là Hoàng.
Bạn chuyên quản lý và tối ưu hóa CHI TIÊU (Expenses).

DANH MỤC CHI TIÊU HỢP LỆ:
- food: Ăn uống (cơm, bún, phở, ăn sáng, ăn trưa, ăn tối, đồ ăn vặt...)
- coffee: Cà phê & Đồ uống (cafe, trà sữa, highlands, starbucks, phúc long...)
- transport: Đi lại (grab, xăng, xe buýt, be, sửa xe, gửi xe...)
- shopping: Mua sắm (quần áo, shopee, tiki, lazada, đồ dùng...)
- bills: Hóa đơn (điện, nước, internet, tiền nhà, phí dịch vụ...)
- health: Sức khỏe & Thuốc (thuốc, khám bệnh, vitamin, gym...)
- entertainment: Giải trí (xem phim, game, netflix, spotify, du lịch...)
- education: Giáo dục & Sách (sách vở, khóa học, học phí...)
- other: Khác

NHIỆM VỤ CỦA BẠN:
1. Nếu câu nói của Hoàng là một khoản chi tiêu (ví dụ: "ăn sáng hết 10k", "vừa mua cafe 30k", "đổ xăng 50k", "chi 120k shopee"):
   - Hãy trích xuất "amount" (số tiền dạng số nguyên, ví dụ 10k = 10000, 1.5tr = 1500000).
   - "category": một trong các id ở trên.
   - "category_name": tên tiếng Việt của danh mục.
   - "description": tên khoản chi ngắn gọn (viết hoa chữ cái đầu, ví dụ "Ăn Sáng", "Cà Phê", "Đổ Xăng").
   - "reply": Lời phản hồi thân thiện, ngầu, xác nhận cho Hoàng biết đã ghi nhận số tiền và danh mục tương ứng.

2. Nếu Hoàng hỏi về báo cáo chi tiêu, tổng tiền, lời khuyên:
   - Hãy phân tích dựa trên lịch sử chi tiêu gần đây để trả lời chính xác, sắc sảo. "amount" và "category" sẽ là null.

ĐỊNH DẠNG TRẢ VỀ: BẮT BUỘC TRẢ VỀ JSON DUY NHẤT:
{
  "action": "add_expense" HOẶC "chat_response",
  "amount": 10000,
  "category": "food",
  "category_name": "Ăn uống",
  "description": "Ăn sáng",
  "reply": "Đã ghi nhận khoản chi Ăn sáng: 10.000 ₫ vào mục Ăn uống cho Hoàng!"
}
''';

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': '$systemInstruction\n\nLịch sử gần đây:\n$recentHistory\n\nHoàng nói: "$prompt"'}
          ]
        }
      ]
    };

    // Primary model requested by user: gemini-3.8-flash, with automatic fallback
    final models = [
      'gemini-3.8-flash',
      'gemini-3.5-flash',
      'gemini-3.5-flash-lite',
      'gemini-2.5-flash',
    ];

    http.Response? res;
    for (final model in models) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );
      try {
        final r = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          res = r;
          break;
        } else {
          debugPrint('Model $model returned status ${r.statusCode}, trying next...');
        }
      } catch (e) {
        debugPrint('Model $model failed with $e, trying next...');
      }
    }

    if (res != null && res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      final rawText = decoded['candidates']?[0]?['content']?[0]?['text'] ??
          decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
          '';

      // Parse JSON from model output
      final jsonStr = _extractJson(rawText);
      if (jsonStr != null) {
        final parsed = jsonDecode(jsonStr);
        final action = parsed['action'];
        final reply = parsed['reply']?.toString() ?? 'Đã xử lý thông tin tài chính của Hoàng!';

        if (action == 'add_expense' && parsed['amount'] != null && (parsed['amount'] as num) > 0) {
          final amt = (parsed['amount'] as num).toInt();
          final cat = parsed['category']?.toString() ?? 'other';
          final catName = parsed['category_name']?.toString() ?? 'Khác';
          final desc = parsed['description']?.toString() ?? 'Chi tiêu';

          return (
            reply: reply,
            expense: ExtractedExpense(
              amount: amt,
              description: desc,
              category: cat,
              categoryName: catName,
              date: DateTime.now(),
            ),
          );
        }
        return (reply: reply.toString(), expense: null as ExtractedExpense?);
      }
      return (reply: rawText.toString(), expense: null as ExtractedExpense?);
    }

    throw 'HTTP status ${res?.statusCode ?? 'no response'}';
  }

  String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return null;
  }

  // Fallback heuristic parser in case device is offline
  ({String reply, ExtractedExpense? expense}) _evaluateLocalEngine(String q, List<Transaction> expenses) {
    final lower = q.toLowerCase();

    // Check for quick amount pattern e.g. "ăn sáng 10k", "cafe 35k", "xăng 50000"
    final moneyMatch = RegExp(r'(\d+[\.,]?\d*)\s*(k|nghìn|ngàn|tr|triệu|đ|vnd)?').firstMatch(lower);

    if (moneyMatch != null && (lower.contains('ăn') || lower.contains('cafe') || lower.contains('mua') || lower.contains('xăng') || lower.contains('hết') || lower.contains('chi'))) {
      double numVal = double.tryParse(moneyMatch.group(1)!.replaceAll(',', '.')) ?? 0;
      final unit = moneyMatch.group(2) ?? '';
      if (unit == 'k' || unit == 'nghìn' || unit == 'ngàn') {
        numVal *= 1000;
      } else if (unit == 'tr' || unit == 'triệu') {
        numVal *= 1000000;
      } else if (numVal < 1000 && numVal > 0) {
        numVal *= 1000; // e.g. "10k" typed as "10"
      }

      int finalAmt = numVal.toInt();
      if (finalAmt > 0) {
        String cat = 'other';
        String catName = 'Khác';
        String desc = 'Chi tiêu';

        if (lower.contains('ăn') || lower.contains('bún') || lower.contains('phở') || lower.contains('cơm')) {
          cat = 'food';
          catName = 'Ăn uống';
          desc = 'Ăn uống';
        } else if (lower.contains('cafe') || lower.contains('cà phê') || lower.contains('trà sữa')) {
          cat = 'coffee';
          catName = 'Cà phê';
          desc = 'Cà phê';
        } else if (lower.contains('xăng') || lower.contains('grab') || lower.contains('xe')) {
          cat = 'transport';
          catName = 'Đi lại';
          desc = 'Đi lại';
        } else if (lower.contains('shopee') || lower.contains('mua')) {
          cat = 'shopping';
          catName = 'Mua sắm';
          desc = 'Mua sắm';
        }

        return (
          reply: '⚡ A.R.I.A đã phân loại và tự động ghi **${Fmt.dong(finalAmt)}** vào mục **$catName** cho Hoàng!',
          expense: ExtractedExpense(
            amount: finalAmt,
            description: desc,
            category: cat,
            categoryName: catName,
            date: DateTime.now(),
          ),
        );
      }
    }

    final totalSpent = expenses.fold<int>(0, (s, t) => s + t.amount);
    return (
      reply: '🤖 Hoàng hiện có **${expenses.length} khoản chi** trong tháng với tổng chi: **${Fmt.dong(totalSpent)}**.\n'
          '💡 Thử nói: *"ăn sáng 15k"* hoặc *"cafe 30k"*, tôi sẽ tự động thêm vào sổ cho bạn ngay!',
      expense: null,
    );
  }
}
