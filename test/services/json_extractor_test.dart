import 'package:flutter_test/flutter_test.dart';
import 'package:dlg_q/services/json_extractor.dart';

void main() {
  group('JsonExtractor', () {
    group('normalizeQuotes', () {
      test('replaces Chinese quotes with ASCII', () {
        expect(JsonExtractor.normalizeQuotes('\u201chello\u201d'), '"hello"');
      });

      test('leaves ASCII quotes unchanged', () {
        expect(JsonExtractor.normalizeQuotes('"hello"'), '"hello"');
      });

      test('handles mixed quotes', () {
        expect(JsonExtractor.normalizeQuotes('\u201cfoo\u201d and "bar"'),
            '"foo" and "bar"');
      });
    });

    group('extractFirstJsonObject', () {
      test('extracts normal JSON', () {
        final input = 'prefix {"a":1} suffix';
        expect(JsonExtractor.extractFirstJsonObject(input), '{"a":1}');
      });

      test('extracts nested objects', () {
        final input = 'data {"a":{"b":1}} end';
        expect(JsonExtractor.extractFirstJsonObject(input), '{"a":{"b":1}}');
      });

      test('extracts JSON with prose around it', () {
        final input =
            'Here is the result: {"status":"ok","value":42} Thanks!';
        expect(
            JsonExtractor.extractFirstJsonObject(input),
            '{"status":"ok","value":42}');
      });

      test('returns null when no { present', () {
        expect(JsonExtractor.extractFirstJsonObject('no json here'), isNull);
      });

      test('returns null for unbalanced brackets', () {
        expect(JsonExtractor.extractFirstJsonObject('{"a":1'), isNull);
      });

      test('handles escaped quotes inside strings', () {
        final input = '{"text":"say \\"hi\\""}';
        expect(JsonExtractor.extractFirstJsonObject(input), '{"text":"say \\"hi\\""}');
      });
    });

    group('stripMarkdownFences', () {
      test('strips ```json fences', () {
        final input = '```json\n{"a":1}\n```';
        expect(JsonExtractor.stripMarkdownFences(input), '{"a":1}');
      });

      test('strips plain ``` fences', () {
        final input = '```\n{"a":1}\n```';
        expect(JsonExtractor.stripMarkdownFences(input), '{"a":1}');
      });

      test('returns input unchanged when no fences', () {
        final input = '{"a":1}';
        expect(JsonExtractor.stripMarkdownFences(input), input);
      });

      test('handles CRLF line endings', () {
        final input = '```json\r\n{"a":1}\r\n```';
        expect(JsonExtractor.stripMarkdownFences(input), '{"a":1}');
      });
    });

    group('parse', () {
      test('parses valid JSON', () {
        expect(JsonExtractor.parse('{"a":1}'), {'a': 1});
      });

      test('parses prose + JSON mix', () {
        expect(JsonExtractor.parse('Result: {"a":1}'), {'a': 1});
      });

      test('parses markdown fence + JSON', () {
        expect(JsonExtractor.parse('```json\n{"a":1}\n```'), {'a': 1});
      });

      test('returns null for pure prose', () {
        expect(JsonExtractor.parse('There is no JSON here.'), isNull);
      });
    });
  });
}
