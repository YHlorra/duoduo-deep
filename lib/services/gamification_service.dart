import '../data/database/database_helper.dart';
import '../data/models/user_stats.dart';

/// 游戏化服务 - 管理 XP、连续打卡、心数、掌握度
class GamificationService {
  final DatabaseHelper _db;

  GamificationService(this._db);

  static const int xpPerCorrect = 10;
  static const int xpPerDeckComplete = 50;
  static const int xpPerPerfectDeck = 100;

  /// 获取用户统计(自动检查每日重置)
  Future<UserStats> getStats() async {
    var stats = await _db.getUserStats();
    // 如果不是今天，重置 todayXp
    if (!stats.isToday) {
      // 检查是否中断了 streak
      if (!stats.studiedYesterday) {
        stats = stats.copyWith(streak: 0, todayXp: 0);
      } else {
        stats = stats.copyWith(todayXp: 0);
      }
      await _db.updateUserStats(stats);
    }
    return stats;
  }

  /// 答对一题
  Future<UserStats> onCorrectAnswer() async {
    var stats = await getStats();
    stats = stats.copyWith(
      xp: stats.xp + xpPerCorrect,
      todayXp: stats.todayXp + xpPerCorrect,
    );

    // 更新 streak
    if (!stats.isToday) {
      if (stats.studiedYesterday) {
        stats = stats.copyWith(streak: stats.streak + 1);
      } else {
        stats = stats.copyWith(streak: 1);
      }
      stats = stats.copyWith(lastStudyDate: DateTime.now());
    }

    await _db.updateUserStats(stats);
    return stats;
  }

  /// 答错一题(扣心)
  Future<UserStats> onWrongAnswer() async {
    var stats = await getStats();

    // 更新 streak (即使答错也记录今天学习了)
    if (!stats.isToday) {
      if (stats.studiedYesterday) {
        stats = stats.copyWith(streak: stats.streak + 1);
      } else {
        stats = stats.copyWith(streak: 1);
      }
      stats = stats.copyWith(lastStudyDate: DateTime.now());
    }

    // 扣心
    if (stats.hearts > 0) {
      stats = stats.copyWith(hearts: stats.hearts - 1);
    }

    await _db.updateUserStats(stats);
    return stats;
  }

  /// 完成题包
  Future<UserStats> onDeckComplete({required bool allCorrect}) async {
    var stats = await getStats();
    final bonus = allCorrect ? xpPerPerfectDeck : xpPerDeckComplete;
    stats = stats.copyWith(
      xp: stats.xp + bonus,
      todayXp: stats.todayXp + bonus,
    );
    await _db.updateUserStats(stats);
    return stats;
  }

  /// 恢复一颗心
  Future<UserStats> refillOneHeart() async {
    var stats = await getStats();
    if (stats.hearts < stats.maxHearts) {
      stats = stats.copyWith(hearts: stats.hearts + 1);
      await _db.updateUserStats(stats);
    }
    return stats;
  }

  /// 设置每日目标
  Future<void> setDailyGoal(int goal) async {
    var stats = await getStats();
    stats = stats.copyWith(dailyGoal: goal);
    await _db.updateUserStats(stats);
  }

  /// 检查是否完成每日目标
  bool isDailyGoalComplete(UserStats stats) {
    return stats.todayXp >= stats.dailyGoal;
  }

  /// 计算题包掌握度
  int calculateMasteryLevel(int correctCount, int totalCount) {
    if (totalCount == 0) return 0;
    final accuracy = correctCount / totalCount;
    return (accuracy * 100).round();
  }
}
