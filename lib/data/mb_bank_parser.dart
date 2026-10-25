import 'models/transaction.dart';

/// Thrown when a text cannot be recognised as an MB Bank transaction notice.
///
/// Callers should treat this as "not a bank message" (e.g. an OTP or a
/// marketing SMS) rather than an error worth surfacing to the user.
class MbParseException implements Exception {
  const MbParseException(this.reason, {this.input});

  final String reason;
  final String? input;

  @override
  String toString() => 'MbParseException($reason)';
}

/// Result of successfully parsing one MB Bank notice.
class MbParseResult {
  const MbParseResult({
    required this.isIncome,
    required this.amount,
    required this.occurredAt,
    required this.description,
    required this.confidence,
    this.counterparty,
    this.referenceNumber,
  });

  /// Whether the money came in or went out.
  final bool isIncome;

  final int amount;
  final DateTime occurredAt;

  /// Human-readable merchant / content ("Highlands Coffee", "TRAN THI B …").
  final String description;

  /// Who the counterparty is, when the message separates it out.
  final String? counterparty;

  /// Bank reference, when present. Used as the sync de-dupe key.
  final String? referenceNumber;

  /// 0–1. Below [MbBankParser.reviewThreshold] the row is flagged for review
  /// so a wrong guess never silently corrupts the books.
  final double confidence;

  /// Convenience for building a [Transaction] without importing the enum at
  /// every call site.
  TxType get type => isIncome ? TxType.income : TxType.expense;
}

/// Parses MB Bank balance-change SMS and push notifications into structured
/// transactions.
///
/// ## Why this is pattern-based rather than one fixed template
/// MB Bank has used several templates over the years, and users receive both
/// branded SMS and app push notifications. Rather than betting on one exact
/// string, the parser anchors on the three things every template contains:
///
///  1. a **signed amount** followed by `VND`/`đ` — e.g. `+500,000VND`
///  2. a **direction** cue — `+`/`-` on the amount, or the words
///     `GHI CO` / `GHI NO` / `tien vao` / `tien ra`
///  3. optionally a **timestamp** `dd/MM/yyyy HH:mm(:ss)` and a
///     **content** marker (`ND:`, `Nội dung:`, or free text after the balance)
///
/// If (1) or (2) is ambiguous the parse still succeeds but is returned with a
/// low confidence score so the UI asks the user to confirm.
abstract final class MbBankParser {
  /// Parses below this score get `pending_review = 1`.
  static const double reviewThreshold = 0.85;

  /// `+500,000VND`, `-1.250.000 đ`, `+ 5.000.000 VNĐ`
  /// Group 1 = sign, Group 2 = magnitude with separators.
  static final RegExp _signedAmount = RegExp(
    r'([+\-−])\s*(\d{1,3}(?:[.,\s]\d{3})*|\d+)\s*(?:VND|VNĐ|VN d|đ|d\b)',
    caseSensitive: false,
  );

  /// Amounts without a leading sign are only trusted when a direction word is
  /// nearby, which [_extractSign] checks.
  static final RegExp _bareAmount = RegExp(
    r'(?:GD|GTGD|Số tiền|So tien)\s*:?\s*(\d{1,3}(?:[.,\s]\d{3})*|\d+)\s*(?:VND|VNĐ|đ)?',
    caseSensitive: false,
  );

