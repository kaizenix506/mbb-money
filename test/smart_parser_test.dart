import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/services/smart_parser.dart';

/// The parser is the hot path for every one-liner Hoàng types, and it runs
/// before any network call, so these cases are the app's real "AI accuracy"
/// contract.
void main() {
  group('SmartParser amount extraction', () {
    test('uống nước 20k → 20000 in Đồ uống', () {
      final e = SmartParser.parse('uống nước 20k');
      expect(e, isNotNull);
      expect(e!.amount, 20000);
      expect(e.category, 'drink');
      expect(e.categoryName, 'Đồ uống');
    });

    test('ăn sáng hết 10k → 10000 in Ăn uống', () {
      final e = SmartParser.parse('ăn sáng hết 10k');
      expect(e, isNotNull);
      expect(e!.amount, 10000);
      expect(e.category, 'food');
    });

    test('trà sữa 35 nghìn → 35000 in Đồ uống', () {
      final e = SmartParser.parse('trà sữa 35 nghìn');
      expect(e?.amount, 35000);
      expect(e?.category, 'drink');
    });

    test('cafe 1,5tr → 1500000 in Cà phê', () {
      final e = SmartParser.parse('cafe 1,5tr');
      expect(e?.amount, 1500000);
      expect(e?.category, 'coffee');
    });

    test('đổ xăng 50k → Đi lại', () {
      expect(SmartParser.parse('đổ xăng 50k')?.category, 'transport');
    });

    test('grab 45k → Đi lại', () {
      expect(SmartParser.parse('grab 45k')?.category, 'transport');
    });

    test('mua sách 120k → Giáo dục', () {
      expect(SmartParser.parse('mua sách 120k')?.category, 'education');
    });

    test('cắt tóc 50k → Sức khỏe', () {
      final e = SmartParser.parse('cắt tóc 50k');
      expect(e?.amount, 50000);
      expect(e?.category, 'health');
    });

    test('mua áo 200k → Mua sắm', () {
      final e = SmartParser.parse('mua áo 200k');
      expect(e?.amount, 200000);
      expect(e?.category, 'shopping');
    });

    test('tiền điện 500k → Hóa đơn', () {
      final e = SmartParser.parse('tiền điện 500k');
      expect(e?.amount, 500000);
      expect(e?.category, 'bills');
    });

    test('uống bia 100k → Đồ uống', () {
      final e = SmartParser.parse('uống bia 100k');
      expect(e?.amount, 100000);
      expect(e?.category, 'drink');
    });

    test('bare number under 1000 is read as nghìn', () {
      expect(SmartParser.parse('ăn trưa 20')?.amount, 20000);
    });

    test('"hai chục" is read as 20000', () {
      expect(SmartParser.parse('ăn sáng hai chục')?.amount, 20000);
    });
  });

  group('SmartParser refuses questions', () {
    for (final String q in <String>[
      'tháng này chi bao nhiêu?',
      'so với tháng trước thế nào',
      'gợi ý cách tiết kiệm',
      'phân tích chi tiêu giúp tôi',
    ]) {
      test('"$q" is not an expense', () {
        expect(SmartParser.parse(q), isNull);
      });
    }

    test('a bare number with no words is not an expense', () {
      expect(SmartParser.parse('20000'), isNull);
    });
  });

  group('SmartParser dates', () {
    test('hôm qua shifts the date back one day', () {
      final e = SmartParser.parse('cafe 30k hôm qua');
      expect(e, isNotNull);
      final DateTime today = DateTime.now();
      final DateTime expected = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 1));
      expect(e!.date!.day, expected.day);
    });

    test('explicit d/m date is honoured', () {
      final e = SmartParser.parse('ăn tối 80k 15/3');
      expect(e?.date?.month, 3);
      expect(e?.date?.day, 15);
    });
  });

  group('SmartParser description', () {
    test('strips the amount and filler words', () {
      final e = SmartParser.parse('ăn sáng hết 10k');
      expect(e!.description.toLowerCase(), 'ăn sáng');
    });

    test('falls back when nothing is left', () {
      final e = SmartParser.parse('hết 50k');
      expect(e, isNotNull);
      expect(e!.description, isNotEmpty);
    });
  });
}
