import '../../core/vn_clock.dart';
import 'cyber_ai_service.dart';

/// Deterministic Vietnamese expense parser that runs **before** any network
/// call, so the common one-liners Hoàng types are filed instantly:
///
/// ```
/// uống nước 20k        → Đồ uống · 20.000
/// ăn sáng hết 10k      → Ăn uống · 10.000
/// grab 45k hôm qua     → Đi lại · 45.000 · (date -1)
/// trà sữa 35 nghìn     → Đồ uống · 35.000
/// đổ xăng 50 k         → Đi lại · 50.000
/// ```
///
/// It deliberately returns `null` when it is not confident (e.g. a question:
/// "tháng này chi bao nhiêu?") so the caller can fall back to Gemini.
abstract final class SmartParser {
  /// Words that mean "this is a question, not a spend".
  static final RegExp _question = RegExp(
    r'(bao nhiêu|bao nhieu|\?|tại sao|tai sao|làm sao|lam sao|gợi ý|goi y|'
    r'so với|so voi|thống kê|thong ke|báo cáo|bao cao|phân tích|phan tich|'
    r'nên|nen |có nên|co nen|thế nào|the nao)',
    caseSensitive: false,
  );

  /// Category keyword table. First match wins, so the most specific rows are
  /// first (trà sữa is a drink, not a "sữa" grocery).
  static final List<(String, List<String>)> _rules = <(String, List<String>)>[
    (
      'coffee',
      <String>[
        'cà phê',
        'ca phe',
        'cafe',
        'coffee',
        'bạc xỉu',
        'bac xiu',
        'highlands',
        'starbucks',
        'phúc long',
        'phuc long',
        'katinat',
        'cộng cà phê',
        'trung nguyên',
        'espresso',
        'latte',
        'cappuccino',
      ],
    ),
    (
      'drink',
      <String>[
        'uống nước',
        'uong nuoc',
        'uống',
        'uong',
        'nước',
        'nuoc',
        'trà sữa',
        'tra sua',
        'trà đào',
        'tra dao',
        'trà',
        'tra',
        'sinh tố',
        'sinh to',
        'nước mía',
        'nuoc mia',
        'nước cam',
        'nuoc cam',
        'nước ngọt',
        'nuoc ngot',
        'nước suối',
        'nuoc suoi',
        'bia',
        'uống bia',
        'tiger',
        'heineken',
        'coca',
        'pepsi',
        'sting',
        'revive',
        'redbull',
        'trà chanh',
        'tra chanh',
        'sữa tươi',
        'sua tuoi',
        'bò húc',
        'bo huc',
      ],
    ),
    (
      'food',
      <String>[
        'ăn sáng',
        'ăn trưa',
        'ăn tối',
        'ăn vặt',
        'đồ ăn',
        'do an',
        'ăn',
        'an sang',
        'an trua',
        'an toi',
        'an vat',
        'cơm',
        'com',
        'cơm tấm',
        'cơm sườn',
        'phở',
        'pho',
        'bún',
        'bun',
        'bún bò',
        'bun bo',
        'mì',
        'bánh mì',
        'banh mi',
        'bánh',
        'banh',
        'cháo',
        'chao',
        'hủ tiếu',
        'hu tieu',
        'gà rán',
        'ga ran',
        'kfc',
        'lotteria',
        'mcdonald',
        'pizza',
        'sushi',
        'lẩu',
        'lau',
        'nướng',
        'nuong',
        'snack',
        'trái cây',
        'trai cay',
        'xôi',
        'xoi',
        'chè',
        'che',
      ],
    ),
    (
      'transport',
      <String>[
        'grab',
        'gojek',
        'be',
        'taxi',
        'xe ôm',
        'xe om',
        'xăng',
        'xang',
        'đổ xăng',
        'do xang',
        'gửi xe',
        'gui xe',
        'sửa xe',
        'sua xe',
        'rửa xe',
        'rua xe',
        'vá xe',
        'va xe',
        'thay nhớt',
        'thay nhot',
        'xe buýt',
        'xe buyt',
        'bus',
        'vé xe',
        've xe',
        'phí đường',
        'cầu đường',
        'cau duong',
      ],
    ),
    (
      'bills',
      <String>[
        'tiền điện',
        'tien dien',
        'tiền nước',
        'tiền nhà',
        'tien nha',
        'tiền trọ',
        'tien tro',
        'tiền phòng',
        'tiền mạng',
        'tien mang',
        'internet',
        'wifi',
        'nạp thẻ',
        'nap the',
        'nạp tiền',
        'nap tien',
        'hóa đơn',
        'hoa don',
        'đóng tiền',
        'dong tien',
        'phí dịch vụ',
        'phi dich vu',
        'trả góp',
        'tra gop',
      ],
    ),
    (
      'education',
      <String>[
        'sách',
        'sach',
        'học phí',
        'hoc phi',
        'khóa học',
        'khoa hoc',
        'vở',
        'học thêm',
        'hoc them',
        'gia sư',
        'gia su',
        'chứng chỉ',
        'chung chi',
      ],
    ),
    (
      'shopping',
      <String>[
        'shopee',
        'tiki',
        'lazada',
        'tiktok shop',
        'mua đồ',
        'mua do',
        'quần áo',
        'quan ao',
        'mua',
        'sắm',
        'sam',
        'quần',
        'áo',
        'giày',
        'dép',
        'đồng hồ',
        'dong ho',
        'mỹ phẩm',
        'my pham',
        'kem',
        'túi',
        'điện thoại',
        'dien thoai',
        'tai nghe',
        'ốp lưng',
        'op lung',
      ],
    ),
    (
      'health',
      <String>[
        'cắt tóc',
        'cat toc',
        'gội đầu',
        'goi dau',
        'thuốc',
        'thuoc',
        'tiệm thuốc',
        'tiem thuoc',
        'khám',
        'kham',
        'bệnh viện',
        'benh vien',
        'nha khoa',
        'phòng gym',
        'gym',
        'spa',
        'vitamin',
        'y tế',
        'ye te',
        'xét nghiệm',
        'xet nghiem',
      ],
    ),
    (
      'entertainment',
      <String>[
        'phim',
        'cinema',
        'cgv',
        'lotte cinema',
        'galaxy',
        'game',
        'netflix',
        'spotify',
        'youtube',
        'du lịch',
        'du lich',
        'khách sạn',
        'khach san',
        'vé máy bay',
        've may bay',
        'karaoke',
        'bar',
        'club',
        'coi phim',
        'xem phim',
        'vé xem',
        've xem',
      ],
    ),
    (
      'education',
      <String>[
        'sách',
        'sach',
        'học phí',
        'hoc phi',
        'khóa học',
        'khoa hoc',
        'vở',
        'vo ',
        'bút',
        'but ',
        'học thêm',
        'hoc them',
        'gia sư',
        'gia su',
        'thi',
        'chứng chỉ',
        'chung chi',
      ],
    ),
    (
      'family',
      <String>[
        'biếu',
        'bieu ',
        'cho mẹ',
        'cho me',
        'cho bố',
        'cho bo',
        'gia đình',
        'gia dinh',
        'con ',
        'vợ',
        'vo ',
        'chồng',
        'chong',
      ],
    ),
  ];

