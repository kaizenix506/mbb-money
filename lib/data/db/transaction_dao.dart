import 'package:sqflite/sqflite.dart' hide Transaction;

import '../models/category.dart';
import '../models/transaction.dart';
import 'database.dart';

/// Aggregated totals for one period, used by the hero card and the reports tab.
class PeriodTotals {
  const PeriodTotals({
    this.income = 0,
    this.expense = 0,
    this.count = 0,
  });

  final int income;
  final int expense;
  final int count;

  int get net => income - expense;

  /// Share of income that has been spent, 0–1. Returns 0 when there is no
  /// income yet so the ring stays empty instead of dividing by zero.
  double get expenseRatio {
    if (income <= 0) return 0;
    return (expense / income).clamp(0.0, 1.0);
  }

  static const PeriodTotals empty = PeriodTotals();
}

/// Totals for a single category, used by the reports bar list.
class CategoryTotal {
  const CategoryTotal({required this.category, required this.total});

  final Category category;
  final int total;
}

/// All SQL touching `transactions` lives here.
///
/// Repository and sync service depend on this class, not on sqflite directly,
/// which keeps the storage engine swappable and unit-testable.
class TransactionDao {
  TransactionDao({Database? db, String directory = ''})
      : _override = db,
        _directory = directory;

  final Database? _override;

  /// Empty on iOS/Android (sqflite resolves the location), an absolute folder
  /// on desktop (FFI needs it explicitly).
  final String _directory;

  Future<Database> get _db async =>
      _override ?? AppDatabase.instance.databaseIn(_directory);

  // ---------------------------------------------------------------- writes

  Future<int> insert(Transaction tx) async {
    final Database db = await _db;
    return db.insert('transactions', tx.toMap());
  }

  /// Inserts many rows in one transaction, skipping any whose
  /// `reference_number` already exists. Returns how many were actually added.
  ///
  /// [ConflictAlgorithm.ignore] plus the partial unique index makes this
  /// idempotent, so re-running a SePay sync is always safe.
  Future<int> insertAllIfNew(List<Transaction> txs) async {
    if (txs.isEmpty) return 0;
    final Database db = await _db;
    return db.transaction<int>((txn) async {
      int added = 0;
      for (final Transaction tx in txs) {
        final int id = await txn.insert(
          'transactions',
          tx.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id != 0) added++;
      }
      return added;
    });
  }

  Future<void> update(Transaction tx) async {
    final Database db = await _db;
    await db.update(
      'transactions',
      tx.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[tx.id],
    );
  }

