import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/providers.dart';
import '../../data/models/deck.dart';
import '../../services/json_extractor.dart';
import '../../services/sm2_algorithm.dart';
import '../learning/quiz_screen.dart';

/// 概念详情页：定义 + keyPoints + SM-2 状态 + 关联题包。
/// 定义缺失时显示「AI 解释」按钮懒生成并写回 concepts 表。
class ConceptDetailScreen extends ConsumerStatefulWidget {
  final ConceptMasteryInfo info;

  const ConceptDetailScreen({super.key, required this.info});

  @override
  ConsumerState<ConceptDetailScreen> createState() => _ConceptDetailScreenState();
}

class _ConceptDetailScreenState extends ConsumerState<ConceptDetailScreen> {
  String? _description;
  List<String> _keyPoints = [];
  bool _loading = true;
  bool _generating = false;
  List<Deck> _relatedDecks = [];

  @override
  void initState() {
    super.initState();
    _loadDefinition();
    _loadRelatedDecks();
  }

  Future<void> _loadDefinition() async {
    final db = ref.read(databaseProvider);
    final c = await db.getConcept(widget.info.name);
    if (!mounted) return;
    setState(() {
      _description = c?['description'] as String?;
      _keyPoints = (c?['key_points'] as List<dynamic>?)?.cast<String>() ?? [];
      _loading = false;
    });
  }

  Future<void> _loadRelatedDecks() async {
    final db = ref.read(databaseProvider);
    final all = await db.getAllDecks();
    if (!mounted) return;
    setState(() {
      _relatedDecks = all.where((d) => d.concepts.contains(widget.info.name)).toList();
    });
  }

  Future<void> _generateWithAi() async {
    final ai = ref.read(openaiServiceProvider);
    if (!await ai.hasApiKey()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置 API Key'), backgroundColor: AppColors.red),
      );
      return;
    }
    setState(() => _generating = true);
    try {
      final raw = await ai.chatCompletion(
        systemPrompt: '你是知识百科助手。用简洁中文解释给定概念，输出 JSON：'
            '{"name":"概念名","description":"一段话解释(50-150字)","keyPoints":["要点1","要点2",...]}'
            '。只输出 JSON。',
        userContent: widget.info.name,
        temperature: 0.3,
      );
      final parsed = JsonExtractor.parse(raw);
      final desc = parsed?['description'] as String?;
      final kp = (parsed?['keyPoints'] as List<dynamic>?)?.map((e) => e.toString()).toList();
      if (desc != null) {
        await ref.read(databaseProvider).upsertConcept(
              widget.info.name,
              description: desc,
              keyPoints: kp,
            );
        if (!mounted) return;
        setState(() {
          _description = desc;
          _keyPoints = kp ?? [];
          _generating = false;
        });
      } else {
        throw Exception('AI 返回格式异常');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final color = [AppColors.red, AppColors.streakOrange, AppColors.green][info.statusColorIndex];
    final masteryText = {'mastered': '已掌握', 'learning': '学习中', 'unknown': '未评估'}[info.masteryLevel] ?? info.masteryLevel;

    return Scaffold(
      appBar: AppBar(title: Text(info.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 掌握度状态卡
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3), width: 2),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(masteryText, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                      const SizedBox(height: 4),
                      Text(
                        '重复 ${info.repetitions} 次 · 间隔 ${info.intervalDays} 天',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      if (info.nextReviewDate != null)
                        Text(
                          '下次复习: ${_formatDate(info.nextReviewDate!)}',
                          style: TextStyle(fontSize: 13, color: info.isDue ? AppColors.red : AppColors.textLight),
                        ),
                    ],
                  ),
                ),
                if (info.isDue)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(6)),
                    child: const Text('到期', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 定义区
          const Text('概念释义', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppColors.green)))
          else if (_description != null && _description!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
              child: Text(_description!, style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textPrimary)),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('还没有这个概念的释义。', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generating ? null : _generateWithAi,
                      icon: _generating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_generating ? '生成中...' : 'AI 解释'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // keyPoints
          if (_keyPoints.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._keyPoints.map((k) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 7, right: 10), decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                      Expanded(child: Text(k, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textPrimary))),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 20),
          // 关联题包
          if (_relatedDecks.isNotEmpty) ...[
            const Text('关联题包', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            ..._relatedDecks.map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    tileColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    subtitle: Text('${d.questionCount} 题', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textLight),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => QuizScreen(deckId: d.id)),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.month}/${d.day}';
  }
}