  /// Units and how many đồng they mean.
  static const Map<String, int> _units = <String, int>{
    'k': 1000,
    'n': 1000,
    'nghìn': 1000,
    'ngàn': 1000,
    'ng': 1000,
    'nghin': 1000,
    'ngan': 1000,
    'tr': 1000000,
    'triệu': 1000000,
    'trieu': 1000000,
    'm': 1000000,
    'tỷ': 1000000000,
    'ty': 1000000000,
    'đ': 1,
    'vnd': 1,
    'vnđ': 1,
    'd': 1,
  };

  /// Vietnamese number words, for "hai chục", "một trăm".
  static const Map<String, int> _words = <String, int>{
    'không': 0,
    'mot': 1,
    'một': 1,
    'hai': 2,
    'ba': 3,
    'bốn': 4,
    'bon': 4,
    'tư': 4,
    'tu': 4,
    'năm': 5,
    'nam': 5,
    'lăm': 5,
    'sáu': 6,
    'sau': 6,
    'bảy': 7,
    'bay': 7,
    'tám': 8,
    'tam': 8,
    'chín': 9,
    'chin': 9,
    'mười': 10,
    'muoi': 10,
    'chục': 10,
    'chuc': 10,
    'trăm': 100,
    'tram': 100,
  };

  // ------------------------------------------------------------------ parse