  Future<void> updateCategory(int id, String? categoryId) async {
    final Database db = await _db;
    await db.update(
      'transactions',
      <String, Object?>{
        'category_id': categoryId,
        'pending_review': 0,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Moves every row of [fromCategoryId] to [toCategoryId] in one statement.
  /// Returns the number of rows updated so the caller can report it.
  Future<int> reassignCategory(String fromCategoryId, String toCategoryId) async {
    final Database db = await _db;
    return db.update(
      'transactions',
      <String, Object?>{'category_id': toCategoryId},
      where: 'category_id = ?',
      whereArgs: <Object?>[fromCategoryId],
    );
  }

  Future<void> delete(int id) async {
    final Database db = await _db;
    await db.delete('transactions', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // ----------------------------------------------------------------- reads

  Future<List<Transaction>> inRange({
    required DateTime from,
    required DateTime to,
    int limit = 500,
  }) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'transactions',
      where: 'occurred_at >= ? AND occurred_at < ?',
      whereArgs: <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(Transaction.fromMap).toList(growable: false);
  }

  /// One page of rows inside `[from, to)`, newest first.
  ///
  /// Keyset pagination rather than OFFSET: [before] is the cursor from the
  /// previous page, so a SePay sync that inserts rows mid-scroll cannot cause
  /// duplicates or skips. The tuple comparison mirrors the ORDER BY exactly.
  Future<List<Transaction>> pageInRange({
    required DateTime from,
    required DateTime to,
    int limit = 60,
    ({int occurredAtMs, int id})? before,
  }) async {
    final Database db = await _db;
    final List<String> where = <String>['occurred_at >= ?', 'occurred_at < ?'];
    final List<Object?> args = <Object?>[
      from.millisecondsSinceEpoch,
      to.millisecondsSinceEpoch,
    ];

    if (before != null) {
      where.add('(occurred_at < ? OR (occurred_at = ? AND id < ?))');
      args.addAll(<Object?>[before.occurredAtMs, before.occurredAtMs, before.id]);
    }

    final List<Map<String, Object?>> rows = await db.query(
      'transactions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(Transaction.fromMap).toList(growable: false);
  }

  /// Income/expense/count totals for `[from, to)` — the same shape as
  /// [totals], but named for the range picker so call sites read clearly.
  Future<PeriodTotals> totalsInRange({
    required DateTime from,
    required DateTime to,
  }) =>
      totals(from: from, to: to);

  /// Expense per day for `[from, to)`, keyed by the local calendar day.
  ///
  /// Used by the transactions tab to show a sparkline for the selected window.
  /// Days with no spending are absent from the result; the caller fills gaps.
  Future<Map<DateTime, int>> dailyExpenses({
    required DateTime from,
    required DateTime to,
  }) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT strftime('%Y-%m-%d', occurred_at / 1000, 'unixepoch', 'localtime') AS d,
             SUM(amount) AS total
      FROM transactions
      WHERE type = 'expense' AND occurred_at >= ? AND occurred_at < ?
      GROUP BY d
      ''',
      <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );

    final Map<DateTime, int> out = <DateTime, int>{};
    for (final Map<String, Object?> r in rows) {
      final String? key = r['d'] as String?;
      final List<String>? parts = key?.split('-');
      if (parts == null || parts.length != 3) continue;
      final DateTime day = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      out[day] = (r['total'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  Future<List<Transaction>> recent({int limit = 5}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'transactions',
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(Transaction.fromMap).toList(growable: false);
  }

  Future<Transaction?> byId(int id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Transaction.fromMap(rows.first);
  }

  /// Income, expense and row count for `[from, to)`.
  Future<PeriodTotals> totals({required DateTime from, required DateTime to}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income'  THEN amount END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expense,
        COUNT(*) AS cnt
      FROM transactions
      WHERE occurred_at >= ? AND occurred_at < ?
      ''',
      <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    final Map<String, Object?> row = rows.first;
    return PeriodTotals(
      income: (row['income'] as num?)?.toInt() ?? 0,
      expense: (row['expense'] as num?)?.toInt() ?? 0,
      count: (row['cnt'] as num?)?.toInt() ?? 0,
    );
  }

  /// Expense totals grouped by the raw `category_id`, biggest first.
  ///
  /// Unlike [expenseByCategory] this does not try to map ids onto the built-in
  /// enum, which is what lets the reports tab show categories Hoàng created
  /// himself. Rows with no category come back with a `null` id.
  Future<List<({String? id, int total})>> expenseByCategoryId({
    required DateTime from,
    required DateTime to,
  }) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT category_id, SUM(amount) AS total
      FROM transactions
      WHERE type = 'expense' AND occurred_at >= ? AND occurred_at < ?
      GROUP BY category_id
      ORDER BY total DESC
      ''',
      <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );

    return <({String? id, int total})>[
      for (final Map<String, Object?> r in rows)
        (id: r['category_id'] as String?, total: (r['total'] as num?)?.toInt() ?? 0),
    ];
  }

  /// Expense totals grouped by category, biggest first. Uncategorised rows
  /// fall into [Category.other] so the list always sums to the period expense.
  Future<List<CategoryTotal>> expenseByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT category_id, SUM(amount) AS total
      FROM transactions
      WHERE type = 'expense' AND occurred_at >= ? AND occurred_at < ?
      GROUP BY category_id
      ORDER BY total DESC
      ''',
      <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );

    return rows.map((Map<String, Object?> r) {
      final Category cat =
          Category.byId(r['category_id'] as String?) ?? Category.other;
      return CategoryTotal(
        category: cat,
        total: (r['total'] as num?)?.toInt() ?? 0,
      );
    }).toList(growable: false);
  }

  /// Expense total per month for the trailing [months] months, oldest first.
  /// Missing months are returned as zero so the bar chart keeps a steady
  /// rhythm instead of collapsing gaps.
  Future<List<({DateTime month, int total})>> monthlyExpenses({
    required DateTime now,
    int months = 6,
  }) async {
    final Database db = await _db;
    final DateTime firstMonth = DateTime(now.year, now.month - (months - 1));
    final DateTime end = DateTime(now.year, now.month + 1);

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT strftime('%Y-%m', occurred_at / 1000, 'unixepoch', 'localtime') AS ym,
             SUM(amount) AS total
      FROM transactions
      WHERE type = 'expense' AND occurred_at >= ? AND occurred_at < ?
      GROUP BY ym
      ''',
      <Object?>[firstMonth.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );

    final Map<String, int> byKey = <String, int>{
      for (final Map<String, Object?> r in rows)
        (r['ym'] as String? ?? ''): (r['total'] as num?)?.toInt() ?? 0,
    };

    return List<({DateTime month, int total})>.generate(months, (int i) {
      final DateTime m = DateTime(firstMonth.year, firstMonth.month + i);
      final String key = '${m.year.toString().padLeft(4, '0')}-'
          '${m.month.toString().padLeft(2, '0')}';
      return (month: m, total: byKey[key] ?? 0);
    });
  }

  /// Expense total for every month of [year], January first.
  /// Powers the annual report so a past year does not need 12 separate calls.
  Future<List<({DateTime month, int total})>> yearlyExpenses(int year) async {
    final Database db = await _db;
    final DateTime from = DateTime(year, 1, 1);
    final DateTime to = DateTime(year + 1, 1, 1);

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT strftime('%m', occurred_at / 1000, 'unixepoch', 'localtime') AS m,
             SUM(amount) AS total
      FROM transactions
      WHERE type = 'expense' AND occurred_at >= ? AND occurred_at < ?
      GROUP BY m
      ''',
      <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );

    final Map<int, int> byMonth = <int, int>{
      for (final Map<String, Object?> r in rows)
        int.tryParse(r['m'] as String? ?? '') ?? 0:
            (r['total'] as num?)?.toInt() ?? 0,
    };

    return List<({DateTime month, int total})>.generate(
      12,
      (int i) => (month: DateTime(year, i + 1), total: byMonth[i + 1] ?? 0),
    );
  }

  Future<int> countPendingReview() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM transactions WHERE pending_review = 1',
    );
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------- new-row notification

