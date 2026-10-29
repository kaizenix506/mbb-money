import 'package:flutter/foundation.dart' hide Category;

import '../../core/formatters.dart';
import '../../data/db/transaction_dao.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../../data/models/tx_range.dart';
import '../../data/repositories/transaction_repository.dart';

/// Mutable screen state for the overview and transaction list.
///
/// Deliberately plain: one instance is provided at the app root and screens
/// read from it. No codegen, no streams — every mutation explicitly calls
/// [notifyListeners] after the database write succeeds.
class TransactionStore extends ChangeNotifier {
  TransactionStore(this._repo);

  final TransactionRepository _repo;

  DateTime _month = Fmt.startOfMonth(DateTime.now());
  bool _loading = true;

  List<Transaction> _monthTransactions = const <Transaction>[];
  List<Transaction> _recent = const <Transaction>[];
  PeriodTotals _totals = PeriodTotals.empty;
  List<CategoryTotal> _byCategory = const <CategoryTotal>[];
  List<({String? id, int total})> _byCategoryId =
      const <({String? id, int total})>[];
  List<({DateTime month, int total})> _trailing =
      const <({DateTime month, int total})>[];
  int _pendingReview = 0;

  // --------------------------------------------------- range list (tab 2)

  /// Window selected on the transactions tab. Independent of [_month] on
  /// purpose: scrolling five years of history must not move the overview.
  TxRange _range = TxRange.days7;
  List<Transaction> _rangeRows = const <Transaction>[];
  PeriodTotals _rangeTotals = PeriodTotals.empty;
  Map<DateTime, int> _rangeDaily = const <DateTime, int>{};
  bool _rangeLoading = false;
  bool _rangeLoadingMore = false;
  bool _rangeHasMore = true;

  // ------------------------------------------------------------------ reads

  DateTime get month => _month;
  bool get isLoading => _loading;
  List<Transaction> get monthTransactions => _monthTransactions;
  List<Transaction> get recent => _recent;
  PeriodTotals get totals => _totals;
  List<CategoryTotal> get byCategory => _byCategory;

  /// Per-category expense totals keyed by the stored id — the shape the
  /// reports tab needs to name categories Hoàng created himself.
  List<({String? id, int total})> get expenseByCategoryId => _byCategoryId;

  List<({DateTime month, int total})> get trailing => _trailing;
  int get pendingReviewCount => _pendingReview;

  bool get canGoForward => !_isCurrentMonth;

  bool get _isCurrentMonth {
    final DateTime now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// Rows grouped by calendar day, in display order (newest first).
  /// The overview and the full list both render from this.
  List<({DateTime day, List<Transaction> items, int dayTotal})> get groupedByDay =>
      _groupByDay(_monthTransactions);

  // --------------------------------------------------------- range getters

  TxRange get range => _range;
  List<Transaction> get rangeRows => _rangeRows;
  PeriodTotals get rangeTotals => _rangeTotals;
  Map<DateTime, int> get rangeDaily => _rangeDaily;
  bool get rangeLoading => _rangeLoading;
  bool get rangeLoadingMore => _rangeLoadingMore;
  bool get rangeHasMore => _rangeHasMore;

  /// Window bounds for the selected range, recomputed on read so a change of
  /// day (app left open overnight) shifts the window without extra state.
  ({DateTime from, DateTime to}) get rangeWindow =>
      _range.windowAt(DateTime.now());

  /// The range rows grouped by day, mirroring [groupedByDay].
  List<({DateTime day, List<Transaction> items, int dayTotal})> get
      rangeGroupedByDay => _groupByDay(_rangeRows);

  /// Days between the oldest row and today, so the UI can say how far back the
  /// loaded data actually reaches versus the requested window.
  int get rangeLoadedDays {
    if (_rangeRows.isEmpty) return 0;
    return DateTime.now().difference(_rangeRows.last.occurredAt).inDays + 1;
  }

  List<({DateTime day, List<Transaction> items, int dayTotal})> _groupByDay(
    List<Transaction> source,
  ) {
    final Map<DateTime, List<Transaction>> buckets = <DateTime, List<Transaction>>{};
    for (final Transaction t in source) {
      final DateTime d =
          DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
      (buckets[d] ??= <Transaction>[]).add(t);
    }
    final List<DateTime> days = buckets.keys.toList()
      ..sort((DateTime a, DateTime b) => b.compareTo(a));
    return days.map((DateTime d) {
      final List<Transaction> items = buckets[d]!;
      final int net = items.fold<int>(
        0,
        (int sum, Transaction t) => sum + t.signedAmount,
      );
      return (day: d, items: items, dayTotal: net);
    }).toList(growable: false);
  }

  /// Spending pace — how much is left to spend per remaining day this month,
  /// used by the hero sub-line. Null when the month has ended or there is no
  /// income to budget against.
  int? get dailyBudgetLeft {
    final DateTime now = DateTime.now();
    if (!_isCurrentMonth || _totals.income <= 0) return null;
    final int daysLeft = Fmt.daysInMonth(now) - now.day + 1;
    if (daysLeft <= 0) return null;
    final int remaining = _totals.income - _totals.expense;
    if (remaining <= 0) return 0;
    return remaining ~/ daysLeft;
  }

  // ----------------------------------------------------------------- writes

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    await _refreshData();
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _refreshData();
    notifyListeners();
  }

