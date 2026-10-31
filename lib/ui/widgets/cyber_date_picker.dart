import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/vn_clock.dart';

/// Opens a native iOS-style vertical rolling wheel date and time picker
/// ("vuốt dọc như đồng hồ iPhone") styled with the Midnight Cyberpunk glass aesthetic.
Future<DateTime?> showCyberDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  DateTime? minimumDate,
  DateTime? maximumDate,
}) async {
  final DateTime now = VnClock.localNow();
  final DateTime min = minimumDate ?? DateTime(now.year - 5);
  final DateTime max = maximumDate ?? DateTime(now.year + 1);

  DateTime selected = initialDateTime;

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setModalState) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xF2080E1C),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(color: AppColors.neonCyan, width: 1.4),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  18,
                  14,
                  18,
                  20 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Drag indicator handle
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Header bar
                    Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.inkDim,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          child: const Text(
                            'HỦY',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'THỜI GIAN GIAO DỊCH',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppColors.neonCyan,
                          ),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            Navigator.of(ctx).pop(selected);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.neonCyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: const Size(0, 36),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'XONG',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick Presets Row
                    Row(
                      children: <Widget>[
                        _PresetChip(
                          label: 'Vừa xong',
                          icon: Icons.flash_on_rounded,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setModalState(() {
                              selected = VnClock.localNow();
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _PresetChip(
                          label: 'Hôm nay',
                          icon: Icons.today_rounded,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            final DateTime n = VnClock.localNow();
                            setModalState(() {
                              selected = DateTime(
                                n.year,
                                n.month,
                                n.day,
                                selected.hour,
                                selected.minute,
                              );
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _PresetChip(
                          label: 'Hôm qua',
                          icon: Icons.history_rounded,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            final DateTime y = VnClock.localNow().subtract(const Duration(days: 1));
                            setModalState(() {
                              selected = DateTime(
                                y.year,
                                y.month,
                                y.day,
                                selected.hour,
                                selected.minute,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Current Selected Preview Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.neonCyan.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.neonCyan.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            Icons.access_time_filled_rounded,
                            size: 15,
                            color: AppColors.neonCyan,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${Fmt.dayOfWeek(selected)}, ${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}  —  ${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontFamily: 'Courier New',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // iOS Vertical Rolling Wheel Picker
                    Container(
                      height: 216,
                      decoration: BoxDecoration(
                        color: const Color(0x66040814),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.strokeFaint,
                          width: 1,
                        ),
                      ),
                      child: CupertinoTheme(
                        data: const CupertinoThemeData(
                          brightness: Brightness.dark,
                          textTheme: CupertinoTextThemeData(
                            dateTimePickerTextStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        child: CupertinoDatePicker(
                          key: ValueKey<int>(selected.millisecondsSinceEpoch ~/ 60000),
                          mode: CupertinoDatePickerMode.dateAndTime,
                          use24hFormat: true,
                          initialDateTime: selected.isBefore(min)
                              ? min
                              : (selected.isAfter(max) ? max : selected),
                          minimumDate: min,
                          maximumDate: max,
                          onDateTimeChanged: (DateTime newDateTime) {
                            HapticFeedback.selectionClick();
                            setModalState(() {
                              selected = newDateTime;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.strokeFaint),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: AppColors.neonCyan),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