  /// Returns an [ExtractedExpense] when the sentence is definitely a spend,
  /// `null` when it should be handed to the model instead.
  static ExtractedExpense? parse(
    String input, {
    List<String> knownCategories = const <String>[],
    bool allowFallback = true,
  }) {
    final String raw = input.trim();
    if (raw.length < 3) return null;
    if (_question.hasMatch(raw)) return null;

    final int? amount = _amount(raw);
    if (amount == null || amount <= 0) return null;

    // Needs at least one letter, otherwise "20000" alone is ambiguous.
    if (!RegExp(r'[a-zA-Zà-ỹÀ-Ỹ]').hasMatch(raw)) return null;

    final String norm = _norm(raw);
    final String catId = _category(norm, knownCategories);
    if (catId == 'other' && !allowFallback) {
      return null;
    }
    final DateTime when = _date(norm);
    final String desc = _description(raw, amount);

    return ExtractedExpense(
      amount: amount,
      description: desc,
      category: catId,
      categoryName: CategoryCatalog.labelOf(catId),
      date: when,
      confidence: catId == 'other' ? 0.55 : 0.95,
    );
  }

  // -------------------------------------------------------- budget command

  /// Words that mean "change the shopping budget", not "record an expense".
  static final RegExp _budgetCue = RegExp(
    r'(ngân sách|ngan sach|ngân quỹ|ngan quy|budget)',
    caseSensitive: false,
  );

