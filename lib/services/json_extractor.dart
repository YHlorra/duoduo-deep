import 'dart:convert';
import 'openai_service.dart';
import 'output_constraint.dart';

/// JSON extraction utilities for LLM output parsing.
///
/// All methods are static and pure (no global state).
class JsonExtractor {
  JsonExtractor._();

  /// Replace Chinese/smart quotes with ASCII double quotes.
  static String normalizeQuotes(String input) {
    return input
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"');
  }

  /// Find the first balanced JSON object in [input] using bracket depth counting.
  ///
  /// Returns the substring from the first `{` to its matching `}` inclusive,
  /// or `null` if no valid pair is found.
  static String? extractFirstJsonObject(String input) {
    int? start;
    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == r'\' && inString) {
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (inString) {
        continue;
      }

      if (char == '{') {
        if (depth == 0) {
          start = i;
        }
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0 && start != null) {
          return input.substring(start, i + 1);
        }
      }
    }

    return null;
  }

  /// Remove markdown code fences, keeping content from the first complete block only.
  ///
  /// Handles both ```` ```json ... ``` ```` and ```` ``` ... ``` ```` variants.
  /// If no fences are found, returns [input] unchanged.
  static String stripMarkdownFences(String input) {
    final fenceRegex = RegExp(r'```(?:json)?\r?\n([\s\S]*?)```');
    final match = fenceRegex.firstMatch(input);
    if (match == null) return input;
    return match.group(1)!.trim();
  }

  /// Repair broken JSON using a single LLM call.
  ///
  /// Pass [outputConstraint] and [schema] to structurally constrain the fix
  /// LLM. Without them the LLM may wrap its output in prose or markdown
  /// fences, and the caller's bare `jsonDecode(fixed)` will throw.
  ///
  /// Throws on any error; callers are responsible for handling failures.
  static Future<String> fixJson(
    String raw,
    String error, {
    OutputConstraintLevel? outputConstraint,
    Map<String, dynamic>? schema,
  }) async {
    final openai = OpenAIService();
    return openai.chatCompletion(
      systemPrompt:
          'You are a JSON repair tool. The following text is broken JSON. Fix it and output ONLY valid JSON, no explanation.',
      userContent: 'Broken JSON:\n$raw\n\nError: $error',
      temperature: 0.0,
      outputConstraint: outputConstraint,
      schema: schema,
    );
  }

  /// Combined parsing pipeline: normalize → strip fences → extract → decode.
  ///
  /// Returns `null` if any step fails.
  static Map<String, dynamic>? parse(String input) {
    var text = normalizeQuotes(input);
    text = stripMarkdownFences(text);
    var extracted = extractFirstJsonObject(text);

    if (extracted == null) {
      // Try without normalization in case it broke something.
      text = stripMarkdownFences(input);
      extracted = extractFirstJsonObject(text);
    }

    if (extracted == null) return null;

    try {
      return jsonDecode(extracted) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
