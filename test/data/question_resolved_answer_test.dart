// Regression test for the multi-choice judging bug:
// LLM sometimes emits `answer` as a letter index ("B") instead of the full
// option text. `Question.resolvedAnswer` must resolve the letter back to the
// matching option so the judge (`_checkCorrect` in quiz_screen.dart) and the
// "correct answer" highlighting in widgets and deck preview work consistently.

import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/data/models/question.dart';
import 'package:dlg_q/data/models/question_type.dart';

Question _mc({required String answer, required List<String> options}) {
  return Question(
    id: 'q1',
    deckId: 'd1',
    type: QuestionType.multipleChoice,
    content: '题干',
    options: options,
    answer: answer,
  );
}

void main() {
  group('Question.resolvedAnswer (regression: LLM letter vs full text)', () {
    test('letter "B" resolves to options[1]', () {
      final q = _mc(
        answer: 'B',
        options: ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
      );
      expect(q.resolvedAnswer, '声明式链式调用');
    });

    test('full option text passes through unchanged', () {
      final q = _mc(
        answer: '声明式链式调用',
        options: ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
      );
      expect(q.resolvedAnswer, '声明式链式调用');
    });

    test('lowercase letter "c" resolves (case-insensitive)', () {
      final q = _mc(
        answer: 'c',
        options: ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
      );
      expect(q.resolvedAnswer, '用户界面渲染');
    });

    test('letter with surrounding whitespace is trimmed', () {
      final q = _mc(
        answer: '  B  ',
        options: ['A1', 'A2', 'A3'],
      );
      expect(q.resolvedAnswer, 'A2');
    });

    test('letter out of range falls back to raw answer', () {
      final q = _mc(
        answer: 'E',
        options: ['A1', 'A2'],
      );
      expect(q.resolvedAnswer, 'E');
    });

    test('empty answer returns empty', () {
      final q = _mc(answer: '', options: ['A1', 'A2']);
      expect(q.resolvedAnswer, '');
    });

    test('true_false: letter resolves against ["正确", "错误"]', () {
      final q = Question(
        id: 'q1',
        deckId: 'd1',
        type: QuestionType.trueFalse,
        content: '题干',
        options: const ['正确', '错误'],
        answer: 'A',
      );
      expect(q.resolvedAnswer, '正确');
    });

    test('true_false: full text passes through', () {
      final q = Question(
        id: 'q1',
        deckId: 'd1',
        type: QuestionType.trueFalse,
        content: '题干',
        options: const ['正确', '错误'],
        answer: '错误',
      );
      expect(q.resolvedAnswer, '错误');
    });

    test('non multi-choice type: passes through even if letter-shaped', () {
      final q = Question(
        id: 'q1',
        deckId: 'd1',
        type: QuestionType.fillBlank,
        content: '题干 ___',
        answer: 'B',
      );
      expect(q.resolvedAnswer, 'B');
    });

    test('multi-choice with empty options: passes through', () {
      final q = Question(
        id: 'q1',
        deckId: 'd1',
        type: QuestionType.multipleChoice,
        content: '题干',
        options: const [],
        answer: 'B',
      );
      expect(q.resolvedAnswer, 'B');
    });
  });
}