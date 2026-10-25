import 'package:flutter/foundation.dart' hide Category;

import '../auto_categorizer.dart';
import '../db/transaction_dao.dart';
import '../mb_bank_parser.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../models/tx_source.dart';
import '../../core/formatters.dart';

/// Outcome of a shortcut/SMS ingestion, so the UI knows what to say.
enum IngestStatus {
  /// Row was created and is ready to show.
  added,

  /// The same bank event was already in the database.
  duplicate,

  /// The text is not a transaction (OTP, marketing…).
  ignored,

  /// Parsed, but with low confidence — stored for review.
  needsReview,

  /// Unrecoverable parse failure.
  failed,
}

class IngestResult {
  const IngestResult(this.status, {this.transaction, this.message});

  final IngestStatus status;
  final Transaction? transaction;
  final String? message;

  bool get ok => status == IngestStatus.added || status == IngestStatus.needsReview;
}

/// The single write-path for transactions, no matter where they came from.
///
/// Both the iOS Shortcut deep link and manual entry funnel through here so the
/// parsing, categorisation, de-duplication and "pending review" rules live in
/// exactly one place.
class TransactionRepository {
  TransactionRepository({
    required TransactionDao dao,
    DateTime Function()? clock,
  })  : _dao = dao,
        _now = clock ?? DateTime.now;

  final TransactionDao _dao;
  final DateTime Function() _now;

  // ------------------------------------------------------------------ read

  Future<List<Transaction>> inMonth(DateTime month) {
    return _dao.inRange(
      from: Fmt.startOfMonth(month),
      to: Fmt.startOfNextMonth(month),
    );
  }

  Future<PeriodTotals> totalsFor(DateTime month) {
    return _dao.totals(
      from: Fmt.startOfMonth(month),
      to: Fmt.startOfNextMonth(month),
    );
  }

  Future<List<CategoryTotal>> categoryBreakdown(DateTime month) {
    return _dao.expenseByCategory(
      from: Fmt.startOfMonth(month),
      to: Fmt.startOfNextMonth(month),
    );
  }

  Future<List<({DateTime month, int total})>> trailingExpenses(
    DateTime now, {
    int months = 6,
  }) {
    return _dao.monthlyExpenses(now: now, months: months);
  }

  Future<List<Transaction>> recent({int limit = 5}) => _dao.recent(limit: limit);

  Future<int> pendingReviewCount() => _dao.countPendingReview();

  Future<List<String>> recentDescriptions({int limit = 8}) =>
      _dao.recentDescriptions(limit: limit);

  // ------------------------------------------------------- manual writing

  Future<Transaction> addManual({
    required TxType type,
    required int amount,
    required DateTime occurredAt,
    required String description,
    String? categoryId,
    String? accountId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'phải lớn hơn 0');
    }

    final bool isIncome = type == TxType.income;
    final Category resolved = Category.byId(categoryId) ??
        AutoCategorizer.categorize(description, isIncome: isIncome) ??
        Category.other;
    assert(resolved != null);

    final Transaction draft = Transaction(
      id: Transaction.draftId,
      type: type,
      amount: amount,
      occurredAt: occurredAt,
      description: description.trim(),
      categoryId: resolved.id,
      source: TxSource.manual,
      accountId: accountId ?? Account.cashId,
    );

    final int id = await _dao.insert(draft);
    return draft.copyWith(id: id);
  }

  Future<void> updateCategory(Transaction tx, Category? category) async {
    await _dao.updateCategory(tx.id, category?.id);
  }

  /// Category ids from user-defined categories are not valid enum values, so
  /// they are written straight to the row instead of through [Category].
  Future<void> updateCategoryId(Transaction tx, String? categoryId) async {
    await _dao.updateCategory(tx.id, categoryId);
  }

  /// Re-buckets every transaction of a deleted category. Returns rows moved.
  Future<int> reassignCategory(String fromCategoryId, String toCategoryId) {
    return _dao.reassignCategory(fromCategoryId, toCategoryId);
  }

  Future<void> update(Transaction tx) => _dao.update(tx);

  Future<void> delete(Transaction tx) => _dao.delete(tx.id);

  // ------------------------------------------------- deep link / SMS ingest

  /// Ingests raw text forwarded by the iOS Shortcut (`mbbmoney://add?raw=…`).
  ///
  /// Never throws for "not a transaction" — those come back as
  /// [IngestStatus.ignored] so the Shortcut can run silently on every SMS.
  Future<IngestResult> ingestRawText(
    String rawText, {
    DateTime? receivedAt,
  }) async {
    if (!MbBankParser.looksLikeMbNotice(rawText)) {
      return const IngestResult(
        IngestStatus.ignored,
        message: 'Không phải tin biến động số dư MB',
      );
    }

    final MbParseResult parsed;
    try {
      parsed = MbBankParser.parse(rawText, fallbackTime: receivedAt ?? _now());
    } on MbParseException catch (e) {
      return IngestResult(IngestStatus.failed, message: e.reason);
    }

    final TxType type = parsed.isIncome ? TxType.income : TxType.expense;
    final Category? guess =
        AutoCategorizer.categorize(parsed.description, isIncome: parsed.isIncome);

    final bool needsReview =
        parsed.confidence < MbBankParser.reviewThreshold || guess == null;

    final Transaction draft = Transaction(
      id: Transaction.draftId,
      type: type,
      amount: parsed.amount,
      occurredAt: parsed.occurredAt,
      description: parsed.description,
      counterparty: parsed.counterparty,
      categoryId: guess?.id,
      source: TxSource.shortcut,
      accountId: Account.mbId,
      referenceNumber: parsed.referenceNumber,
      rawText: rawText,
      isPendingReview: needsReview,
    );

    final int id = await _dao.insert(draft);
    if (id == 0) {
      // Unique index swallowed it: the same SMS already arrived.
      return const IngestResult(IngestStatus.duplicate);
    }

    return IngestResult(
      needsReview ? IngestStatus.needsReview : IngestStatus.added,
      transaction: draft.copyWith(id: id),
      message: needsReview
          ? 'Đã lưu nhưng cần bạn xác nhận phân loại'
          : null,
    );
  }

  /// Inserts rows pulled from SePay. Returns how many were genuinely new.
  ///
  /// SePay rows are converted to [TxSource.sepay] and given the
  /// `sepay:<id>` key so a re-run can never duplicate them.
  Future<int> ingestSepayRows(
    List<({int amount, bool isIncome, DateTime at, String content, String key, String? bank})> rows,
  ) async {
    final List<Transaction> drafts = <Transaction>[];
    for (final ({int amount, bool isIncome, DateTime at, String content, String key, String? bank}) row
        in rows) {
      if (row.amount <= 0) continue;
      final Category? guess = AutoCategorizer.categorize(
        row.content,
        isIncome: row.isIncome,
      );
      drafts.add(
        Transaction(
          id: Transaction.draftId,
          type: row.isIncome ? TxType.income : TxType.expense,
          amount: row.amount,
          occurredAt: row.at,
          description: _displayContent(row.content),
          categoryId: guess?.id,
          source: TxSource.sepay,
          accountId: Account.mbId,
          referenceNumber: row.key,
          isPendingReview: guess == null,
        ),
      );
    }
    return _dao.insertAllIfNew(drafts);
  }

  /// SePay memos are long bank strings; trim to something that fits a row.
  static String _displayContent(String content) {
    final String trimmed = content.trim();
    if (trimmed.isEmpty) return 'Giao dịch SePay';
    return trimmed.length > 80 ? '${trimmed.substring(0, 79)}\u2026' : trimmed;
  }
}
