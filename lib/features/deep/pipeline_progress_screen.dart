import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../services/content_analyzer.dart';
import 'deep_pipeline_controller.dart';
import 'tools/learning_goal.dart';
import '../ingestion/deck_preview_screen.dart';

class PipelineProgressScreen extends ConsumerStatefulWidget {
  final LearningGoal goal;

  const PipelineProgressScreen({super.key, required this.goal});

  @override
  ConsumerState<PipelineProgressScreen> createState() => _PipelineProgressScreenState();
}

class _PipelineProgressScreenState extends ConsumerState<PipelineProgressScreen> {
  @override
  void initState() {
    super.initState();
    // 启动管线
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deepPipelineProvider.notifier).run(widget.goal);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deepPipelineProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          '深度拆解',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 图标
              _buildStageIcon(state.stage),
              const SizedBox(height: 32),

              // 状态描述
              Text(
                state.statusText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 进度条
              if (state.stage == PipelineStage.searching ||
                  state.stage == PipelineStage.generating)
                const LinearProgressIndicator(
                  minHeight: 6,
                  borderRadius: BorderRadius.all(Radius.circular(3)),
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.blue),
                ),
              const SizedBox(height: 24),

              // 工具调用计数
              if (state.toolCallCount > 0)
                Text(
                  '已搜索 ${state.toolCallCount} 次',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 32),

              // 取消按钮
              if (state.stage == PipelineStage.searching ||
                  state.stage == PipelineStage.generating)
                OutlinedButton(
                  onPressed: () {
                    ref.read(deepPipelineProvider.notifier).cancel();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),

              // 失败状态：错误 + 重试
              if (state.stage == PipelineStage.failed) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.red, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.red, size: 28),
                      const SizedBox(height: 8),
                      Text(
                        state.error ?? '未知错误',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.redDark,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.read(deepPipelineProvider.notifier).reset();
                    ref.read(deepPipelineProvider.notifier).run(widget.goal);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '重试',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],

              // 完成状态：自动跳转
              if (state.stage == PipelineStage.done && state.result != null)
                _buildDoneContent(state.result!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageIcon(PipelineStage stage) {
    IconData icon;
    Color color;
    switch (stage) {
      case PipelineStage.searching:
        icon = Icons.search_rounded;
        color = AppColors.blue;
        break;
      case PipelineStage.generating:
        icon = Icons.auto_awesome_rounded;
        color = AppColors.purple;
        break;
      case PipelineStage.done:
        icon = Icons.check_circle_rounded;
        color = AppColors.green;
        break;
      case PipelineStage.failed:
        icon = Icons.error_outline_rounded;
        color = AppColors.red;
        break;
      default:
        icon = Icons.psychology_rounded;
        color = AppColors.blue;
    }

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(icon, size: 48, color: color),
    );
  }

  Widget _buildDoneContent(AnalysisResult result) {
    // 延迟一帧再跳转，确保 UI 已渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DeckPreviewScreen(
              result: result,
              sourceText: '',
              sourceUrl: '',
              sourceImage: null,
            ),
          ),
        );
      }
    });

    return const Column(
      children: [
        SizedBox(height: 16),
        CircularProgressIndicator(color: AppColors.green),
        SizedBox(height: 16),
        Text(
          '即将进入预览...',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
