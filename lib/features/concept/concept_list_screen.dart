import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/providers.dart';
import '../../services/sm2_algorithm.dart';
import 'concept_detail_screen.dart';
import '../learning/quiz_screen.dart';

/// 概念掌握度列表页

/// 概念掌握度列表页
class ConceptListScreen extends ConsumerWidget {
  const ConceptListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masteryAsync = ref.watch(conceptMasteryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('概念掌握度'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '什么是概念页？',
            onPressed: () => _showHelpDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(conceptMasteryProvider.notifier).refresh(),
          ),
        ],
      ),
      body: masteryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.green)),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (concepts) {
          if (concepts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.psychology_outlined, size: 64, color: AppColors.textLight),
                  const SizedBox(height: 16),
                  Text(
                    '还没有追踪的概念',
                    style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '开始答题后，系统会自动追踪你的概念掌握度',
                    style: TextStyle(fontSize: 13, color: AppColors.textLight),
                  ),
                ],
              ),
            );
          }

          final due = concepts.where((c) => c.isDue).toList();
          final mastered = concepts.where((c) => c.masteryLevel == 'mastered').toList();
          final learning = concepts.where((c) => c.masteryLevel == 'learning').toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 统计卡片
              Row(
                children: [
                  _statCard('已掌握', mastered.length, AppColors.green),
                  const SizedBox(width: 8),
                  _statCard('学习中', learning.length, AppColors.streakOrange),
                  const SizedBox(width: 8),
                  _statCard('待复习', due.length, AppColors.red),
                ],
              ),
              // 7 日到期预报
              if (concepts.isNotEmpty) ...[
                const SizedBox(height: 12),
                _forecastBar(concepts),
              ],
              const SizedBox(height: 24),
              // 今日到期
              if (due.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle('今日应复习'),
                    TextButton.icon(
                      onPressed: () => _startReview(context, ref),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('开始复习'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.green),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...due.map((c) => _conceptCard(c, highlight: true, onTap: () => _openDetail(context, c))),
                const SizedBox(height: 16),
              ],
              // 全部概念
              _sectionTitle('全部概念 (${concepts.length})'),
              const SizedBox(height: 8),
              ...concepts.map((c) => _conceptCard(c, onTap: () => _openDetail(context, c))),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, ConceptMasteryInfo info) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConceptDetailScreen(info: info)),
    );
  }

  Future<void> _startReview(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final questions = await db.getSmartRandomQuestions(5);
    if (!context.mounted || questions.isEmpty) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuizScreen(questions: questions)),
    );
    ref.read(conceptMasteryProvider.notifier).refresh();
  }

  void _showHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.psychology_outlined, color: AppColors.blue),
            SizedBox(width: 8),
            Text('概念页是什么？'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '系统会自动追踪你答题中遇到的每一个概念，并根据 SM-2 间隔重复算法安排下一次复习时间——答得越稳，间隔越长。',
                style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              _legendItem(
                AppColors.green,
                '已掌握',
                '连续答对 ≥ 3 次，且记忆强度（ease factor）≥ 2.3。间隔最长可拉到 125 天。',
              ),
              const SizedBox(height: 10),
              _legendItem(
                AppColors.streakOrange,
                '学习中',
                '刚开始接触或还未达「已掌握」阈值，正在巩固。',
              ),
              const SizedBox(height: 10),
              _legendItem(
                AppColors.red,
                '待复习',
                '到了系统安排的复习时间，建议今天再过一遍。',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '为什么只看到部分概念？\n概念列表只来自你已经生成并且实际作答过的题包，未答题的题包不会产生记录。',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('明白了'),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6, right: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: '$label：',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
    );
  }

  /// 7 日到期预报条：柱状显示未来 7 天每天的到期概念数。
  Widget _forecastBar(List<ConceptMasteryInfo> concepts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List.filled(7, 0);
    for (final c in concepts) {
      if (c.nextReviewDate == null) continue;
      final d = DateTime(c.nextReviewDate!.year, c.nextReviewDate!.month, c.nextReviewDate!.day);
      final diff = d.difference(today).inDays;
      if (diff >= 0 && diff < 7) counts[diff]++;
    }
    if (counts.every((c) => c == 0)) return const SizedBox.shrink();

    final labels = ['今', '明', '后', '3天', '4天', '5天', '6天'];
    final maxCount = counts.reduce((a, b) => a > b ? a : b).clamp(1, 10);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('未来 7 天复习量', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final count = counts[i];
              final isToday = i == 0;
              final barColor = count == 0
                  ? AppColors.border
                  : (isToday ? AppColors.red : AppColors.green);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: count > 0 ? AppColors.textPrimary : AppColors.textLight)),
                      const SizedBox(height: 4),
                      // ponytail: 简单比例柱 — 高度按 count/maxCount 缩放，最小 4px 保证可见
                      Container(
                        height: 4 + (count / maxCount) * 28,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(labels[i], style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _conceptCard(ConceptMasteryInfo info, {bool highlight = false, VoidCallback? onTap}) {
    final color = [AppColors.red, AppColors.streakOrange, AppColors.green][info.statusColorIndex];
    final masteryText = {'mastered': '已掌握', 'learning': '学习中', 'unknown': '未评估'}[info.masteryLevel] ?? info.masteryLevel;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlight ? color.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight ? color.withOpacity(0.3) : AppColors.border,
            width: highlight ? 2 : 1,
          ),
        ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '$masteryText · 重复 ${info.repetitions} 次 · 间隔 ${info.intervalDays} 天',
                  style: TextStyle(fontSize: 12, color: AppColors.textLight),
                ),
              ],
            ),
          ),
          if (info.isDue)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('到期', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.red)),
            ),
        ],
      ),
      ),
    );
  }
}
