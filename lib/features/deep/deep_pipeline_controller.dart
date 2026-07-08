import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../data/models/question.dart';
import '../../services/content_analyzer.dart';
import '../../services/json_extractor.dart';
import '../../services/openai_service.dart';
import '../../services/output_constraint.dart';
import '../../core/providers/providers.dart';
import '../../data/models/schemas/deck_schema.dart';
import 'tools/learning_goal.dart';
import 'tools/web_search_tool.dart';
import 'tools/fetch_url_tool.dart';

/// 管线阶段
enum PipelineStage {
  idle,
  searching,    // LLM 正在搜索/抓取
  generating,   // LLM 正在生成题目
  done,
  failed,
  cancelled,
}

/// 管线状态
class PipelineState {
  final PipelineStage stage;
  final String statusText;       // 当前状态描述（用户可见）
  final String? error;
  final AnalysisResult? result;
  final int toolCallCount;       // 已执行的工具调用次数

  const PipelineState({
    this.stage = PipelineStage.idle,
    this.statusText = '',
    this.error,
    this.result,
    this.toolCallCount = 0,
  });

  PipelineState copyWith({
    PipelineStage? stage,
    String? statusText,
    String? error,
    AnalysisResult? result,
    int? toolCallCount,
  }) {
    return PipelineState(
      stage: stage ?? this.stage,
      statusText: statusText ?? this.statusText,
      error: error ?? this.error,
      result: result ?? this.result,
      toolCallCount: toolCallCount ?? this.toolCallCount,
    );
  }
}

class DeepPipelineController extends StateNotifier<PipelineState> {
  final OpenAIService _openai;
  final WebSearchTool _webSearch;
  final FetchUrlTool _fetchUrl;

  DeepPipelineController(this._openai)
      : _webSearch = WebSearchTool(Dio()),
        _fetchUrl = FetchUrlTool(Dio()),
        super(const PipelineState());

  Future<void> run(LearningGoal goal) async {
    try {
      state = state.copyWith(stage: PipelineStage.searching, statusText: '正在搜索相关信息...');

      // 1. 预处理: 抓取用户提供的 URLs
      final preFetchedContent = StringBuffer();
      for (final url in goal.urls) {
        try {
          final content = await _fetchUrl.execute(url);
          preFetchedContent.writeln('--- 网页: $url ---');
          preFetchedContent.writeln(content);
          preFetchedContent.writeln();
        } catch (_) {}
      }

      if (goal.extraText.isNotEmpty) {
        preFetchedContent.writeln('--- 补充材料 ---');
        preFetchedContent.writeln(goal.extraText);
      }

      // 2. Function Calling 循环
      final systemPrompt = _buildSystemPrompt(goal);
      final userContent = _buildUserPrompt(goal, preFetchedContent.toString());

      final toolDefs = [
        WebSearchTool.toolDefinition,
        FetchUrlTool.toolDefinition,
      ];

      final result = await _openai.chatCompletionWithTools(
        systemPrompt: systemPrompt,
        userContent: userContent,
        toolDefinitions: toolDefs,
        executeTool: _executeTool,
        maxToolCalls: 5,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: deckJsonSchema,
      );

      state = state.copyWith(stage: PipelineStage.generating, statusText: '正在生成题目...');

      // 3. 解析最终 JSON
      final analysisResult = await _parseJson(result);

      state = state.copyWith(
        stage: PipelineStage.done,
        statusText: '完成！',
        result: analysisResult,
      );
    } catch (e) {
      state = state.copyWith(
        stage: PipelineStage.failed,
        error: e.toString(),
        statusText: '失败: $e',
      );
    }
  }

  Future<String> _executeTool(String name, Map<String, dynamic> args) async {
    state = state.copyWith(
      toolCallCount: state.toolCallCount + 1,
      statusText: name == 'web_search'
          ? '搜索: ${args['query'] ?? ''}'
          : '抓取: ${args['url'] ?? ''}',
    );

    if (name == 'web_search') {
      return _webSearch.execute(args['query'] as String? ?? '');
    } else if (name == 'fetch_url') {
      return _fetchUrl.execute(args['url'] as String? ?? '');
    }
    return '未知工具: $name';
  }

