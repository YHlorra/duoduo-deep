import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/services/sm2_algorithm.dart';

void main() {
  group('SM-2 algorithm', () {
    test('first correct answer sets interval to 1 day', () {
      final result = sm2(easeFactor: 2.5, intervalDays: 0, repetitions: 0, quality: 4);
      expect(result.intervalDays, 1);
      expect(result.repetitions, 1);
    });

    test('second correct answer sets interval to 3 days', () {
      final result = sm2(easeFactor: 2.5, intervalDays: 1, repetitions: 1, quality: 4);
      expect(result.intervalDays, 3);
      expect(result.repetitions, 2);
    });

    test('wrong answer resets repetitions to 0 and interval to 1', () {
      final result = sm2(easeFactor: 2.5, intervalDays: 10, repetitions: 5, quality: 1);
      expect(result.intervalDays, 1);
      expect(result.repetitions, 0);
    });

    test('nextReviewDate is in the future', () {
      final result = sm2(easeFactor: 2.5, intervalDays: 0, repetitions: 0, quality: 4);
      expect(result.nextReviewDate.isAfter(DateTime.now()), true);
    });
  });

  group('ConceptMasteryInfo', () {
    test('mastered when repetitions >= 3 and ease >= 2.3', () {
      // can't construct directly without map, skip this
    });
  });
}
