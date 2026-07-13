import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/services/socratic_dialog_service.dart';
import 'package:dlg_q/services/openai_service.dart';
import 'package:dlg_q/services/output_constraint.dart';

/// 轻量 fake：让 chatCompletion 返回预设文本，不经过真实网络。
class _FakeOpenAIService extends OpenAIService {
  final String response;
  _FakeOpenAIService(this.response);

  @override
  Future<String> chatCompletion({
    required String systemPrompt,
    required String userContent,
    String? imageBase64,
    double? temperature,
    OutputConstraintLevel? outputConstraint,
    Map<String, dynamic>? schema,
    int maxTokens = 4096,
    bool throwOnTruncation = true,
  }) async =>
      response;
}

void main() {
  group('SocraticDialogService.generateHint', () {
    test('strips <think> reasoning blocks leaked by the model', () async {
      // 复现 bug：模型把内部思考也吐了出来
      const leaked =
          '<think>用户选了 A，但其实...\n让我再想想答案</think>你觉得这道题的核心概念是什么？';
      final service = SocraticDialogService(_FakeOpenAIService(leaked));

      final hint = await service.generateHint(
        questionContent: '1+1=?',
        userAnswer: '3',
        correctAnswer: '2',
        explanation: null,
      );

      expect(hint.contains('<think>'), isFalse);
      expect(hint.contains('用户选了 A'), isFalse);
      expect(hint, contains('核心概念'));
    });

    test('returns plain output unchanged when no think block present', () async {
      const clean = '换个角度想：你是怎么得出这个答案的？';
      final service = SocraticDialogService(_FakeOpenAIService(clean));

      final hint = await service.generateHint(
        questionContent: '1+1=?',
        userAnswer: '3',
        correctAnswer: '2',
        explanation: null,
      );

      expect(hint, equals(clean));
    });

    test('falls back to default hint when model output is only think content', () async {
      const onlyThink = '<think>Let me reason step by step...</think>';
      final service = SocraticDialogService(_FakeOpenAIService(onlyThink));

      final hint = await service.generateHint(
        questionContent: '1+1=?',
        userAnswer: '3',
        correctAnswer: '2',
        explanation: null,
      );

      expect(hint, isNotEmpty);
      expect(hint.contains('<think>'), isFalse);
    });
  });
}