  /// "5 triệu" / "5tr" / "5000000" / "5 000 000" → 5000000.
  static final RegExp _budgetNumber = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(nghìn|ngàn|nghin|ngan|triệu|trieu|tr|k|vnđ|vnd|đ|d)?',
    caseSensitive: false,
  );

  /// Detects "đổi ngân sách thành 5 triệu", "đặt ngân sách 5tr",
  /// "tăng ngân sách thêm 2 triệu", "giảm ngân sách bớt 1tr".
  ///
  /// Returns the **absolute** new budget when [currentBudget] is supplied and
  /// the sentence is relative ("tăng/giảm thêm"); returns the delta otherwise.
  /// The caller decides, which is why the sign is encoded in [BudgetCommand].
  static BudgetCommand? parseBudgetCommandText(String input) {
    final String raw = input.trim();
    if (raw.length < 3) return null;
    if (!_budgetCue.hasMatch(raw)) return null;

    final String lower = raw.toLowerCase();

    // "còn lại bao nhiêu" is a QUESTION about the budget, not a new one.
    if (RegExp(r'(bao nhiêu|bao nhieu|\?|thế nào|the nao|còn lại|con lai)')
        .hasMatch(lower)) {
      return null;
    }

    final int? value = _budgetAmount(lower);
    if (value == null || value <= 0) return null;

    final bool isIncrease =
        RegExp(r'(tăng|tang|thêm|them|cộng|them vao)').hasMatch(lower);
    final bool isDecrease =
        RegExp(r'(giảm|giam|bớt|bot|trừ|tru)').hasMatch(lower);

    return BudgetCommand(
      amount: value,
      isRelative: isIncrease || isDecrease,
      isIncrease: isIncrease && !isDecrease,
    );
  }

  /// Backwards-friendly helper: the absolute new budget, or `null`.
  ///
  /// Relative phrasing ("tăng thêm 2 triệu") is resolved against
  /// [currentBudget]; without it a relative command cannot be resolved and
  /// `null` is returned so the model gets a chance instead.
  static int? parseBudgetCommandWith(int? currentBudget, String input) {
    final BudgetCommand? cmd = parseBudgetCommandText(input);
    if (cmd == null) return null;
    if (!cmd.isRelative) return cmd.amount;
    if (currentBudget == null) return null;
    final int next =
        cmd.isIncrease ? currentBudget + cmd.amount : currentBudget - cmd.amount;
    return next < 0 ? 0 : next;
  }

  static int? _budgetAmount(String lower) {
    // Prefer the number that directly follows a unit/amount word.
    for (final RegExpMatch m in _budgetNumber.allMatches(lower)) {
      final String numberText = m.group(1)!.replaceAll(',', '.');
      final double base = double.tryParse(numberText) ?? 0;
      final String? unit = m.group(2)?.toLowerCase();
      int mult = 1;
      if (unit != null) mult = _units[unit] ?? 1000;
      double value = base * mult;
      if (unit == null && value > 0 && value < 1000) value *= 1000;
      if (value >= 1000) return value.round();
    }
    return null;
  }

  // --------------------------------------------------------------- amount

  static int? _amount(String s) {
    final String lower = s.toLowerCase();

    // Digit form: 20k, 1,5tr, 35.000đ, 50000
    final RegExpMatch? m = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(nghìn|ngàn|nghin|ngan|triệu|trieu|tr|k|n|m|'
      r'vnđ|vnd|đ|d)?',
      caseSensitive: false,
    ).allMatches(lower).cast<RegExpMatch?>().firstWhere(
          (RegExpMatch? e) => e != null,
          orElse: () => null,
        );

    if (m != null) {
      final String numberText = m.group(1)!.replaceAll(',', '.');
      final double base = double.tryParse(numberText) ?? 0;
      final String? unit = m.group(2)?.toLowerCase();
      int mult = 1;
      if (unit != null) mult = _units[unit] ?? 1;

      double value = base * mult;
      // "20" with no unit and under 1000 → assume nghìn (Vietnamese habit).
      if (unit == null && value > 0 && value < 1000) value *= 1000;
      if (value >= 100) {
        return value.round();
      }
    }

    // Word form: "hai chục", "một trăm"
    final RegExpMatch? w = RegExp(
      r'([a-zA-Zà-ỹ]+)\s*(chục|chuc|trăm|tram|nghìn|ngàn|triệu|tr)?',
      caseSensitive: false,
    ).allMatches(lower).cast<RegExpMatch?>().firstWhere(
          (RegExpMatch? e) => e != null && _words.containsKey(e.group(1)!.toLowerCase()),
          orElse: () => null,
        );

    if (w != null) {
      final int base = _words[w.group(1)!.toLowerCase()] ?? 0;
      final String? unit = w.group(2)?.toLowerCase();
      int mult = 1000;
      if (unit != null) {
        if (unit == 'triệu' || unit == 'tr') {
          mult = 1000000;
        } else if (unit == 'chục' || unit == 'chuc') {
          mult = 10000;
        } else if (unit == 'trăm' || unit == 'tram') {
          mult = 100000;
        } else {
          mult = 1000;
        }
      }
      final int value = base * mult;
      if (value >= 1000) return value;
    }

    return null;
  }

  // ------------------------------------------------------------- category

  static String _category(String norm, List<String> known) {
    for (final (String id, List<String> words) in _rules) {
      for (final String w in words) {
        if (_containsWord(norm, _norm(w))) return id;
      }
    }
    // A custom category the user created wins if named explicitly.
    for (final String id in known) {
      if (id.isNotEmpty && _containsWord(norm, _norm(id))) return id;
    }
    return 'other';
  }

  /// Word-aware containment.
  ///
  /// A plain `contains` is wrong for short Vietnamese tokens: the keyword «ă»
  /// (eat) would match «xăng» (petrol). So a keyword shorter than four
  /// characters must start a word, while longer phrases may match anywhere
  /// («ănsáng» still hits «ăn sáng» after normalisation).
  static bool _containsWord(String haystack, String needle) {
    if (needle.isEmpty) return false;
    if (needle.length >= 4) return haystack.contains(needle);
    for (int i = 0; i < haystack.length; i++) {
      if (haystack.startsWith(needle, i) &&
          (i == 0 || haystack[i - 1] == ' ')) {
        return true;
      }
    }
    return false;
  }

  // ----------------------------------------------------------------- date

  static DateTime _date(String norm) {
    final DateTime now = VnClock.now();
    // VnClock.now() carries VN wall-clock fields but is flagged UTC, so build a
    // local-agnostic DateTime for storage.
    final DateTime base = DateTime(now.year, now.month, now.day, now.hour, now.minute);

    if (norm.contains('hôm qua') || norm.contains('hom qua')) {
      return base.subtract(const Duration(days: 1));
    }
    if (norm.contains('hôm kia') || norm.contains('hom kia')) {
      return base.subtract(const Duration(days: 2));
    }
    if (norm.contains('hôm nay') || norm.contains('hom nay')) {
      return base;
    }
    final RegExpMatch? d = RegExp(r'(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?')
        .firstMatch(norm);
    if (d != null) {
      final int day = int.parse(d.group(1)!);
      final int month = int.parse(d.group(2)!);
      int year = now.year;
      if (d.group(3) != null) {
        year = int.parse(d.group(3)!);
        if (year < 100) year += 2000;
      }
      if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
        final DateTime parsed = DateTime(year, month, day, now.hour, now.minute);
        if (!parsed.isAfter(base)) return parsed;
      }
    }
    return base;
  }

  // --------------------------------------------------------- description

  /// Strips the amount and filler words, then title-cases what is left so the
  /// ledger reads "Uống nước" instead of "uống nước 20k".
  static String _description(String raw, int amount) {
    String s = raw
        .replaceAll(
          RegExp(
            r'\d+(?:[.,]\d+)?\s*(nghìn|ngàn|nghin|ngan|triệu|trieu|tr|k|n|m|'
            r'vnđ|vnd|đ|d)?',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(hết|het|mất|mat|hết tiền|vừa|vua|mới|moi|đã|da|chi|trả|tra|'
            r'cho|hôm nay|hom nay|hôm qua|hom qua|hôm kia|hom kia|tôi|toi|'
            r'mình|minh|tui|tớ|to)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    s = s.replaceAll(RegExp(r'^[\s,.\-–+]+|[\s,.\-–+]+$'), '');
    if (s.isEmpty) return 'Chi tiêu';

    final List<String> words = s.split(' ');
    final List<String> capped = <String>[
      for (int i = 0; i < words.length; i++)
        if (words[i].isNotEmpty)
          i == 0
              ? '${words[i][0].toUpperCase()}${words[i].substring(1)}'
              : words[i],
    ];
    final String out = capped.join(' ');
    return out.length > 48 ? '${out.substring(0, 48)}…' : out;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// A parsed budget-change instruction.
///
/// Kept separate from [ExtractedExpense] because it is a *state change on the
/// app*, not a ledger row: the chat sheet applies it to the wishlist store.
class BudgetCommand {
  const BudgetCommand({
    required this.amount,
    required this.isRelative,
    required this.isIncrease,
  });

  /// Absolute target when [isRelative] is false, otherwise the delta.
  final int amount;

  /// True for "tăng thêm 2 triệu" / "giảm bớt 1tr".
  final bool isRelative;

  /// Only meaningful when [isRelative] is true.
  final bool isIncrease;

  @override
  String toString() => 'BudgetCommand(amount: $amount, relative: $isRelative, '
      'increase: $isIncrease)';
}
