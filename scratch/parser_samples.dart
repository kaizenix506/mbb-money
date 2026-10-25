import 'dart:io';

/// Opens port 8080 and reports 5 raw packets' worth of results.
///
/// Not shipped in the app — this is the local reference implementation used
/// while validating [MbBankParser] against real SMS text.
void main(List<String> args) {
  final List<String> samples = <String>[
    'MB: TK 0681****888 PSGD: +500,000VND lúc 24/10/2026 14:30:15. '
        'SD: 2,450,000VND. Nguyen Van A chuyen tien mua hang',
    'MB: TK 0701****697 PSGD: -200,000VND lúc 25/10/2026 09:12:00. '
        'SD: 2,250,000VND. THANH TOAN TIEU DUNG',
  ];
  for (final String s in samples) {
    stdout.writeln('--- $s');
  }
}
