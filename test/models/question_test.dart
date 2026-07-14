import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/data/models/question.dart';
import 'package:dlg_q/data/models/question_type.dart';

void main() {
  group('Question.fromJson (题型多样性)', () {
    test('matching 题无 options 可正确解析且不崩', () {
      final json = {
        'type': 'matching',
        'content': '将概念与对应解释连线',
        'difficulty': 'medium',
        'cognitiveLevel': 'skill',
        'match_left': ['概念1', '概念2'],
        'match_right': ['解释A', '解释B'],
        'answer': '概念1-解释A|概念2-解释B',
        'explanation': '解析',
      };
      final q = Question.fromJson(json, 'deck_1');
      expect(q.type, QuestionType.matching);
      expect(q.matchLeft, ['概念1', '概念2']);
      expect(q.matchRight, ['解释A', '解释B']);
      expect(q.options, isEmpty);
      expect(q.answer, '概念1-解释A|概念2-解释B');
    });

    test('ordering 题 options 为打乱顺序、answer 为正确顺序', () {
      final json = {
        'type': 'ordering',
        'content': '按正确顺序排列下列步骤',
        'difficulty': 'hard',
        'cognitiveLevel': 'skill',
        'options': ['步骤C', '步骤A', '步骤B'],
        'answer': '步骤A|步骤B|步骤C',
        'explanation': '解析',
      };
      final q = Question.fromJson(json, 'deck_1');
      expect(q.type, QuestionType.ordering);
      expect(q.options, ['步骤C', '步骤A', '步骤B']);
      expect(q.answer, '步骤A|步骤B|步骤C');
    });

    test('选择题缺失 options 时兜底为空数组而不崩', () {
      final json = {
        'type': 'multiple_choice',
        'content': '题干',
        'difficulty': 'easy',
        'cognitiveLevel': 'knowledge',
        'answer': 'A',
        'explanation': '解析',
      };
      final q = Question.fromJson(json, 'deck_1');
      expect(q.type, QuestionType.multipleChoice);
      expect(q.options, isEmpty);
    });
  });
}