  Future<void> _refreshData() async {
    final results = await Future.wait<Object>(<Future<Object>>[
      _repo.inMonth(_month),
      _repo.recent(limit: 6),
      _repo.totalsFor(_month),
      _repo.categoryBreakdown(_month),
      _repo.categoryBreakdownById(_month),
      _repo.trailingExpenses(DateTime.now()),
      _repo.pendingReviewCount(),
    ]);
    _monthTransactions = results[0] as List<Transaction>;
    _recent = results[1] as List<Transaction>;
    _totals = results[2] as PeriodTotals;
    _byCategory = results[3] as List<CategoryTotal>;
    _byCategoryId = results[4] as List<({String? id, int total})>;
    final List<({DateTime month, int total})> series =
        results[5] as List<({DateTime month, int total})>;
    _trailing = series;
    _pendingReview = results[6] as int;

    // Range rows are loaded separately: they resolve to void, and bundling a
    // void future into the typed batch above is what the analyser rejects.
    await _loadRangeFirstPage();
  }

  Future<void> goToMonth(DateTime target) async {
    _month = Fmt.startOfMonth(target);
    await load();
  }

  Future<void> previousMonth() => goToMonth(Fmt.previousMonth(_month));

  // ------------------------------------------------------------ range list

  /// Incremented on every range change so a slow response for the previous
  /// range cannot overwrite the rows of the new one.
  int _rangeGeneration = 0;

  /// Switches the transactions tab to [next] and loads its first page.
  Future<void> setRange(TxRange next) async {
    if (next == _range && _rangeRows.isNotEmpty) return;
    _range = next;
    _rangeLoading = true;
    _rangeLoadingMore = false;
    _rangeHasMore = true;
    _rangeRows = const <Transaction>[];
    _rangeDaily = const <DateTime, int>{};
    notifyListeners();

    await _loadRangeFirstPage();
    _rangeLoading = false;
    notifyListeners();
  }

