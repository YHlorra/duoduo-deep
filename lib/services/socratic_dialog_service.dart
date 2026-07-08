import 'openai_service.dart';
import '../data/models/schemas/deck_schema.dart';
import 'json_extractor.dart';
import 'output_constraint.dart';

/// 苏格拉底式对话服务 — 答错时通过提问引导用户发现错误
class SocraticDialogService {
  final OpenAIService _openai;

  SocraticDialogService(this._openai);

  /// 生成引导提示（一次 AI 调用）
  Future<String> generateHint({
    required String questionContent,
    required String userAnswer,
    required String correctAnswer,
    required String? explanation,
  }) async {
    const systemPrompt = '''你是一位善于引导的导师。用户答错了一道题。你的任务不是直接告诉答案，而是通过提问帮助用户自己发现错误。

要求：
1. 简短一句话提问（不超过 50 字）
2. 用引导性问题让用户重新思考
3. 不要透露正确答案
4. 语气温和友善
5. 只输出问题本身，不要任何前缀或解释
6. 用中文''';

    final userContent = '题目：$questionContent\n'
        '用户的错误答案：$userAnswer\n'
        '解析参考：${explanation ?? "无"}\n\n'
        '请生成一个引导性问题（中文）：';

    try {
      final result = await _openai.chatCompletion(
        systemPrompt: systemPrompt,
        userContent: userContent,
        temperature: 0.8,
      );
      return result.trim();
    } catch (_) {
      return '让我们换个角度想：这道题的关键概念是什么？';
    }
  }

  /// 评估用户是否理解了引导问题
  Future<bool> evaluateUnderstanding({
    required String socraticHint,
    required String userResponse,
    required String originalQuestion,
    required String correctAnswer,
  }) async {
    const systemPrompt = '''你是一位评估导师。用户在接受了引导性提问后给出了回应。

判断用户的回应是否显示出理解了核心概念（不需要完美正确，只要方向对就算通过）。
输出 JSON：{"understood": true} 或 {"understood": false}
只输出 JSON，不要其他内容。''';

    final userContent = '原题：$originalQuestion\n'
        '用户的错误答案：（已记录）\n'
        '引导问题：$socraticHint\n'
        '用户回应：$userResponse\n\n'
        '用户的理解方向对吗？';

    try {
      final result = await _openai.chatCompletion(
        systemPrompt: systemPrompt,
        userContent: userContent,
        temperature: 0.3,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: socraticEvaluationSchema,
      );
      final parsed = JsonExtractor.parse(result);
      if (parsed != null) {
        return parsed['understood'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
