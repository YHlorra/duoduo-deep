// BDD-style regression tests for the multi-choice judging bug.
//
// Mirror of the user-visible screenshot scenario:
//   - LLM emits `answer` as a letter index ("B") sometimes
//   - User taps the correct option (full text in options[i])
//   - System must mark CORRECT, not WRONG
//
// Prior code (`answer.trim() == question.answer.trim()`) would compare
// "声明式链式调用" against "B" and always return false. After the fix, the
// judge resolves letters via Question.resolvedAnswer (which delegates from
// the pure isAnswerCorrect function in lib/data/question_judge.dart).
//
// Each test uses Given/When/Then to make the scenario read like a spec.

import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/data/models/question.dart';
import 'package:dlg_q/data/models/question_type.dart';
import 'package:dlg_q/data/question_judge.dart';

Question _q({
  required QuestionType type,
  required String answer,
  List<String> options = const [],
  String id = 'q1',
}) {
  return Question(
    id: id,
    deckId: 'd1',
    type: type,
    content: '题干',
    options: options,
    answer: answer,
  );
}

void main() {
  // ===========================================================================
  // Feature: multi-choice judging tolerates LLM letter-index answers
  // ===========================================================================

  group('Feature: multi-choice judging (LLM letter vs full text)', () {
    // ------------------------------------------------------------------
    // Scenario 1 (the original bug): user taps correct option while LLM
    // emitted a letter index. Pre-fix would mark WRONG. Post-fix: CORRECT.
    // ------------------------------------------------------------------
    test(
      'Scenario 1 [regression]: tapping correct option "声明式链式调用" when '
      'LLM emitted answer="B" → CORRECT',
      () {
        // Given a multi-choice question whose JSON the LLM emitted as a letter
        final question = _q(
          type: QuestionType.multipleChoice,
          options: const ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
          answer: 'B',
        );

        // Sanity witness: the data still carries the letter form (this is
        // exactly what the prior code compared against, and that comparison
        // returned false because "声明式链式调用" != "B").
        expect(question.answer, 'B',
            reason: 'raw answer should still be the letter index '
                '(the helper bridges the gap, it does not rewrite history)');

        // When the user taps option B (the full-text option)
        final isCorrect =
            isAnswerCorrect(question, '声明式链式调用');

        // Then the judge returns true
        expect(isCorrect, isTrue,
            reason: 'clicking the correct option must register as CORRECT '
                'even when the LLM stored its answer as a letter index');
      },
    );

    // ------------------------------------------------------------------
    // Scenario 2: the fix does NOT make wrong answers look right.
    // ------------------------------------------------------------------
    test(
      'Scenario 2: tapping wrong option while LLM emitted answer="B" → WRONG',
      () {
        // Given a multi-choice question, LLM emitted answer="B"
        final question = _q(
          type: QuestionType.multipleChoice,
          options: const ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
          answer: 'B',
        );

        // When the user taps option A (wrong)
        final isCorrect = isAnswerCorrect(question, '数据库连接');

        // Then the judge returns false
        expect(isCorrect, isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Scenario 3: full-text answers (the "good" path) still work.
    // ------------------------------------------------------------------
    test(
      'Scenario 3: LLM emitted full text, user taps matching option → CORRECT',
      () {
        // Given a question whose `answer` is already the full option text
        final question = _q(
          type: QuestionType.multipleChoice,
          options: const ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
          answer: '声明式链式调用',
        );

        // When the user taps that exact option
        final isCorrect =
            isAnswerCorrect(question, '声明式链式调用');

        // Then CORRECT (no regression on the well-formed path)
        expect(isCorrect, isTrue);
      },
    );

    // ------------------------------------------------------------------
    // Scenario 4: lowercase letter resolves (case-insensitive).
    // ------------------------------------------------------------------
    test(
      'Scenario 4: LLM emitted lowercase letter "c" → CORRECT on third option',
      () {
        final question = _q(
          type: QuestionType.multipleChoice,
          options: const ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
          answer: 'c',
        );
        expect(isAnswerCorrect(question, '用户界面渲染'), isTrue);
      },
    );

    // ------------------------------------------------------------------
    // Scenario 5: letter outside the options range stays WRONG.
    // ------------------------------------------------------------------
    test(
      'Scenario 5: LLM emitted letter "E" with only 2 options → no false '
      'positive, wrong option stays WRONG',
      () {
        final question = _q(
          type: QuestionType.multipleChoice,
          options: const ['选项1', '选项2'],
          answer: 'E',
        );
        // resolvedAnswer cannot map E → option, so it stays "E"; no option
        // matches "E" → correct behavior is to return false.
        expect(isAnswerCorrect(question, '选项1'), isFalse);
        expect(isAnswerCorrect(question, '选项2'), isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Scenario 6: true/false with letter "B" and options=["正确","错误"]
    // ------------------------------------------------------------------
    test(
      'Scenario 6: true/false letter B against ["正确","错误"] → CORRECT on "错误"',
      () {
        final question = _q(
          type: QuestionType.trueFalse,
          options: const ['正确', '错误'],
          answer: 'B',
        );
        expect(isAnswerCorrect(question, '错误'), isTrue);
        expect(isAnswerCorrect(question, '正确'), isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Scenario 7: fill-blank unchanged (case-insensitive trim).
    // ------------------------------------------------------------------
    test(
      'Scenario 7: fill_blank case-insensitive trim still works → CORRECT',
      () {
        final question = _q(
          type: QuestionType.fillBlank,
          answer: 'Paris',
        );
        expect(isAnswerCorrect(question, '  paris  '), isTrue);
        expect(isAnswerCorrect(question, 'London'), isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Scenario 8: matching/ordering pipe-format unchanged.
    // ------------------------------------------------------------------
    test(
      'Scenario 8: matching pipe format still correct',
      () {
        final question = _q(
          type: QuestionType.matching,
          answer: '条目1-匹配A|条目2-匹配B',
        );
        expect(isAnswerCorrect(question, '条目1-匹配A | 条目2-匹配B'), isTrue);
        expect(isAnswerCorrect(question, '条目2-匹配B|条目1-匹配A'), isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Bug-shape witness: without the fix, the original equality would fail.
    // We re-create the OLD comparison here to assert it really would fail,
    // so the BDD suite documents both the bug AND the fix.
    // ------------------------------------------------------------------
    test(
      'Bug-shape witness: pre-fix code would have returned false on this input',
      () {
        final question = _q(
          type: QuestionType.multipleChoice,
          options: const ['数据库连接', '声明式链式调用', '用户界面渲染', '模型训练'],
          answer: 'B',
        );
        // The pre-fix code lived at quiz_screen.dart:152 and did:
        //     answer.trim() == question.answer.trim();
        final wouldHaveBeenPreFixResult =
            '声明式链式调用'.trim() == question.answer.trim();

        expect(wouldHaveBeenPreFixResult, isFalse,
            reason: 'pre-fix code wrongly returned false here, that is the '
                'bug — isAnswerCorrect must return true (proven above)');
      },
    );
  });
}