  /// Direction words used when the amount itself carries no sign.
  static final RegExp _incomeWords = RegExp(
    r'\b(ghi\s*c[oó]|tien\s*vao|ti\u1ec1n\s*v\u00e0o|nh\u1eadn|credit|\+)\b',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _expenseWords = RegExp(
    r'\b(ghi\s*n[oợ]|tien\s*ra|ti\u1ec1n\s*ra|thanh\s*to\u00e1n|debit)\b',
    caseSensitive: false,
    unicode: true,
  );

  /// `15/10/2026 14:32:10`, `24-10-2026 09:05`
  static final RegExp _dateTime = RegExp(
    r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})(?:\s+|,\s*|T)'
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?',
  );

  /// `lúc 14:32 24/10` (date after time, as in "lúc HH:mm dd/MM/yyyy")
  static final RegExp _timeThenDate = RegExp(
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s+(?:ng[aà]y\s+)?'
    r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})',
    caseSensitive: false,
  );

  /// `ND: ...` / `Nội dung: ...` / `Noi dung: ...`
  static final RegExp _contentMarker = RegExp(
    r'(?:\bND\b|\bNoi\s*dung\b|N\u1ed9i\s*dung)\s*:\s*(.+)$',
    caseSensitive: false,
    unicode: true,
    dotAll: true,
  );

  /// `FT26123456789012` — MB sometimes appends a reference number.
  static final RegExp _reference = RegExp(
    r'\b(FT\d{8,}|REF\s*:?\s*([A-Z0-9]{8,})|M\u00e3\s*GD\s*:?\s*([A-Z0-9]{6,}))',
    caseSensitive: false,
  );

  /// True when [text] looks like an MB balance-change notice at all. Used to
  /// ignore OTPs and marketing SMS that reach the same Shortcut automation.
  static bool looksLikeMbNotice(String text) {
    final bool mentionsBank =
        RegExp(r'\bMB\b|\bMBBank\b|MB\s*Bank', caseSensitive: false).hasMatch(text);
    final bool mentionsBalance =
        RegExp(r'\bSD\b|\bS\u1ed1 d\u01b0\b|\bSo du\b', caseSensitive: false)
            .hasMatch(text);
    final bool mentionsTxn = RegExp(
      r'\bPSGD\b|\bGD\b|\bGTGD\b|giao d\u1ecbch',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
    return mentionsBank && (mentionsBalance || mentionsTxn);
  }

  /// Parses [text]. Throws [MbParseException] when the message clearly is not
  /// a transaction (no amount / no direction).
  static MbParseResult parse(String text, {DateTime? fallbackTime}) {
    final String clean =
        text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) {
      throw const MbParseException('empty input', input: '');
    }

    double confidence = 1.0;

    // ---- amount + direction ---------------------------------------------
    int? magnitude;
    bool? isIncome;

    final RegExpMatch? signed = _signedAmount.firstMatch(clean);
    if (signed != null) {
      isIncome = signed.group(1) == '+';
      magnitude = _digits(signed.group(2));
    } else {
      final RegExpMatch? bare = _bareAmount.firstMatch(clean);
      if (bare != null) {
        magnitude = _digits(bare.group(1));
        // No sign — decide from words, and trust it less.
        confidence -= 0.2;
      }
    }

    if (magnitude == null || magnitude <= 0) {
      throw MbParseException('no amount found', input: clean);
    }

    isIncome ??= _guessDirection(clean);
    if (isIncome == null) {
      // We have money but no idea which way it moved. Default to expense
      // (the common case) and make the user confirm.
      isIncome = false;
      confidence -= 0.35;
    }

    // ---- timestamp -------------------------------------------------------
    DateTime occurredAt;
    final RegExpMatch? dm = _dateTime.firstMatch(clean);
    final RegExpMatch? tdm = dm == null ? _timeThenDate.firstMatch(clean) : null;
    if (dm != null) {
      occurredAt = _buildDateTime(
        day: dm.group(1),
        month: dm.group(2),
        year: dm.group(3),
        hour: dm.group(4),
        minute: dm.group(5),
        second: dm.group(6),
      );
    } else if (tdm != null) {
      occurredAt = _buildDateTime(
        day: tdm.group(4),
        month: tdm.group(5),
        year: tdm.group(6),
        hour: tdm.group(1),
        minute: tdm.group(2),
        second: tdm.group(3),
      );
    } else {
      // No date in the SMS (very common on push notifications).
      occurredAt = fallbackTime ?? DateTime.now();
      confidence -= 0.1;
    }

    // ---- content + counterparty -----------------------------------------
    String? content = _contentMarker.firstMatch(clean)?.group(1)?.trim();
    content ??= _trailingContent(clean);

    final String description = _cleanContent(content).ifEmpty(
      isIncome ? 'Tiền vào' : 'Chi tiêu',
    );

    // ---- reference -------------------------------------------------------
    String? reference;
    final RegExpMatch? refMatch = _reference.firstMatch(clean);
    if (refMatch != null) {
      reference = refMatch.group(1) ??
          (refMatch.group(2) == null ? null : 'REF${refMatch.group(2)}') ??
          (refMatch.group(3) == null ? null : 'GD${refMatch.group(3)}');
    }

    return MbParseResult(
      isIncome: isIncome,
      amount: magnitude,
      occurredAt: occurredAt,
      description: description,
      counterparty: _guessCounterparty(description),
      referenceNumber: reference,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  // ------------------------------------------------------------- internals

  /// "1.250.000" / "1,250,000" / "1 250 000" → 1250000.
  static int? _digits(String? raw) {
    if (raw == null) return null;
    final String stripped = raw.replaceAll(RegExp(r'[.,\s]'), '');
    return int.tryParse(stripped);
  }

  static bool? _guessDirection(String text) {
    final bool inc = _incomeWords.hasMatch(text);
    final bool exp = _expenseWords.hasMatch(text);
    if (inc == exp) return null; // both or neither: ambiguous
    return inc;
  }

  static DateTime _buildDateTime({
    String? day,
    String? month,
    String? year,
    String? hour,
    String? minute,
    String? second,
  }) {
    final DateTime now = DateTime.now();
    int y = int.tryParse(year ?? '') ?? now.year;
    if (y < 100) y += 2000;
    return DateTime(
      y,
      int.tryParse(month ?? '') ?? now.month,
      int.tryParse(day ?? '') ?? now.day,
      int.tryParse(hour ?? '') ?? 0,
      int.tryParse(minute ?? '') ?? 0,
      int.tryParse(second ?? '') ?? 0,
    );
  }

  /// Content often lives after the running balance: `... SD: 2,450,000VND. <content>`.
  static String? _trailingContent(String text) {
    final RegExp sd = RegExp(
      r'(?:SD|S\u1ed1 d\u01b0|So du)\s*:?\s*[\d.,]+\s*(?:VND|VNĐ|đ)?[.,;\s]*(.*)$',
      caseSensitive: false,
      unicode: true,
    );
    return sd.firstMatch(text)?.group(1)?.trim();
  }

  /// Bank content strings are SHOUTING C++ and full of filler. Normalise to
  /// something that reads like a merchant name.
  static String _cleanContent(String? raw) {
    if (raw == null) return '';
    String s = raw
        .replaceAll(RegExp(r'^[\s.,;:\-]+'), '')
        .replaceAll(RegExp(r'[\s.,;\-]+$'), '');
    // Drop common MB admin phrases that carry no meaning for the user.
    s = s.replaceAll(
      RegExp(
        r'\b(MB\s*Bank|MBBank|TK|GD|PSGD|GTGD|SD|VND|VN\s*\u0111|N\u1ed9i dung|ND)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return '';
    // "TRAN THI B CHUYEN TIEN" → "Tran Thi B Chuyen Tien".
    // Only letters are re-cased; digits and symbols are left untouched so a
    // merchant token like "GRABBIKE123" can never lose characters.
    if (s == s.toUpperCase() && s.length > 3) {
      s = s.toLowerCase();
      final StringBuffer rebuilt = StringBuffer();
      bool atWordStart = true;
      for (final int rune in s.runes) {
        final String ch = String.fromCharCode(rune);
        if (ch.trim().isEmpty) {
          atWordStart = true;
          rebuilt.write(ch);
          continue;
        }
        final bool isLetter = RegExp(r'\p{L}', unicode: true).hasMatch(ch);
        rebuilt.write(atWordStart && isLetter ? ch.toUpperCase() : ch);
        atWordStart = false;
      }
      s = rebuilt.toString();
    }
    return s.length > 90 ? '${s.substring(0, 89)}\u2026' : s;
  }

  /// Best-effort counterparty: the leading run of capitalised words.
  static String? _guessCounterparty(String description) {
    final RegExpMatch? m = RegExp(r'^([\p{L}][\p{L}\s]{1,40}?)(?:\s+chuyen|\s+ck\b|$)',
            unicode: true)
        .firstMatch(description);
    final String? candidate = m?.group(1)?.trim();
    if (candidate == null || candidate.length < 3) return null;
    if (candidate.split(' ').length > 5) return null;
    return candidate;
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
