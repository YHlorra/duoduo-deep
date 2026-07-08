import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/core/providers/providers.dart';

/// Regression guard for the random-mode empty-state bug.
///
/// When `DeckOperations.saveAnalysisResult` writes a new deck + questions
/// to SQLite, it MUST invalidate BOTH `deckListProvider` AND
/// `allQuestionsProvider`. The home screen's random-mode entry watches
/// `allQuestionsProvider`; if it's not invalidated on save, the cache
/// stays as the initial `[]` and the user sees the empty state even
/// after creating decks.
///
/// This test fails if someone removes either of the paired invalidations.
void main() {
  group('cache invalidation pairing (regression: random-mode empty state)', () {
    test('allQuestionsProvider is defined as a FutureProvider', () {
      // Sanity: the data source must exist for the test below to be meaningful.
      expect(allQuestionsProvider, isNotNull);
      // ignore: invalid_use_of_protected_member
      expect(allQuestionsProvider.future, isNotNull);
    });

    test('saveAnalysisResult invalidates both deck + question providers', () async {
      // Read the source statically; verifying a behavior change would require
      // mocking sqflite, which the codebase doesn't currently do.
      final source = await _readSource('lib/core/providers/providers.dart');
      // Locate the saveAnalysisResult method body.
      final start = source.indexOf('Future<String> saveAnalysisResult');
      expect(start, greaterThan(0), reason: 'saveAnalysisResult not found');
      final nextMethod = source.indexOf('// =====', start + 1);
      final body = source.substring(
        start,
        nextMethod > 0 ? nextMethod : source.length,
      );
      expect(
        body.contains('_ref.invalidate(deckListProvider)'),
        isTrue,
        reason: 'deckListProvider must be invalidated after save',
      );
      expect(
        body.contains('_ref.invalidate(allQuestionsProvider)'),
        isTrue,
        reason:
            'allQuestionsProvider MUST also be invalidated, otherwise random-mode '
            'home keeps showing empty state. See docs/investigation-format-exception-20260708.md '
            'and the cache-pair pattern added 2026-07-08.',
      );
    });
  });
}

Future<String> _readSource(String relativePath) async {
  // Tests run with CWD = project root in flutter_test.
  return io.File(relativePath).readAsString();
}
