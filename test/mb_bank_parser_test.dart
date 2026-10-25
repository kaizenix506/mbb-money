import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/mb_bank_parser.dart';

/// These tests encode real MB Bank message shapes. If a bank changes its
/// template, a test here fails before the user's books quietly go wrong.
void main() {
  group('looksLikeMbNotice', () {
    test('accepts a standard balance-change SMS', () {
      const String sms =
          'MB: TK 0681****888 PSGD: +500,000VND lúc 24/10/2026 14:30:15. '
          'SD: 2,450,000VND. Nguyen Van A chuyen tien mua hang';
      expect(MbBankParser.looksLikeMbNotice(sms), isTrue);
    });

    test('rejects an OTP message', () {
      const String otp =
          'MB Bank: Ma xac thuc cua ban la 123456. Khong chia se ma nay.';
      expect(MbBankParser.looksLikeMbNotice(otp), isFalse);
    });

    test('rejects marketing copy', () {
      const String promo =
          'MBBank uu dai hoan tien 10% khi thanh toan online. Xem chi tiet.';
      expect(MbBankParser.looksLikeMbNotice(promo), isFalse);
    });
  });

  group('amount and direction', () {
    test('parses an inflow with a plus sign', () {
      final MbParseResult r = MbBankParser.parse(
        'MB: TK 0681****888 PSGD: +500,000VND lúc 24/10/2026 14:30:15. '
        'SD: 2,450,000VND. Nguyen Van A chuyen tien mua hang',
      );
      expect(r.isIncome, isTrue);
      expect(r.amount, 500000);
      expect(r.occurredAt, DateTime(2026, 10, 24, 14, 30, 15));
    });

    test('parses an outflow with a minus sign', () {
      final MbParseResult r = MbBankParser.parse(
        'MB: TK 0701****697 PSGD: -200,000VND lúc 25/10/2026 09:12:00. '
        'SD: 2,250,000VND. THANH TOAN TIEU DUNG',
      );
      expect(r.isIncome, isFalse);
      expect(r.amount, 200000);
    });

    test('handles dot thousands separators', () {
      final MbParseResult r = MbBankParser.parse(
        'MB: TK 001 PSGD: -1.250.000 đ lúc 01/11/2026 08:00. SD: 9.000.000đ',
      );
      expect(r.amount, 1250000);
      expect(r.isIncome, isFalse);
    });

    test('handles spaces inside the number', () {
      final MbParseResult r = MbBankParser.parse(
        'MB TK 001 PSGD: +28 500 000 VND lúc 01/11/2026 08:00 SD: 0 VND',
      );
      expect(r.amount, 28500000);
      expect(r.isIncome, isTrue);
    });

    test('falls back to direction words when the sign is missing', () {
      final MbParseResult r = MbBankParser.parse(
        'MBBank 15/10/2026 14:32 GD: 150,000 VND - TK: 098xxxx123 '
        'SD: 2,450,000 VND. ND: ghi no thanh toan',
      );
      expect(r.amount, 150000);
      expect(r.isIncome, isFalse);
    });

    test('throws when there is no amount', () {
      expect(
        () => MbBankParser.parse('MB Bank thong bao bao tri he thong'),
        throwsA(isA<MbParseException>()),
      );
    });
  });

  group('confidence', () {
    test('high confidence for an unambiguous message', () {
      final MbParseResult r = MbBankParser.parse(
        'MB: TK 001 PSGD: -58,000VND lúc 24/10/2026 14:30:00. '
        'SD: 1,000,000VND. HIGHLANDS COFFEE',
      );
      expect(r.confidence, greaterThanOrEqualTo(MbBankParser.reviewThreshold));
    });

    test('low confidence when the direction is unknown', () {
      final MbParseResult r = MbBankParser.parse(
        'MB TK 001 PSGD: 58,000VND lúc 24/10/2026 14:30:00 SD: 1,000,000VND',
      );
      expect(r.confidence, lessThan(MbBankParser.reviewThreshold));
    });
  });

  group('content', () {
    test('extracts ND: content and title-cases shouting', () {
      final MbParseResult r = MbBankParser.parse(
        'MB: TK 0701****697 PSGD: -75,000VND lúc 25/10/2026 12:04:00. '
        'SD: 2,175,000VND. ND: HIGHLANDS COFFEE Q1',
      );
      expect(r.description.toLowerCase(), contains('highlands'));
      expect(r.description, isNot(r.description.toUpperCase()));
    });

    test('falls back to text after the running balance', () {
      final MbParseResult r = MbBankParser.parse(
        'MB: TK 001 PSGD: -20,000VND lúc 25/10/2026 12:04:00. '
        'SD: 100,000VND. GrabBike chuyen di',
      );
      expect(r.description.toLowerCase(), contains('grab'));
    });

    test('uses a neutral label when nothing is parseable', () {
      final MbParseResult r = MbBankParser.parse(
        'MB: TK 001 PSGD: -20,000VND lúc 25/10/2026 12:04:00. SD: 100,000VND',
      );
      expect(r.description, isNotEmpty);
    });
  });

  group('dates', () {
    test('parses time-first format', () {
      final MbParseResult r = MbBankParser.parse(
        'MB TK 001 PSGD: -20,000VND lúc 12:04 ngày 25/10/2026 SD: 100,000VND',
      );
      expect(r.occurredAt, DateTime(2026, 10, 25, 12, 4));
    });

    test('uses the fallback time when the message has no date', () {
      final DateTime fallback = DateTime(2026, 3, 1, 9);
      final MbParseResult r = MbBankParser.parse(
        'MB PSGD: -20,000VND SD: 100,000VND',
        fallbackTime: fallback,
      );
      expect(r.occurredAt, fallback);
    });

    test('handles two-digit years', () {
      final MbParseResult r = MbBankParser.parse(
        'MB TK 001 PSGD: -20,000VND lúc 25/10/26 12:04 SD: 100,000VND',
      );
      expect(r.occurredAt.year, 2026);
    });
  });

  test('reference numbers are captured when present', () {
    final MbParseResult r = MbBankParser.parse(
      'MB TK 001 PSGD: -20,000VND lúc 25/10/2026 12:04 SD: 100,000VND '
      'FT26123456789012',
    );
    expect(r.referenceNumber, 'FT26123456789012');
  });
}
