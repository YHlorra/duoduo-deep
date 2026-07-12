import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';

/// 倒计时文本 `0:43`。满血时一般由父组件不渲染。
class HeartCountdownText extends ConsumerStatefulWidget {
  final DateTime lastHeartRefill;
  final TextStyle? style;
  const HeartCountdownText({
    super.key,
    required this.lastHeartRefill,
    this.style,
  });

  @override
  ConsumerState<HeartCountdownText> createState() => _HeartCountdownState();
}

class _HeartCountdownState extends ConsumerState<HeartCountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 负 elapsed（时钟回拨）兜底为 0，避免倒计时变成 >60s 的怪值。
    final rawElapsed = DateTime.now().difference(widget.lastHeartRefill).inSeconds;
    final elapsed = rawElapsed < 0 ? 0 : rawElapsed;
    final secondsLeft = 60 - (elapsed % 60);
    final secs = secondsLeft % 60;
    final mins = secondsLeft ~/ 60;
    return Text(
      '$mins:${secs.toString().padLeft(2, '0')}',
      style: widget.style ??
          const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.heartRed,
          ),
    );
  }
}

/// 心数 + 下一心倒计时组合。满血时只显示 `5/5`。
class HeartsWithCountdown extends StatelessWidget {
  final int hearts;
  final int maxHearts;
  final DateTime lastHeartRefill;

  const HeartsWithCountdown({
    super.key,
    required this.hearts,
    required this.maxHearts,
    required this.lastHeartRefill,
  });

  @override
  Widget build(BuildContext context) {
    final showCountdown = hearts < maxHearts;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$hearts/$maxHearts',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (showCountdown) ...[
          const SizedBox(width: 6),
          HeartCountdownText(lastHeartRefill: lastHeartRefill),
        ],
      ],
    );
  }
}