  String _buildSystemPrompt(LearningGoal goal) {
    final levelGuide = {
      'beginner': '用户是初学者。出题策略：基础概念、记忆类题目为主 (60% knowledge, 40% skill)，题目直接明了。',
      'advanced': '用户是高级学习者。出题策略：综合分析类题目为主 (20% knowledge, 80% skill)，增加跨概念综合题和开放性问题。',
      'intermediate': '用户是中级学习者。出题策略：理解应用类题目为主 (40% knowledge, 60% skill)。',
    }[goal.level] ?? '';

    return '''你是一位专业的教育内容专家。你的任务是帮用户生成高质量的学习题目。

## 用户背景
- 学习目的: ${goal.purpose}
- 水平: ${goal.levelLabel}
- 出题策略: $levelGuide

## 工作流程
1. 先使用 web_search 搜索相关信息（如最佳实践、常见误区、示例）
2. 如有需要，使用 fetch_url 抓取关键链接获取更多细节
3. 信息充足后，直接输出题目 JSON

## 输出格式（最终回答必须是纯 JSON）:
```json
{
  "concepts": ["概念1", "概念2"],
  "title": "题包标题",
  "questions": [
    {
      "type": "multiple_choice",
      "content": "题干",
      "difficulty": "medium",
      "cognitiveLevel": "knowledge",
      "options": ["A", "B", "C", "D"],
      "answer": "B",
      "explanation": "解析"
    }
  ]
}
```

## 规则
- 题目数量 5-10 道
- 至少 2 种题型
- 每道题必须有 difficulty (easy/medium/hard) 和 cognitiveLevel (knowledge/skill)
- concepts 数组列出所有题目涉及的知识点
- 所有文本使用中文
- 搜索时优先使用中文关键词''';
  }

  String _buildUserPrompt(LearningGoal goal, String preFetched) {
    final buf = StringBuffer();
    buf.writeln('学习目的: ${goal.purpose}');
    buf.writeln('水平: ${goal.levelLabel}');
    if (preFetched.isNotEmpty) {
      buf.writeln();
      buf.writeln('## 已有材料（先搜索补充信息，再出题）:');
      buf.writeln(preFetched);
    }
    buf.writeln();
    buf.writeln('请先搜索相关信息确保题目质量，然后生成题目。');
    return buf.toString();
  }

  Future<AnalysisResult> _parseJson(String response) async {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response) as Map<String, dynamic>;
    } catch (_) {
      final parsed = JsonExtractor.parse(response);
      if (parsed != null) {
        json = parsed;
      } else {
        // One fix attempt via LLM with structural constraint
        try {
          final fixed = await JsonExtractor.fixJson(
            response,
            'parse failed',
            outputConstraint: OutputConstraintLevel.level3Strict,
            schema: deckJsonSchema,
          );
          json = JsonExtractor.parse(fixed) ?? jsonDecode(fixed) as Map<String, dynamic>;
        } catch (_) {
          throw Exception('无法解析 AI 返回的内容');
        }
      }
    }

    final title = json['title'] as String? ?? '未命名题包';
    final questionsJson = json['questions'] as List<dynamic>? ?? [];
    final questions = <Question>[];
    for (final q in questionsJson) {
      try {
        questions.add(Question.fromJson(q as Map<String, dynamic>, ''));
      } catch (_) {}
    }
    if (questions.isEmpty) throw Exception('AI 未生成有效题目');

    return AnalysisResult(
      title: title,
      questions: questions,
      conceptNames: (json['concepts'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  void cancel() {
    state = state.copyWith(stage: PipelineStage.cancelled, statusText: '已取消');
  }

  void reset() {
    state = const PipelineState();
  }
}

// Provider
final deepPipelineProvider = StateNotifierProvider<DeepPipelineController, PipelineState>((ref) {
  return DeepPipelineController(
    ref.read(openaiServiceProvider),
  );
});
