import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../stores/transaction_store.dart';
import '../widgets/common.dart';
import '../widgets/mini_chip.dart';

/// Review queue for rows the parser could not confidently categorise.
///
/// This screen is the safety valve that makes automatic bank ingestion
/// trustworthy: anything the app is unsure about waits here instead of being
/// silently filed under the wrong category.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  static const String route = '/review';

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  List<Transaction>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final TransactionRepository repo = context.read<TransactionRepository>();
    // Pulling the whole month and filtering client-side is fine at this scale
    // and keeps the DAO surface small.
    final List<Transaction> month = await repo.inMonth(DateTime.now());
    if (!mounted) return;
    setState(() {
      _items = month.where((Transaction t) => t.isPendingReview).toList();
      _loading = false;
    });
  }

  Future<void> _assign(Transaction tx, Category category) async {
    await context.read<TransactionStore>().setCategory(tx, category);
    if (!mounted) return;
    setState(() {
      _items = _items
          ?.where((Transaction t) => t.id != tx.id)
          .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Cần xác nhận',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.mint,
                ),
              ),
            )
          : (_items == null || _items!.isEmpty)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.check_circle_rounded,
                            size: 40, color: AppColors.mint),
                        SizedBox(height: 14),
                        Text(
                          'Không còn gì cần xác nhận',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                  itemCount: _items!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int i) {
                    final Transaction tx = _items![i];
                    return _ReviewCard(
                      transaction: tx,
                      onPick: (Category c) => _assign(tx, c),
                    );
                  },
                ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.transaction, required this.onPick});

  final Transaction transaction;
  final ValueChanged<Category> onPick;

  @override
  Widget build(BuildContext context) {
    final bool income = transaction.isIncome;
    final List<Category> choices =
        income ? Category.incomeChoices : Category.expenseChoices;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  Fmt.signed(transaction.signedAmount),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: income ? AppColors.mint : AppColors.ink,
                  ),
                ),
              ),
              Text(
                Fmt.dayMonth(transaction.occurredAt) +
                    ' · ${Fmt.time(transaction.occurredAt)}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            transaction.description,
            style: const TextStyle(fontSize: 13, color: AppColors.ink),
          ),
          if (transaction.rawText != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              transaction.rawText!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: AppColors.inkFaint,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Category c in choices)
                MiniChip(
                  label: c.label,
                  icon: c.icon,
                  tint: c.tint,
                  selected: false,
                  onTap: () => onPick(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
