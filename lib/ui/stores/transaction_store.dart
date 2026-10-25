import 'package:flutter/foundation.dart' hide Category;

import '../../core/formatters.dart';
import '../../data/db/transaction_dao.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
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
  List<({DateTime month, int total})> _trailing =
      const <({DateTime month, int total})>[];
  int _pendingReview = 0;

  // ------------------------------------------------------------------ reads

  DateTime get month => _month;
  bool get isLoading => _loading;
  List<Transaction> get monthTransactions => _monthTransactions;
  List<Transaction> get recent => _recent;
  PeriodTotals get totals => _totals;
  List<CategoryTotal> get byCategory => _byCategory;
  List<({DateTime month, int total})> get trailing => _trailing;
  int get pendingReviewCount => _pendingReview;

  bool get canGoForward => !_isCurrentMonth;

  bool get _isCurrentMonth {
    final DateTime now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// Rows grouped by calendar day, in display order (newest first).
  /// The overview and the full list both render from this.
  List<({DateTime day, List<Transaction> items, int dayTotal})> get groupedByDay {
    final Map<DateTime, List<Transaction>> buckets = <DateTime, List<Transaction>>{};
    for (final Transaction t in _monthTransactions) {
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
      _repo.trailingExpenses(DateTime.now()),
      _repo.pendingReviewCount(),
    ]);
    _monthTransactions = results[0] as List<Transaction>;
    _recent = results[1] as List<Transaction>;
    _totals = results[2] as PeriodTotals;
    _byCategory = results[3] as List<CategoryTotal>;
    final List<({DateTime month, int total})> series =
        await _repo.trailingExpenses(DateTime.now());
    _trailing = series;
    _pendingReview = results[5] as int;
  }

  Future<void> goToMonth(DateTime target) async {
    _month = Fmt.startOfMonth(target);
    await load();
  }

  Future<void> previousMonth() => goToMonth(Fmt.previousMonth(_month));

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
    return tx;
  }

  Future<void> setCategory(Transaction tx, Category? category) async {
    await _repo.updateCategory(tx, category);
    await refresh();
  }

  /// Reassigns a category id without going through the legacy [Category] enum.
  /// Used when a user moves a transaction into one of their own categories.
  Future<void> setCategoryId(Transaction tx, String? categoryId) async {
    await _repo.updateCategoryId(tx, categoryId);
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

  /// Called after a Shortcut deep link or a SePay sync so the UI catches up.
  Future<void> afterExternalIngest() => refresh();
}
