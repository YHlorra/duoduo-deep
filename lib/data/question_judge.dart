import 'models/question.dart';
import 'models/question_type.dart';

/// Pure judge for quiz answers. Extracted from `_QuizScreenState._checkCorrect`
/// so BDD tests can exercise the exact same code path the screen uses.
///
/// Letters in [Question.answer] (e.g. "B") are resolved via
/// [Question.resolvedAnswer] — see the getter's doc for the rationale
/// (LLM sometimes emits a letter index instead of full option text).
bool isAnswerCorrect(Question question, String answer) {
  switch (question.type) {
    case QuestionType.multipleChoice:
    case QuestionType.trueFalse:
      return answer.trim() == question.resolvedAnswer.trim();
    case QuestionType.fillBlank:
      // 去除空格和标点，忽略大小写
      return answer.trim().toLowerCase() ==
          question.answer.trim().toLowerCase();
    case QuestionType.matching:
    case QuestionType.ordering:
      // 对于匹配和排序，答案格式为 "item1-match1|item2-match2" 或 "step1|step2|step3"
      // 比较时需要规范化
      final normalize = (String s) =>
          s.split('|').map((e) => e.trim()).join('|');
      return normalize(answer) == normalize(question.answer);
  }
}