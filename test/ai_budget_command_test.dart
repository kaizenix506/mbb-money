import 'package:flutter_test/flutter_test.dart';
import 'package:mbb_money/data/services/smart_parser.dart';

/// Guards the "AI can change the app" contract Hoàng asked for.
///
/// Before this, asking A.R.I.A to change the shopping budget produced a friendly
/// chat reply and nothing else — there was no command channel at all. The local
/// detector below is what makes the phrase work instantly, offline and with no
/// Gemini key, so it is the piece most worth pinning down.
void main() {
  group('SmartParser.parseBudgetCommandWith', () {
    test('absolute phrasing sets the budget to the stated amount', () {
      expect(
        SmartParser.parseBudgetCommandWith(0, 'đổi ngân sách thành 5 triệu'),
        5000000,
      );
      expect(
        SmartParser.parseBudgetCommandWith(0, 'dat ngan sach 5tr'),
        5000000,
      );
      expect(
        SmartParser.parseBudgetCommandWith(123, 'ngân sách mua sắm là 8 triệu'),
        8000000,
      );
      expect(
        SmartParser.parseBudgetCommandWith(0, 'đặt ngân sách 2,5 triệu'),
        2500000,
      );
      expect(
        SmartParser.parseBudgetCommandWith(0, 'ngân sách 5000000'),
        5000000,
      );
      expect(
        SmartParser.parseBudgetCommandWith(0, 'budget 10 triệu'),
        10000000,
      );
    });

    test('relative phrasing adds to / subtracts from the current budget', () {
      expect(
        SmartParser.parseBudgetCommandWith(5000000, 'tăng ngân sách thêm 2 triệu'),
        7000000,
      );
      expect(
        SmartParser.parseBudgetCommandWith(5000000, 'giảm ngân sách bớt 1tr'),
        4000000,
      );
      expect(
        SmartParser.parseBudgetCommandWith(3000000, 'them ngan sach 1 trieu'),
        4000000,
      );
    });

    test('a relative command with a negative result clamps at zero', () {
      expect(
        SmartParser.parseBudgetCommandWith(1000000, 'giảm ngân sách bớt 5 triệu'),
        0,
      );
    });

    test('a relative command without a known current budget is not guessed', () {
      expect(
        SmartParser.parseBudgetCommandWith(null, 'tăng ngân sách thêm 2 triệu'),
        isNull,
      );
    });

    test('questions about the budget are not commands', () {
      expect(SmartParser.parseBudgetCommandWith(0, 'ngân sách còn bao nhiêu'), isNull);
      expect(SmartParser.parseBudgetCommandWith(0, 'ngân sách thế nào rồi'), isNull);
      expect(SmartParser.parseBudgetCommandWith(0, 'còn lại bao nhiêu ngân sách'), isNull);
    });

    test('ordinary spending sentences are not budget commands', () {
      expect(SmartParser.parseBudgetCommandWith(0, 'uống nước 20k'), isNull);
      expect(SmartParser.parseBudgetCommandWith(0, 'ăn sáng 10k'), isNull);
      expect(SmartParser.parseBudgetCommandWith(0, 'cafe 35k'), isNull);
      expect(SmartParser.parseBudgetCommandWith(0, 'grab 45k'), isNull);
    });

    test('a budget sentence without a number is ignored', () {
      expect(SmartParser.parseBudgetCommandWith(0, 'đổi ngân sách đi'), isNull);
    });
  });

  group('normal expense parsing still works', () {
    test('a plain spend is still parsed as an expense', () {
      final e = SmartParser.parse('uống nước 20k', allowFallback: true);
      expect(e, isNotNull);
      expect(e!.amount, 20000);
      expect(e.category, 'drink');
    });
  });
}