  /// Loads the next older page. Safe to call repeatedly; it self-guards.
  Future<void> loadMoreRange() async {
    if (_rangeLoadingMore || !_rangeHasMore || _rangeRows.isEmpty) return;
    _rangeLoadingMore = true;
    notifyListeners();

    final int generation = _rangeGeneration;
    final ({DateTime from, DateTime to}) w = rangeWindow;
    final Transaction last = _rangeRows.last;

    try {
      final List<Transaction> page = await _repo.pageInRange(
        from: w.from,
        to: w.to,
        limit: 60,
        before: (
          occurredAtMs: last.occurredAt.millisecondsSinceEpoch,
          id: last.id,
        ),
      );
      if (generation != _rangeGeneration) return;
      _rangeRows = <Transaction>[..._rangeRows, ...page];
      _rangeHasMore = page.length == 60;
    } on Object {
      if (generation == _rangeGeneration) _rangeHasMore = false;
    } finally {
      if (generation == _rangeGeneration) {
        _rangeLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// First page + totals + daily series for the current range.
  Future<void> _loadRangeFirstPage() async {
    _rangeLoading = true;
    final int generation = ++_rangeGeneration;
    final ({DateTime from, DateTime to}) w = rangeWindow;

    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _repo.pageInRange(from: w.from, to: w.to, limit: 60),
        _repo.totalsInRange(from: w.from, to: w.to),
        _repo.dailyExpenses(from: w.from, to: w.to),
      ]);
      if (generation != _rangeGeneration) return;

      final List<Transaction> page = results[0] as List<Transaction>;
      _rangeRows = page;
      _rangeTotals = results[1] as PeriodTotals;
      _rangeDaily = results[2] as Map<DateTime, int>;
      _rangeHasMore = page.length == 60;
    } finally {
      if (generation == _rangeGeneration) {
        _rangeLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> nextMonth() async {
    if (!canGoForward) return;
    await goToMonth(DateTime(_month.year, _month.month + 1));
  }

  Future<Transaction> addManual({
    required TxType type,
    required int amount,
    required DateTime occurredAt,
    required String description,
    String? categoryId,
    String? accountId,
  }) async {
    final Transaction tx = await _repo.addManual(
      type: type,
      amount: amount,
      occurredAt: occurredAt,
      description: description,
      categoryId: categoryId,
      accountId: accountId,
    );
    await refresh();
    await _notifyPersisted(tx);
    return tx;
  }

  /// Called with the id of a row written outside the sync path (manual entry or
  /// the AI chat), so the notification watermark can be advanced past it.
  Future<void> Function(int id)? onRowPersisted;

  Future<void> setCategory(Transaction tx, Category? category) async {
    await _repo.updateCategory(tx, category);
    await _notifyPersisted(tx);
    await refresh();
  }

  /// Reassigns a category id without going through the legacy [Category] enum.
  /// Used when a user moves a transaction into one of their own categories.
  Future<void> setCategoryId(Transaction tx, String? categoryId) async {
    await _repo.updateCategoryId(tx, categoryId);
    await _notifyPersisted(tx);
    await refresh();
  }

  /// Updates all mutable fields of an existing transaction (amount, description,
  /// occurredAt, categoryId) and refreshes state.
  Future<void> updateTransaction(Transaction tx) async {
    await _repo.update(tx);
    await refresh();
  }

  /// Moves every transaction pointing at [fromCategoryId] to the fallback
  /// bucket. Called before deleting a category so no expense is orphaned.
  Future<int> migrateCategoryTransactions(
    String fromCategoryId,
    String toCategoryId,
  ) async {
    final int moved = await _repo.reassignCategory(fromCategoryId, toCategoryId);
    await refresh();
    return moved;
  }

  Future<void> delete(Transaction tx) async {
    await _repo.delete(tx);
    await refresh();
  }

  /// Twelve monthly totals for a whole calendar year.
  Future<List<({DateTime month, int total})>> expensesForYear(int year) {
    return _repo.yearlyExpenses(year);
  }

  /// Called after a Shortcut deep link or a SePay sync so the UI catches up.
  Future<void> afterExternalIngest() => refresh();

  /// Best-effort hand-off to the notification watcher. A failure here must never
  /// break a write the user already made, so it is swallowed.
  Future<void> _notifyPersisted(Transaction tx) async {
    final int id = tx.id;
    try {
      await onRowPersisted?.call(id);
    } on Object catch (e) {
      debugPrint('onRowPersisted hook failed: $e');
    }
  }
}
