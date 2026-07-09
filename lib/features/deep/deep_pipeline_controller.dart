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

      // 2. Phase 1: 研究阶段 — 工具循环，收集搜索结果
      final researchSystemPrompt = _buildResearchSystemPrompt(goal);
      final researchUserContent = _buildResearchUserPrompt(goal, preFetchedContent.toString());

      final toolDefs = [
        WebSearchTool.toolDefinition,
        FetchUrlTool.toolDefinition,
      ];

      final toolLoop = await _openai.chatCompletionWithTools(
        systemPrompt: researchSystemPrompt,
        userContent: researchUserContent,
        toolDefinitions: toolDefs,
        executeTool: _executeTool,
        maxToolCalls: 5,
      );

      // 若 provider 不支持工具，chatCompletionWithTools 已降级为普通 chatCompletion，
      // finalContent 已是 schema 约束的 deck JSON，直接解析。
      if (!toolLoop.toolsSupported) {
        state = state.copyWith(stage: PipelineStage.generating, statusText: '正在生成题目...');
        final analysisResult = await _parseJson(toolLoop.finalContent ?? '');
        state = state.copyWith(
          stage: PipelineStage.done,
          statusText: '完成！',
          result: analysisResult,
        );
        return;
      }

      // 3. Phase 1.5: 概念解析 — 将搜索结果结构化转写
      state = state.copyWith(stage: PipelineStage.searching, statusText: '正在整理搜索结果...');

      String structuredKnowledge = '';
      if (toolLoop.toolResults.isNotEmpty) {
        structuredKnowledge = await _structureSearchResults(toolLoop.toolResults);
      }

      // 4. Phase 2: 生成阶段 — 用结构化知识点 + 学习目标生成 deck
      state = state.copyWith(stage: PipelineStage.generating, statusText: '正在生成题目...');

      final generationSystemPrompt = _buildGenerationSystemPrompt(goal);
      final generationUserContent = _buildGenerationUserPrompt(
        goal, structuredKnowledge, preFetchedContent.toString(),
      );

      final deckJson = await _openai.chatCompletion(
        systemPrompt: generationSystemPrompt,
        userContent: generationUserContent,
        temperature: 0.7,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: deckJsonSchema,
        maxTokens: 8192,
      );

      final analysisResult = await _parseJson(deckJson);

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

  /// Phase 1.5: 概念解析 — 将原始搜索结果结构化转写为知识点 JSON。
  ///
  /// 输入: 工具循环收集的原始搜索结果文本列表
  /// 输出: 结构化知识点 JSON (concepts + summary)，喂给 Phase 2 生成调用
  Future<String> _structureSearchResults(List<String> rawResults) async {
    final combined = rawResults.join('\n\n---\n\n');

    try {
      return await _openai.chatCompletion(
        systemPrompt: '你是一位知识结构化助手。从以下搜索结果中提取核心知识点，'
            '输出 JSON：包含 concepts 数组（每个知识点有 name、description、keyPoints）'
            '和 summary（概述）。只输出 JSON，不要解释。',
        userContent: combined,
        temperature: 0.3,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: searchResultsSchema,
      );
    } catch (e) {
      // 结构化失败时降级：直接返回原始搜索结果文本
      return combined;
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

  /// Phase 1 研究阶段的 system prompt — 只负责搜索，不负责出题。
  String _buildResearchSystemPrompt(LearningGoal goal) {
    return '''你是一位信息研究助手。你的任务是搜索和收集与以下学习目标相关的信息。

## 学习目标
- 目的: ${goal.purpose}
- 水平: ${goal.levelLabel}

## 工作流程
1. 使用 web_search 搜索相关概念、最佳实践、示例
2. 如有需要，使用 fetch_url 抓取关键链接获取更多细节
3. 信息充足后停止搜索

你不需要生成题目，只需要搜索和收集信息。''';
  }

  /// Phase 1 研究阶段的 user prompt
  String _buildResearchUserPrompt(LearningGoal goal, String preFetched) {
    final buf = StringBuffer();
    buf.writeln('学习目的: ${goal.purpose}');
    buf.writeln('水平: ${goal.levelLabel}');
    if (preFetched.isNotEmpty) {
      buf.writeln();
      buf.writeln('## 已有材料:');
      buf.writeln(preFetched);
    }
    buf.writeln();
    buf.writeln('请搜索相关信息，确保覆盖该主题的核心知识点。');
    return buf.toString();
  }

  /// Phase 2 生成阶段的 system prompt — 只负责出题，schema 从一开始就强制。
  String _buildGenerationSystemPrompt(LearningGoal goal) {
    final levelGuide = {
      'beginner': '用户是初学者。出题策略：基础概念、记忆类题目为主 (60% knowledge, 40% skill)，题目直接明了。',
      'advanced': '用户是高级学习者。出题策略：综合分析类题目为主 (20% knowledge, 80% skill)，增加跨概念综合题和开放性问题。',
      'intermediate': '用户是中级学习者。出题策略：理解应用类题目为主 (40% knowledge, 60% skill)。',
    }[goal.level] ?? '';

    return '''你是一位专业的教育内容专家。根据提供的结构化知识点和学习目标，生成高质量的学习题目。

## 用户背景
- 学习目的: ${goal.purpose}
- 水平: ${goal.levelLabel}
- 出题策略: $levelGuide

## 输出格式（纯 JSON）:
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
- 所有文本使用中文''';
  }

  /// Phase 2 生成阶段的 user prompt — 结构化知识点 + 学习目标 + 已有材料
  String _buildGenerationUserPrompt(LearningGoal goal, String structuredKnowledge, String preFetched) {
    final buf = StringBuffer();
    buf.writeln('学习目的: ${goal.purpose}');
    buf.writeln('水平: ${goal.levelLabel}');
    buf.writeln();
    if (structuredKnowledge.isNotEmpty) {
      buf.writeln('## 结构化知识点（来自搜索）:');
      buf.writeln(structuredKnowledge);
      buf.writeln();
    }
    if (preFetched.isNotEmpty) {
      buf.writeln('## 已有材料:');
      buf.writeln(preFetched);
      buf.writeln();
    }
    buf.writeln('请根据以上信息生成题目。');
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
