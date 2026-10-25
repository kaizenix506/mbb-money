import 'models/category.dart';

/// Maps a merchant string to a category using keyword rules.
///
/// Deliberately simple and transparent: a keyword table beats a model for
/// Vietnamese merchants, is free, works offline, and users can reason about
/// why a row landed where it did. Anything that matches nothing comes back as
/// `null` so the row is flagged for review rather than dumped into "Khác".
abstract final class AutoCategorizer {
  /// Ordered — the first hit wins. Longer, more specific phrases come first so
  /// `GRABFOOD` is not swallowed by the generic `GRAB` transport rule.
  static const List<(Category, List<String>)> _rules = <(Category, List<String>)>[
    // ---- income -----------------------------------------------------------
    (
      Category.salary,
      <String>[
        'luong',
        'l\u01b0\u01a1ng',
        'salary',
        'tien luong',
        'thuong',
        'th\u01b0\u1edfng',
        'bonus',
      ],
    ),
    // ---- food & drink -----------------------------------------------------
    (
      Category.coffee,
      <String>[
        'highlands',
        'starbucks',
        'phuc long',
        'ph\u00fac long',
        'the coffee house',
        'coffee',
        'cafe',
        'c\u00e0 ph\u00ea',
        'katinat',
        'milano',
        'trung nguyen',
        'trung nguy\u00ean',
        'passio',
        'cheese coffee',
        'kokon',
        'tea',
        'tra sua',
        'tr\u00e0 s\u1eefa',
        'gong cha',
        'tocotoco',
        'mixue',
        'circle k',
        'familymart',
        'gs25',
      ],
    ),
    (
      Category.food,
      <String>[
        'grab food',
        'grabfood',
        'shopeefood',
        'shopeefood',
        'now food',
        'befood',
        'baemin',
        'lozi',
        'gojek food',
        'an sang',
        '\u0103n s\u00e1ng',
        'an trua',
        '\u0103n tr\u01b0a',
        'an toi',
        '\u0103n t\u1ed1i',
        'com',
        'c\u01a1m',
        'pho',
        'ph\u1edf',
        'bun',
        'b\u00fan',
        'mi',
        'm\u00ec',
        'banh mi',
        'b\u00e1nh m\u00ec',
        'quan an',
        'qu\u00e1n \u0103n',
        'nha hang',
        'nh\u00e0 h\u00e0ng',
        'buffet',
        'pizza',
        'kfc',
        'lotteria',
        'mcdonald',
        'burger king',
        'jollibee',
        'pizza hut',
        'domino',
        'sushi',
        'lotte mart food',
        'goi y',
      ],
    ),
    // ---- transport --------------------------------------------------------
    (
      Category.transport,
      <String>[
        'grab',
        'be group',
        'be bike',
        'xanh sm',
        'xanhsm',
        'vinfast',
        'gojek',
        'uber',
        'taxi',
        'mai linh',
        'vinasun',
        'grab bike',
        'grabcar',
        'grab car',
        'xang',
        'x\u0103ng',
        'petrolimex',
        'pvoil',
        'shell',
        'bus',
        'xe bus',
        've tau',
        'v\u00e9 t\u00e0u',
        've may bay',
        'vietnam airlines',
        'vietjet',
        'bamboo airway',
        'giao hang',
        'ghn',
        'ghtk',
        'viettel post',
        'vnpost',
        'j&t',
        'spx',
        'ninjavan',
      ],
    ),
    // ---- shopping ---------------------------------------------------------
    (
      Category.shopping,
      <String>[
        'shopee',
        'lazada',
        'tiki',
        'sendo',
        'tiktok shop',
        'hasaki',
        'guardian',
        'watsons',
        'thegioididong',
        'the gioi di dong',
        'fpt shop',
        'cellphones',
        'dien may xanh',
        '\u0111i\u1ec7n m\u00e1y xanh',
        'bach hoa xanh',
        'b\u00e1ch ho\u00e1 xanh',
        'winmart',
        'vinmart',
        'coopmart',
        'go!',
        'big c',
        'lotte mart',
        'mega market',
        'aeon',
        'uniqlo',
        'zara',
        'hm',
        'decathlon',
        'shop',
        'mua sam',
        'mua s\u1eafm',
      ],
    ),
    // ---- bills ------------------------------------------------------------
    (
      Category.bills,
      <String>[
        'evn',
        'dien luc',
        '\u0111i\u1ec7n l\u1ef1c',
        'tien dien',
        'ti\u1ec1n \u0111i\u1ec7n',
        'nuoc',
        'n\u01b0\u1edbc',
        'cap nuoc',
        'viettel',
        'vnpt',
        'mobifone',
        'vinaphone',
        'fpt telecom',
        'internet',
        'wifi',
        'truyen hinh',
        'truy\u1ec1n h\u00ecnh',
        'netflix',
        'spotify',
        'youtube premium',
        'icloud',
        'google one',
        'microsoft 365',
        'office 365',
        'hoc phi',
        'h\u1ecdc ph\u00ed',
        'bao hiem',
        'b\u1ea3o hi\u1ec3m',
        'phi',
        'ph\u00ed',
      ],
    ),
    // ---- health -----------------------------------------------------------
    (
      Category.health,
      <String>[
        'nha thuoc',
        'nh\u00e0 thu\u1ed1c',
        'pharmacy',
        'long chau',
        'long ch\u00e2u',
        'pharmacity',
        'benh vien',
        'b\u1ec7nh vi\u1ec7n',
        'phong kham',
        'ph\u00f2ng kh\u00e1m',
        'hospital',
        'clinic',
        'gym',
        'fitness',
        'yoga',
        'california',
        'vinmec',
        'tam anh',
        't\u00e2m anh',
      ],
    ),
    // ---- entertainment ----------------------------------------------------
    (
      Category.entertainment,
      <String>[
        'cgv',
        'galaxy cinema',
        'lotte cinema',
        'cinestar',
        'beta cinema',
        'rap phim',
        'r\u1ea1p phim',
        'steam',
        'playstation',
        'nintendo',
        'bar',
        'pub',
        'karaoke',
        'bida',
        'bowling',
        'game',
      ],
    ),
    // ---- education --------------------------------------------------------
    (
      Category.education,
      <String>[
        'nha sach',
        'nh\u00e0 s\u00e1ch',
        'fahasa',
        'phuong nam book',
        'udemy',
        'coursera',
        'skillshare',
        'duolingo',
        'bytedance edu',
        'trung tam',
        'trung t\u00e2m',
        'ielts',
        'toeic',
        'khoa hoc',
        'kh\u00f3a h\u1ecdc',
      ],
    ),
    // ---- transfers --------------------------------------------------------
    (
      Category.transfer,
      <String>[
        'chuyen tien',
        'chuy\u1ec3n ti\u1ec1n',
        'chuyen khoan',
        'chuy\u1ec3n kho\u1ea3n',
        'transfer',
        'ck ',
        'nap tien',
        'n\u1ea1p ti\u1ec1n',
        'rut tien',
        'r\u00fat ti\u1ec1n',
        'atm',
        'tiet kiem',
        'ti\u1ebft ki\u1ec7m',
      ],
    ),
  ];

  /// Returns the category for [text], or `null` when nothing matches.
  ///
  /// [isIncome] narrows the salary rule so an outgoing transfer described as
  /// "LUONG" is not mis-read as a salary credit.
  static Category? categorize(String text, {required bool isIncome}) {
    final String haystack = _normalise(text);
    if (haystack.isEmpty) return null;

    for (final (Category category, List<String> keywords) in _rules) {
      if (category == Category.salary && !isIncome) continue;
      for (final String keyword in keywords) {
        if (haystack.contains(_normalise(keyword))) {
          // "shop" alone would swallow "shopee" as education via 'nha sach'
          // etc.; the ordered rules already handle specificity, so accept.
          return category;
        }
      }
    }
    return null;
  }

  /// Same as [categorize] but falls back to [Category.other] — use when the UI
  /// must show *something*.
  static Category categorizeOrOther(String text, {required bool isIncome}) {
    return categorize(text, isIncome: isIncome) ?? Category.other;
  }

  static String _normalise(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