  /// Highest row id currently stored, `0` when the ledger is empty.
  ///
  /// Ids are AUTOINCREMENT, so "id > watermark" is an exact test for "arrived
  /// after we last looked" — no timestamp comparisons and no clock skew.
  Future<int> maxId() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(MAX(id), 0) AS mx FROM transactions',
    );
    return (rows.first['mx'] as num?)?.toInt() ?? 0;
  }

  /// Rows with id > after, newest first. Powers the new-transaction push.
  Future<List<Transaction>> rowsAbove(int after, {int limit = 20}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'transactions',
      where: 'id > ?',
      whereArgs: <Object?>[after],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(Transaction.fromMap).toList(growable: false);
  }

  /// Finds an existing row for a bank reference, so a webhook pushed for a
  /// transaction the SePay poller already stored is not announced twice.
  Future<Transaction?> byReference(String reference) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'transactions',
      where: 'reference_number = ?',
      whereArgs: <Object?>[reference],
      limit: 1,
    );
    return rows.isEmpty ? null : Transaction.fromMap(rows.first);
  }

  // --------------------------------------------------- internal state (kv)

  Future<String?> readInternal(String key) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'internal_state',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeInternal(String key, String? value) async {
    final Database db = await _db;
    if (value == null) {
      await db.delete('internal_state', where: 'key = ?', whereArgs: <Object?>[key]);
      return;
    }
    await db.insert(
      'internal_state',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Distinct descriptions for a category — powers quick-add suggestions.
  Future<List<String>> recentDescriptions({int limit = 8}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT description, MAX(occurred_at) AS last_seen
      FROM transactions
      WHERE description <> ''
      GROUP BY description
      ORDER BY last_seen DESC
      LIMIT ?
      ''',
      <Object?>[limit],
    );
    return rows
        .map((Map<String, Object?> r) => r['description'] as String? ?? '')
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> clearAll() async {
    final Database db = await _db;
    await db.delete('transactions');
  }
}
