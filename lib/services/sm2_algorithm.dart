/// 简化 SM-2 间隔重复算法
class Sm2Result {
  final double easeFactor;
  final int intervalDays;
  final int repetitions;
  final DateTime nextReviewDate;

  const Sm2Result({
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    required this.nextReviewDate,
  });
}

/// 简化 SM-2 算法
/// quality: 0-5 评分（答对=4，答错=1，苏格拉底后理解=3）
Sm2Result sm2({
  required double easeFactor,
  required int intervalDays,
  required int repetitions,
  required int quality,
}) {
  // 更新 ease factor
  final newEase = (easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))
      .clamp(1.3, 2.8);

  int newReps;
  int newInterval;

  if (quality < 3) {
    // 答错：重置
    newReps = 0;
    newInterval = 1;
  } else {
    newReps = repetitions + 1;
    if (newReps == 1) {
      newInterval = 1;
    } else if (newReps == 2) {
      newInterval = 3;
    } else {
      newInterval = (intervalDays * newEase).round();
    }
  }

  final nextReview = DateTime.now().add(Duration(days: newInterval));

  return Sm2Result(
    easeFactor: newEase,
    intervalDays: newInterval,
    repetitions: newReps,
    nextReviewDate: nextReview,
  );
}

/// 课程概念掌握度信息（用于 UI 展示）
class ConceptMasteryInfo {
  final String name;
  final double easeFactor;
  final int intervalDays;
  final int repetitions;
  final DateTime? nextReviewDate;
  final String? lastResult;
  final DateTime updatedAt;

  const ConceptMasteryInfo({
    required this.name,
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    this.nextReviewDate,
    this.lastResult,
    required this.updatedAt,
  });

  /// 掌握度: 'unknown' | 'learning' | 'mastered'
  String get masteryLevel {
    if (repetitions == 0 && lastResult != null) return 'unknown';
    if (repetitions >= 3 && easeFactor >= 2.3) return 'mastered';
    return 'learning';
  }

  /// 颜色标识
  int get statusColorIndex {
    switch (masteryLevel) {
      case 'mastered':
        return 2; // green
      case 'learning':
        return 1; // orange
      default:
        return 0; // red
    }
  }

  /// 是否到期
  bool get isDue {
    if (nextReviewDate == null) return false;
    return nextReviewDate!.millisecondsSinceEpoch <= DateTime.now().millisecondsSinceEpoch;
  }
}
