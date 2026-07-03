import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/providers.dart';
import '../../data/models/deck.dart';
import '../../data/models/user_stats.dart';
import '../settings/settings_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsProvider);
    final decksAsync = ref.watch(deckListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 头像和等级
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.green, AppColors.greenDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 40,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '学习者',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    statsAsync.when(
                      data: (stats) => Text(
                        '等级 ${stats.xp ~/ 100 + 1}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 统计网格
              statsAsync.when(
                data: (stats) => _buildStatsGrid(stats),
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.green),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              // 每日目标
              statsAsync.when(
                data: (stats) => _buildDailyGoal(context, stats),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              // 成就
              _buildAchievements(context, statsAsync, decksAsync),
              const SizedBox(height: 24),
              // 菜单项
              _buildMenuItems(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(UserStats stats) {
    return Row(
      children: [
        _StatCard(
          icon: Icons.local_fire_department,
          color: AppColors.streakOrange,
          value: stats.streak.toString(),
          label: '连续天数',
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: Icons.diamond,
          color: AppColors.blue,
          value: stats.xp.toString(),
          label: '总 XP',
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: Icons.favorite,
          color: AppColors.heartRed,
          value: '${stats.hearts}/${stats.maxHearts}',
          label: '心数',
        ),
      ],
    );
  }

  Widget _buildDailyGoal(BuildContext context, UserStats stats) {
    final progress = (stats.todayXp / stats.dailyGoal).clamp(0.0, 1.0);
    final isComplete = stats.todayXp >= stats.dailyGoal;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '每日目标',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${stats.todayXp} / ${stats.dailyGoal} XP',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isComplete ? AppColors.green : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 进度条
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: isComplete ? AppColors.gold : AppColors.green,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          if (isComplete) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.emoji_events, color: AppColors.gold, size: 20),
                const SizedBox(width: 4),
                const Text(
                  '今日目标已达成！',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAchievements(
    BuildContext context,
    AsyncValue<UserStats> statsAsync,
    AsyncValue<List<Deck>> decksAsync,
  ) {
    final decks = decksAsync.value ?? [];
    final stats = statsAsync.value;

    final achievements = <_Achievement>[
      _Achievement(
        icon: Icons.school,
        title: '初次学习',
        desc: '完成第一个题包',
        unlocked: decks.isNotEmpty,
        color: AppColors.green,
      ),
      _Achievement(
        icon: Icons.local_fire_department,
        title: '连续3天',
        desc: '坚持学习3天',
        unlocked: (stats?.streak ?? 0) >= 3,
        color: AppColors.streakOrange,
      ),
      _Achievement(
        icon: Icons.local_fire_department,
        title: '连续7天',
        desc: '坚持学习7天',
        unlocked: (stats?.streak ?? 0) >= 7,
        color: AppColors.red,
      ),
      _Achievement(
        icon: Icons.star,
        title: '收集达人',
        desc: '创建5个题包',
        unlocked: decks.length >= 5,
        color: AppColors.gold,
      ),
      _Achievement(
        icon: Icons.diamond,
        title: '积少成多',
        desc: '累计 500 XP',
        unlocked: (stats?.xp ?? 0) >= 500,
        color: AppColors.blue,
      ),
      _Achievement(
        icon: Icons.emoji_events,
        title: '满分通关',
        desc: '完美完成一个题包',
        unlocked: decks.any((d) => d.masteryLevel >= 100),
        color: AppColors.purple,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '成就',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: achievements.length,
          itemBuilder: (context, index) => _AchievementBadge(
            achievement: achievements[index],
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItems(BuildContext context) {
    return Column(
      children: [
        _MenuItem(
          icon: Icons.settings,
          title: '设置',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
        const SizedBox(height: 8),
        _MenuItem(
          icon: Icons.info,
          title: '关于',
          onTap: () {
            showAboutDialog(
              context: context,
              applicationName: 'DIY 多邻国',
              applicationVersion: '1.0.0',
              applicationLegalese: '自定义题库 + AI 拆题学习 APP',
            );
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Achievement {
  final IconData icon;
  final String title;
  final String desc;
  final bool unlocked;
  final Color color;

  _Achievement({
    required this.icon,
    required this.title,
    required this.desc,
    required this.unlocked,
    required this.color,
  });
}

class _AchievementBadge extends StatelessWidget {
  final _Achievement achievement;

  const _AchievementBadge({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: achievement.unlocked ? achievement.color.withValues(alpha: 0.1) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: achievement.unlocked ? achievement.color.withValues(alpha: 0.3) : AppColors.border,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            achievement.icon,
            size: 32,
            color: achievement.unlocked ? achievement.color : AppColors.textLight,
          ),
          const SizedBox(height: 4),
          Text(
            achievement.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: achievement.unlocked ? AppColors.textPrimary : AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}
