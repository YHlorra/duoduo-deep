import 'dart:convert';
import 'package:dio/dio.dart';
import 'openai_service.dart';
import '../data/models/question.dart';
import '../data/models/schemas/deck_schema.dart';
import 'output_constraint.dart';
import 'json_extractor.dart';
import 'log_service.dart';

/// 分析结果
class AnalysisResult {
  final String title;
  final List<Question> questions;
  final List<String> conceptNames;

  AnalysisResult({
    required this.title,
    required this.questions,
    this.conceptNames = const [],
  });
}

/// 内容拆解引擎 - 将用户输入的文本/图片/URL转化为结构化题目
class ContentAnalyzer {
  final OpenAIService _openai;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  ContentAnalyzer(this._openai);

  static const String _systemPrompt = '''你是一个专业的教育内容分析专家。你的任务是分析用户提供的文本或图片内容，提取关键知识点，生成多种类型的题目。

## 核心要求：
1. 仔细阅读/分析内容，提取 5-10 个核心知识点（记录到 concepts 数组）
2. 为每个知识点生成合适类型的题目
3. 题目类型多样化：选择题、填空题、判断题、匹配题、排序题
4. 每道题必须标注难度（difficulty）和认知层级（cognitiveLevel）
5. 难度分布建议：约 40% easy、40% medium、20% hard
6. 认知层级：knowledge（知识记忆）/ skill（理解应用）

## 题型格式说明：

### 选择题 (multiple_choice)
- options: 4个选项 ["选项A", "选项B", "选项C", "选项D"]
- answer: 正确答案的文本，必须与options中的某一项完全一致
- 选项要有迷惑性但不能有歧义

### 填空题 (fill_blank)
- answer: 正确答案的文本
- content 中用 ___ 表示空缺处

### 判断题 (true_false)
- options: ["正确", "错误"]
- answer: "正确" 或 "错误"

### 匹配题 (matching)
- match_left: 左侧条目列表 ["条目1", "条目2", "条目3"]
- match_right: 右侧条目列表（顺序打乱）["匹配A", "匹配B", "匹配C"]
- answer: 正确匹配关系，格式 "条目1-匹配A|条目2-匹配B|条目3-匹配C"
- 左右两侧数量必须相等

### 排序题 (ordering)
- options: 打乱顺序的条目列表
- answer: 正确顺序，用 | 分隔，如 "第一步|第二步|第三步"

## 输出格式（严格 JSON）：
```json
{
  "concepts": ["概念1", "概念2", "概念3"],
  "title": "题包标题（简短概括内容主题）",
  "questions": [
    {
      "type": "multiple_choice",
      "content": "题干文本",
      "difficulty": "medium",
      "cognitiveLevel": "knowledge",
      "options": ["选项A", "选项B", "选项C", "选项D"],
      "answer": "选项B",
      "explanation": "解析说明"
    },
    {
      "type": "fill_blank",
      "content": "内容中的___是什么",
      "difficulty": "easy",
      "cognitiveLevel": "knowledge",
      "answer": "正确答案",
      "explanation": "解析说明"
    },
    {
      "type": "true_false",
      "content": "判断以下说法是否正确：...",
      "difficulty": "easy",
      "cognitiveLevel": "knowledge",
      "options": ["正确", "错误"],
      "answer": "正确",
      "explanation": "解析说明"
    },
    {
      "type": "matching",
      "content": "将左侧概念与右侧解释匹配",
      "difficulty": "medium",
      "cognitiveLevel": "skill",
      "match_left": ["概念1", "概念2"],
      "match_right": ["解释A", "解释B"],
      "answer": "概念1-解释A|概念2-解释B",
      "explanation": "解析说明"
    },
    {
      "type": "ordering",
      "content": "按正确顺序排列以下步骤",
      "difficulty": "hard",
      "cognitiveLevel": "skill",
      "options": ["步骤C", "步骤A", "步骤B"],
      "answer": "步骤A|步骤B|步骤C",
      "explanation": "解析说明"
    }
  ]
}
```

## 注意事项：
- concepts 数组列出所有题目涉及的知识点名称（用于学习追踪）
- 每道题必须有 difficulty（easy/medium/hard）和 cognitiveLevel（knowledge/skill）
- question 数量 5-10，尽量包含至少 2 种题型
- title 简洁有力，概括内容主题
- 如果内容是图片，仔细识别图片中的文字和图表
- 所有文本使用中文''';

  /// 抓取 URL 内容并提取纯文本
  Future<String> _fetchUrlContent(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !['http', 'https'].contains(uri.scheme)) {
        throw Exception('仅支持 http/https 链接');
      }

      final response = await _dio.getUri<String>(
        uri,
        options: Options(
          followRedirects: true,
          maxRedirects: 3,
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      final html = response.data ?? '';
      // HTML → 纯文本：去除 script/style，strip tags，空白压缩
      var text = html
          .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .replaceAll(RegExp(r' {2,}'), ' ')
          .trim();

      // 太长截断（LLM context 留空间给 system prompt + output）
      if (text.length > 12000) {
        text = '${text.substring(0, 12000)}\n\n[内容过长，已截断]';
      }
      return text;
    } catch (e) {
      throw Exception('抓取链接失败: $e');
    }
  }

  /// 分析内容并生成题目
  /// [text] - 用户输入的文本（可选）
  /// [imageBase64] - 可选的图片(base64编码)
  /// [url] - 可选的网页链接
  Future<AnalysisResult> analyze({
    String text = '',
    String? imageBase64,
    String? url,
  }) async {
    final contentBuffer = StringBuffer();

    if (url != null && url.trim().isNotEmpty) {
      contentBuffer.writeln('--- 网页内容 ---');
      final urlContent = await _fetchUrlContent(url.trim());
      contentBuffer.writeln(urlContent);
      contentBuffer.writeln();
    }

    if (text.trim().isNotEmpty) {
      contentBuffer.writeln('--- 文本内容 ---');
      contentBuffer.writeln(text.trim());
      contentBuffer.writeln();
    }

    if (contentBuffer.isEmpty && imageBase64 == null) {
      throw Exception('请提供内容或图片');
    }

    final response = await _openai.chatCompletion(
      systemPrompt: _systemPrompt,
      userContent: imageBase64 != null
          ? '${contentBuffer.toString()}\n请同时分析上方提供的图片，识别其中的文字和图表信息。'
          : contentBuffer.toString(),
      imageBase64: imageBase64,
      temperature: 0.7,
      outputConstraint: OutputConstraintLevel.level3Strict,
      schema: deckJsonSchema,
      maxTokens: 8192,
    );

    return await _parseResponse(response);
  }

  /// 解析 GPT 返回的 JSON
  Future<AnalysisResult> _parseResponse(String response) async {
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
    for (final qJson in questionsJson) {
      try {
        final q = Question.fromJson(qJson as Map<String, dynamic>, '');
        questions.add(q);
      } catch (_) {
        // 跳过格式错误的题目
        continue;
      }
    }

    if (questions.isEmpty) {
      LogService.instance.log('parse', 'error', 'no_valid_questions', {
        'title': title,
        'rawQuestionCount': questionsJson.length,
      });
      throw Exception('AI 未生成有效题目');
    }

    return AnalysisResult(
      title: title,
      questions: questions,
      conceptNames: (json['concepts'] as List<dynamic>?)
          ?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
