import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/data/models/schemas/deck_schema.dart';

void main() {
  group('Deck schemas', () {
    test('all schema constants are valid Maps', () {
      expect(deckJsonSchema, isA<Map<String, dynamic>>());
      expect(socraticEvaluationSchema, isA<Map<String, dynamic>>());
      expect(fillBlankJudgeSchema, isA<Map<String, dynamic>>());
      expect(searchResultsSchema, isA<Map<String, dynamic>>());
    });

    test('searchResultsSchema has correct required fields', () {
      expect(searchResultsSchema['required'], equals(['concepts', 'summary']));
      final conceptDef = (searchResultsSchema['\$defs']! as Map)['concept'] as Map;
      expect(conceptDef['required'], equals(['name', 'description']));
    });

    test('deckJsonSchema question required 不含 options（连线/排序题无需 options）', () {
      final questionRequired =
          (deckJsonSchema['\$defs']! as Map)['question'] as Map;
      expect(
        questionRequired['required'],
        equals([
          'type',
          'content',
          'difficulty',
          'cognitiveLevel',
          'answer',
          'explanation',
        ]),
      );
      expect(questionRequired['required'].contains('options'), isFalse);
    });

    test('questionBatchSchema question required 同样不含 options', () {
      final questionRequired =
          (questionBatchSchema['\$defs']! as Map)['question'] as Map;
      expect(questionRequired['required'].contains('options'), isFalse);
      expect(
        questionRequired['required'],
        equals([
          'type',
          'content',
          'difficulty',
          'cognitiveLevel',
          'answer',
          'explanation',
        ]),
      );
    });

    test('match_left and match_right are in properties but not required', () {
      final question =
          (deckJsonSchema['\$defs']! as Map)['question'] as Map;
      final properties = question['properties'] as Map;
      expect(properties.containsKey('match_left'), isTrue);
      expect(properties.containsKey('match_right'), isTrue);
      expect(question['required'].contains('match_left'), isFalse);
      expect(question['required'].contains('match_right'), isFalse);
    });

    test('socraticEvaluationSchema required is understood only', () {
      expect(socraticEvaluationSchema['required'], equals(['understood']));
    });

    test('fillBlankJudgeSchema required is correct only', () {
      expect(fillBlankJudgeSchema['required'], equals(['correct']));
    });

    test('all schemas have additionalProperties false', () {
      expect(deckJsonSchema['additionalProperties'], isFalse);
      expect(socraticEvaluationSchema['additionalProperties'], isFalse);
      expect(fillBlankJudgeSchema['additionalProperties'], isFalse);
    });
  });
}
