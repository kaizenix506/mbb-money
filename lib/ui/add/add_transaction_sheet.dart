import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/auto_categorizer.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../stores/transaction_store.dart';
import '../widgets/sheet_kit.dart';

/// Quick-add sheet.
///
/// Optimised for one-handed use: the *amount* is the first and only required
/// field, and typing it is a big numeric pad with a huge submit button. The
/// category auto-suggests from the description and can be overridden in one tap.
class AddTransactionSheet extends StatefulWidget {
  const AddTransactionSheet({this.initialType = TxType.expense, super.key});

  final TxType initialType;

  static Future<bool?> show(BuildContext context, {TxType? type}) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => AddTransactionSheet(initialType: type ?? TxType.expense),
    );
  }

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final FocusNode _amountFocus = FocusNode();

  late TxType _type = widget.initialType;
  DateTime _date = DateTime.now();
  Category? _category;
  bool _categoryTouched = false;
  bool _saving = false;

  /// Digits only, so "20.000" and "20000" both become 20000.
  int get _amountValue =>
      int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType == TxType.transfer
        ? TxType.expense
        : widget.initialType;
    WidgetsBinding.instance.addPostFrameCallback((_) => _amountFocus.requestFocus());
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _onDescriptionChanged(String value) {
    if (_categoryTouched) return;
    final Category? guess = AutoCategorizer.categorize(
      value,
      isIncome: _type == TxType.income,
    );
    if (guess != _category) setState(() => _category = guess);
  }

  Future<void> _save() async {
    final int value = _amountValue;
    if (value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập số tiền trước đã')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await context.read<TransactionStore>().addManual(
            type: _type,
            amount: value,
            occurredAt: _date,
            description: _description.text.trim(),
            categoryId: _category?.id,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không lưu được: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isIncome = _type == TxType.income;
    final Color accent = isIncome ? AppColors.mint : AppColors.coral;

    return SheetKit.dismissKeyboardOnTap(
      Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgMid,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Thêm giao dịch',
                      style: AppText.sectionTitle.copyWith(
                        fontSize: 18,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  _SegmentedType(
                    value: _type,
                    onChanged: (TxType t) => setState(() {
                      _type = t;
                      if (_categoryTouched) _category = null;
                      _categoryTouched = false;
                      _onDescriptionChanged(_description.text);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _amount,
                focusNode: _amountFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  color: accent,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkFaint.withValues(alpha: 0.5),
                  ),
                  suffixText: '₫',
                  suffixStyle: TextStyle(fontSize: 18, color: accent),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_amountValue > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '= ${Fmt.money(_amountValue)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkDim,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.strokeFaint),
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onDescriptionChanged,
                decoration: const InputDecoration(
                  hintText: 'Nội dung (vd. Highlands Coffee)',
                  prefixIcon: Icon(Icons.edit_note_rounded,
                      size: 20, color: AppColors.inkFaint),
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Phân loại'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Category c in isIncome
                      ? Category.incomeChoices
                      : Category.expenseChoices)
                    _CategoryChip(
                      category: c,
                      selected: _category == c,
                      onTap: () => setState(() {
                        _category = _category == c ? null : c;
                        _categoryTouched = true;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const _FieldLabel('Thời gian'),
              const SizedBox(height: 8),
              _DateField(
                value: _date,
                onPick: _pickDate,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: isIncome
                        ? const Color(0xFF04231A)
                        : const Color(0xFF2A0808),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_typeLabel),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
      ),
    );
  }

  String get _typeLabel => switch (_type) {
        TxType.income => 'Lưu khoản thu',
        TxType.expense => 'Lưu khoản chi',
        TxType.transfer => 'Lưu chuyển khoản',
      };

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      helpText: 'Ngày giao dịch',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.mint,
              surface: AppColors.bgMid,
              onSurface: AppColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Giờ giao dịch',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
    );
    if (time == null) return;

    setState(() {
      _date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: AppColors.inkFaint,
      ),
    );
  }
}

class _SegmentedType extends StatelessWidget {
  const _SegmentedType({required this.value, required this.onChanged});

  final TxType value;
  final ValueChanged<TxType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.strokeFaint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SegChip(
            label: 'Chi',
            selected: value == TxType.expense,
            color: AppColors.coral,
            onTap: () => onChanged(TxType.expense),
          ),
          _SegChip(
            label: 'Thu',
            selected: value == TxType.income,
            color: AppColors.mint,
            onTap: () => onChanged(TxType.income),
          ),
        ],
      ),
    );
  }
}

class _SegChip extends StatelessWidget {
  const _SegChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: selected ? color.withValues(alpha: 0.18) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? color : AppColors.inkDim,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: selected
              ? category.tint.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.045),
          border: Border.all(
            color: selected
                ? category.tint.withValues(alpha: 0.55)
                : AppColors.strokeFaint,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              category.icon,
              size: 14,
              color: selected ? category.tint : AppColors.inkDim,
            ),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.ink : AppColors.inkDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onPick});

  final DateTime value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final bool isToday = value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.field),
          color: AppColors.glass,
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.schedule_rounded,
                size: 18, color: AppColors.inkFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isToday
                    ? 'Hôm nay · ${Fmt.time(value)}'
                    : '${Fmt.dayMonth(value)} · ${Fmt.time(value)}',
                style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
