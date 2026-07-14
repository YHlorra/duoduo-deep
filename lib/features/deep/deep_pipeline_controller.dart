import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/question.dart';
import '../../services/content_analyzer.dart';
import '../../services/json_extractor.dart';
import '../../services/log_service.dart';
import '../../services/openai_service.dart';
import '../../services/output_constraint.dart';
import '../../core/providers/providers.dart';
import '../../data/models/schemas/deck_schema.dart';
import 'tools/learning_goal.dart';
import 'tools/web_search_tool.dart';
import 'tools/fetch_url_tool.dart';

/// Default batch size for Phase 2b question expansion.
/// Reduced automatically on truncation.
const _defaultBatchSize = 3;

/// Minimum questions to accept as a partial result.
const _minQuestionsForPartial = 3;

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

      // 检查研究阶段是否所有工具调用都失败
      if (toolLoop.toolResults.isNotEmpty &&
          toolLoop.toolResults.every((r) => r.startsWith('搜索失败') || r.startsWith('搜索服务错误') || r.startsWith('搜索无结果') || r.startsWith('搜索返回格式异常'))) {
        state = state.copyWith(
          stage: PipelineStage.failed,
          error: '研究阶段失败：所有搜索请求均无有效结果，请检查网络或换一个主题',
          statusText: '搜索失败',
        );
        return;
      }

      // 3. Phase 1.5: 概念解析 — 将搜索结果结构化转写
      state = state.copyWith(stage: PipelineStage.searching, statusText: '正在整理搜索结果...');

      String structuredKnowledge = '';
      if (toolLoop.toolResults.isNotEmpty) {
        structuredKnowledge = await _structureSearchResults(toolLoop.toolResults);
      }

      // Phase 2a: Generate question plan (small, bounded output)
      state = state.copyWith(stage: PipelineStage.generating, statusText: '正在规划题目结构...');

      final planJson = await _openai.chatCompletion(
        systemPrompt: _buildPlanSystemPrompt(goal),
        userContent: _buildPlanUserPrompt(goal, structuredKnowledge, preFetchedContent.toString()),
        temperature: 0.7,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: questionPlanSchema,
        maxTokens: 2048,
        throwOnTruncation: false,
      );

      final plan = _parsePlan(planJson);
      if (plan.isEmpty) {
        throw Exception('AI 未生成有效的题目规划');
      }

      LogService.instance.log('pipeline', 'info', 'plan_generated', {
        'planSize': plan.length,
        'goal': goal.purpose,
      });

      // Phase 2b: Expand plan into full questions (batch-by-batch, bounded)
      final allQuestions = <Question>[];
      final allConceptNames = <String>{};
      final title = _deriveTitle(plan, goal);
      var batchSize = _defaultBatchSize;
      // Track retry count per batch position to prevent infinite loops
      final retryCount = <int, int>{};

      for (var i = 0; i < plan.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, plan.length);
        final batch = plan.sublist(i, end);

        state = state.copyWith(
          stage: PipelineStage.generating,
          statusText: '正在生成题目 ${i + 1}-$end / ${plan.length}...',
        );

        final success = await _expandBatch(
          batch: batch,
          goal: goal,
          structuredKnowledge: structuredKnowledge,
          preFetched: preFetchedContent.toString(),
          batchSize: batchSize,
          onQuestions: (questions, concepts) {
            allQuestions.addAll(questions);
            allConceptNames.addAll(concepts);
          },
        );

        if (!success) {
          final retries = retryCount[i] ?? 0;
          if (batchSize > 1) {
            // Truncation: reduce batch size and retry this batch
            batchSize = batchSize - 1;
            retryCount[i] = retries + 1;
            LogService.instance.log('pipeline', 'warn', 'batch_truncated_reduce', {
              'batchIndex': i,
              'oldBatchSize': batchSize + 1,
              'newBatchSize': batchSize,
              'retry': retries + 1,
            });
            i -= batchSize;
            continue;
          } else if (retries < 2) {
            // Batch size is 1, retry same position (model may have temporary issues)
            retryCount[i] = retries + 1;
            LogService.instance.log('pipeline', 'warn', 'batch_retry', {
              'batchIndex': i,
              'retry': retries + 1,
            });
            i -= batchSize;
            continue;
          }
          // Already retried enough, skip this batch
          LogService.instance.log('pipeline', 'error', 'batch_skip', {
            'batchIndex': i,
            'retries': retries,
          });
        }
      }

      if (allQuestions.length < _minQuestionsForPartial) {
        throw Exception('仅生成 ${allQuestions.length} 道题，至少需要 $_minQuestionsForPartial 道');
      }

      final analysisResult = AnalysisResult(
        title: title,
        questions: allQuestions,
        conceptNames: allConceptNames.toList(),
      );

      state = state.copyWith(
        stage: PipelineStage.done,
        statusText: '完成！',
        result: analysisResult,
      );
    } catch (e) {
      final errorMsg = e.toString();
      // 用户友好的错误提示
      final userFriendlyError = errorMsg.contains('connection abort') ||
              errorMsg.contains('Software caused connection abort') ||
              errorMsg.contains('Connection refused') ||
              errorMsg.contains('SocketException')
          ? '网络连接中断，请检查网络后重试'
          : errorMsg.contains('DioException')
              ? '网络请求失败，请稍后重试'
              : errorMsg;
      state = state.copyWith(
        stage: PipelineStage.failed,
        error: userFriendlyError,
        statusText: '失败',
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
      final json = await _openai.chatCompletion(
        systemPrompt: '你是一位知识结构化助手。从以下搜索结果中提取核心知识点，'
            '输出 JSON：包含 concepts 数组（每个知识点有 name、description、keyPoints）'
            '和 summary（概述）。只输出 JSON，不要解释。',
        userContent: combined,
        temperature: 0.3,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: searchResultsSchema,
      );
      // ponytail: 顺手持久化概念定义到 concepts 表（DatabaseHelper 全局单例）。
      // 解析失败不阻塞 — 主流程只依赖返回的字符串喂给 Phase 2 prompt。
      _persistConceptDefinitions(json);
      return json;
    } catch (e) {
      // 结构化失败时降级：直接返回原始搜索结果文本
      return combined;
    }
  }

  /// 解析结构化 JSON 并写入 concepts 表。容错：任何异常静默跳过。
  void _persistConceptDefinitions(String jsonStr) {
    try {
      final parsed = JsonExtractor.parse(jsonStr);
      if (parsed == null) return;
      final concepts = parsed['concepts'] as List<dynamic>? ?? [];
      final db = DatabaseHelper();
      for (final c in concepts) {
        if (c is! Map<String, dynamic>) continue;
        final name = (c['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final desc = c['description'] as String?;
        final keyPoints = (c['keyPoints'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList();
        db.upsertConcept(name, description: desc, keyPoints: keyPoints);
      }
    } catch (_) {
      // 容错：持久化失败不影响主流程
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
        },
        {
          "type": "matching",
          "content": "将下列概念与对应解释连线",
          "difficulty": "medium",
          "cognitiveLevel": "skill",
          "match_left": ["概念1", "概念2", "概念3"],
          "match_right": ["解释A", "解释B", "解释C"],
          "answer": "概念1-解释A|概念2-解释B|概念3-解释C",
          "explanation": "解析"
        },
        {
          "type": "ordering",
          "content": "按正确顺序排列下列步骤",
          "difficulty": "hard",
          "cognitiveLevel": "skill",
          "options": ["步骤C", "步骤A", "步骤B"],
          "answer": "步骤A|步骤B|步骤C",
          "explanation": "解析"
        }
      ]
}
```

## 规则
- 题目数量 5-10 道
- 至少 2 种题型，且必须包含至少 1 道连线题(matching)或排序题(ordering)
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
          // Log raw response for debugging parse failures
          LogService.instance.log('parse', 'error', 'json_parse_failed', {
            'rawLength': response.length,
            'rawPreview': response.substring(0, response.length.clamp(0, 1000)),
            'rawTail': response.length > 500 ? response.substring(response.length - 500) : '',
          });
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
    if (questions.isEmpty) {
      LogService.instance.log('parse', 'error', 'no_valid_questions', {
        'title': title,
        'rawQuestionCount': questionsJson.length,
        'rawJsonPreview': json.toString().substring(0, json.toString().length.clamp(0, 500)),
      });
      throw Exception('AI 未生成有效题目');
    }

    return AnalysisResult(
      title: title,
      questions: questions,
      conceptNames: (json['concepts'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  // ============ Phase 2a: Question Plan ============

  String _buildPlanSystemPrompt(LearningGoal goal) {
    final levelGuide = {
      'beginner': '用户是初学者。出题策略：基础概念、记忆类题目为主 (60% knowledge, 40% skill)，题目直接明了。',
      'advanced': '用户是高级学习者。出题策略：综合分析类题目为主 (20% knowledge, 80% skill)，增加跨概念综合题和开放性问题。',
      'intermediate': '用户是中级学习者。出题策略：理解应用类题目为主 (40% knowledge, 60% skill)。',
    }[goal.level] ?? '';

    return '''你是一位专业的教育内容专家。根据提供的知识点和学习目标，规划一份题目结构清单。

## 学习目标
- 目的: ${goal.purpose}
- 水平: ${goal.levelLabel}
- 出题策略: $levelGuide

## 输出格式（纯 JSON）:
```json
{
  "plan": [
    {
      "type": "multiple_choice",
      "difficulty": "medium",
      "cognitiveLevel": "knowledge",
      "concept": "知识点名称",
      "briefContent": "一句话描述这道题考什么"
    }
  ]
}
```

## 规则
- 题目数量 5-8 道
- 至少 2 种题型，且必须包含至少 1 道连线题(matching)或排序题(ordering)
- briefContent 不超过 30 字
- 所有文本使用中文''';
  }

  String _buildPlanUserPrompt(LearningGoal goal, String structuredKnowledge, String preFetched) {
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
    buf.writeln('请规划题目结构清单。');
    return buf.toString();
  }

  List<Map<String, dynamic>> _parsePlan(String response) {
    final json = JsonExtractor.parse(response);
    if (json == null) {
      LogService.instance.log('parse', 'error', 'plan_parse_failed', {
        'rawLength': response.length,
        'rawPreview': response.substring(0, response.length.clamp(0, 500)),
      });
      return [];
    }
    final plan = json['plan'] as List<dynamic>?;
    if (plan == null || plan.isEmpty) return [];
    return plan.whereType<Map<String, dynamic>>().toList();
  }

  String _deriveTitle(List<Map<String, dynamic>> plan, LearningGoal goal) {
    // Use the first concept + goal purpose to derive a title
    final firstConcept = plan.first['concept'] as String? ?? '';
    if (firstConcept.isNotEmpty && goal.purpose.length <= 20) {
      return '$firstConcept · ${goal.purpose}';
    }
    return goal.purpose;
  }

  // ============ Phase 2b: Batch Expansion ============

  String _buildExpandSystemPrompt(LearningGoal goal) {
    return '''你是一位专业的教育内容专家。根据提供的题目骨架和知识点，生成完整的题目。

## 用户背景
- 学习目的: ${goal.purpose}
- 水平: ${goal.levelLabel}

## 输出格式（纯 JSON）:
```json
{
  "concepts": ["概念1", "概念2"],
      "questions": [
        {
          "type": "multiple_choice",
          "content": "题干",
          "difficulty": "medium",
          "cognitiveLevel": "knowledge",
          "options": ["A", "B", "C", "D"],
          "answer": "B",
          "explanation": "解析"
        },
        {
          "type": "matching",
          "content": "将下列概念与对应解释连线",
          "difficulty": "medium",
          "cognitiveLevel": "skill",
          "match_left": ["概念1", "概念2", "概念3"],
          "match_right": ["解释A", "解释B", "解释C"],
          "answer": "概念1-解释A|概念2-解释B|概念3-解释C",
          "explanation": "解析"
        },
        {
          "type": "ordering",
          "content": "按正确顺序排列下列步骤",
          "difficulty": "hard",
          "cognitiveLevel": "skill",
          "options": ["步骤C", "步骤A", "步骤B"],
          "answer": "步骤A|步骤B|步骤C",
          "explanation": "解析"
        }
      ]
}
```

## 规则
- 每道题必须有 difficulty (easy/medium/hard) 和 cognitiveLevel (knowledge/skill)
- explanation 不超过 2 句话
- 题型应多样化，建议包含连线题(matching)或排序题(ordering)
- 所有文本使用中文''';
  }

  String _buildExpandUserPrompt({
    required List<Map<String, dynamic>> batch,
    required String structuredKnowledge,
    required String preFetched,
  }) {
    final buf = StringBuffer();
    buf.writeln('请将以下题目骨架展开为完整题目：');
    buf.writeln();
    buf.writeln('## 题目骨架:');
    for (var i = 0; i < batch.length; i++) {
      final stub = batch[i];
      buf.writeln('${i + 1}. type=${stub['type']}, difficulty=${stub['difficulty']}, '
          'cognitiveLevel=${stub['cognitiveLevel']}, concept=${stub['concept']}, '
          'briefContent=${stub['briefContent']}');
    }
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
    buf.writeln('请生成完整题目。');
    return buf.toString();
  }

  /// Expands a batch of question stubs into full questions.
  /// Returns true on success, false if output was truncated.
  Future<bool> _expandBatch({
    required List<Map<String, dynamic>> batch,
    required LearningGoal goal,
    required String structuredKnowledge,
    required String preFetched,
    required int batchSize,
    required void Function(List<Question> questions, List<String> concepts) onQuestions,
  }) async {
    try {
      final response = await _openai.chatCompletion(
        systemPrompt: _buildExpandSystemPrompt(goal),
        userContent: _buildExpandUserPrompt(
          batch: batch,
          structuredKnowledge: structuredKnowledge,
          preFetched: preFetched,
        ),
        temperature: 0.7,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: questionBatchSchema,
        maxTokens: 4096,
        throwOnTruncation: false,
      );

      // Check if truncated by looking for finish_reason in response
      // Since we can't easily get finish_reason from the string response,
      // we try to parse and check if we got fewer questions than expected
      final json = JsonExtractor.parse(response);
      if (json == null) {
        LogService.instance.log('parse', 'error', 'batch_parse_failed', {
          'batchSize': batchSize,
          'rawLength': response.length,
          'rawPreview': response.substring(0, response.length.clamp(0, 500)),
        });
        return false;
      }

      final questionsJson = json['questions'] as List<dynamic>? ?? [];
      final concepts = (json['concepts'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final questions = <Question>[];
      for (final q in questionsJson) {
        try {
          questions.add(Question.fromJson(q as Map<String, dynamic>, ''));
        } catch (_) {}
      }

      // If we got fewer questions than the batch size, likely truncated
      if (questions.length < batch.length && batchSize > 1) {
        LogService.instance.log('pipeline', 'warn', 'batch_partial_truncated', {
          'expected': batch.length,
          'got': questions.length,
        });
        return false;
      }

      onQuestions(questions, concepts);
      return true;
    } catch (e) {
      LogService.instance.log('pipeline', 'error', 'batch_expand_error', {
        'error': e.toString(),
        'batchSize': batchSize,
      });
      return false;
    }
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
