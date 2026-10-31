import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';

/// Liquid Glass Holographic Balance Hero Card
/// Designed for Hoang:
/// - Displays total spent (TỔNG TIỀN ĐÃ CHI)
/// - Total count of transactions (ĐÃ GIAO DỊCH BAO NHIÊU GIAO DỊCH)
/// - Live SePay MB Bank badge with 1-tap instant sync
/// - Frosted glass reflection and neon aura
class BalanceHeroCard extends StatelessWidget {
  const BalanceHeroCard({
    required this.income,
    required this.expense,
    required this.month,
    required this.onPreviousMonth,
    required this.onNextMonth,
    this.txCount = 0,
    this.canGoForward = false,
    this.dailyBudgetLeft,
    this.onSyncTap,
    super.key,
  });

  final int income;
  final int expense;
  final DateTime month;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final int txCount;
  final bool canGoForward;
  final int? dailyBudgetLeft;
  final VoidCallback? onSyncTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xB00B1120),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.45), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonCyan.withValues(alpha: 0.15),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Liquid Glass Corner Accents
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.neonPink, width: 2.5),
                      right: BorderSide(color: AppColors.neonPink, width: 2.5),
                    ),
                    borderRadius: BorderRadius.only(topRight: Radius.circular(AppRadius.card)),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: Month Selector & SePay Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0x6604060C),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: onPreviousMonth,
                                child: const Icon(Icons.chevron_left, color: AppColors.neonCyan, size: 20),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  'THÁNG ${month.month} // ${month.year}',
                                  style: const TextStyle(
                                    fontFamily: 'Courier New',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.ink,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: canGoForward ? onNextMonth : null,
                                child: Icon(
                                  Icons.chevron_right,
                                  color: canGoForward ? AppColors.neonCyan : AppColors.inkFaint,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // SePay MB Bank badge
                        GestureDetector(
                          onTap: onSyncTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0x3300F0FF), Color(0x22FF0055)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.neonCyan, width: 1.2),
                              boxShadow: AppColors.neonGlow(AppColors.neonCyan, blur: 8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt, color: AppColors.neonCyan, size: 14),
                                SizedBox(width: 5),
                                Text(
                                  'SEPAY MB',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.neonCyan,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Metric 1: TỔNG TIỀN ĐÃ CHI
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.neonPink,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: AppColors.neonPink, blurRadius: 10, spreadRadius: 2),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'TỔNG TIỀN ĐÃ CHI THÁNG NÀY',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: AppColors.neonPink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Fmt.dong(expense),
                      style: const TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Metric 2: ĐÃ GIAO DỊCH BAO NHIÊU GIAO DỊCH & HẠN MỨC
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0x7304060C),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.strokeFaint),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.receipt_rounded, color: AppColors.neonCyan, size: 16),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'ĐÃ CHI: $txCount GIAO DỊCH',
                                      style: const TextStyle(
                                        fontFamily: 'Courier New',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.neonCyan,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                dailyBudgetLeft != null && dailyBudgetLeft! > 0
                                    ? 'HẠN MỨC ~${Fmt.compact(dailyBudgetLeft!)}/NGÀY'
                                    : 'MB BANK ONLINE',
                                style: const TextStyle(
                                  fontFamily: 'Courier New',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.neonYellow,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
