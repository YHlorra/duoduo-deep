import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'heart_countdown.dart';

/// 答题进度条
class QuizProgressBar extends StatelessWidget {
  final double progress; // 0.0 - 1.0
  final int hearts;
  final int maxHearts;
  final DateTime lastHeartRefill;

  const QuizProgressBar({
    super.key,
    required this.progress,
    required this.hearts,
    required this.maxHearts,
    required this.lastHeartRefill,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 关闭按钮
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textLight),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          // 进度条
          Expanded(
            child: Container(
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 心数 + 下一心倒计时
          HeartsWithCountdown(
            hearts: hearts,
            maxHearts: maxHearts,
            lastHeartRefill: lastHeartRefill,
          ),
        ],
      ),
    );
  }
}
