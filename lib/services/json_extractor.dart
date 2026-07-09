import 'dart:convert';
import 'openai_service.dart';
import 'output_constraint.dart';

/// JSON extraction utilities for LLM output parsing.
///
/// All methods are static and pure (no global state).
class JsonExtractor {
  JsonExtractor._();

  static const _openSmartQuote = '\u201c';  // "
  static const _closeSmartQuote = '\u201d'; // "

  /// Replace Chinese/smart quotes with ASCII double quotes.
  ///
  /// NOTE: This is a blind global replace. Prefer [extractFirstJsonObject]
  /// which only normalizes smart quotes in structural (delimiter) position,
  /// preserving smart quotes that are legitimate content inside string values.
  static String normalizeQuotes(String input) {
    return input
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"');
  }

  /// Find the first balanced JSON object in [input] using bracket depth counting.
  ///
  /// Smart-quote-aware: treats U+201C / U+201D as string delimiters when they
  /// appear in structural position (outside a string), normalizing them to
  /// ASCII `"` in the returned output. Smart quotes that appear *inside* an
  /// ASCII-delimited string value are preserved as content (not normalized),
  /// so legitimate content like `"他说"你好"了吗"` survives intact.
  ///
  /// Returns the normalized JSON object substring, or `null` if no valid
  /// pair is found.
  static String? extractFirstJsonObject(String input) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    // Which quote char opened the current string: '"' or _openSmartQuote.
    String? stringQuote;
    final buf = StringBuffer();
    bool started = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (!started) {
        // Scan for the first '{' — ignore everything before it.
        if (char == '{') {
          started = true;
          depth = 1;
          buf.write(char);
        }
        continue;
      }

      if (escaped) {
        buf.write(char);
        escaped = false;
        continue;
      }

      if (char == r'\' && inString) {
        buf.write(char);
        escaped = true;
        continue;
      }

      if (!inString) {
        if (char == '"') {
          inString = true;
          stringQuote = '"';
          buf.write(char);
        } else if (char == _openSmartQuote) {
          // Structural smart quote → normalize to ASCII.
          inString = true;
          stringQuote = _openSmartQuote;
          buf.write('"');
        } else if (char == '{') {
          depth++;
          buf.write(char);
        } else if (char == '}') {
          depth--;
          buf.write(char);
          if (depth == 0) return buf.toString();
        } else {
          buf.write(char);
        }
      } else {
        // Inside a string.
        if (stringQuote == '"' && char == '"') {
          inString = false;
          stringQuote = null;
          buf.write(char);
        } else if (stringQuote == _openSmartQuote && char == _closeSmartQuote) {
          // Closing structural smart quote → normalize to ASCII.
          inString = false;
          stringQuote = null;
          buf.write('"');
        } else {
          // Content char — smart quotes inside an ASCII string are preserved.
          buf.write(char);
        }
      }
    }

    return null;
  }

  /// Strip AI thinking tags that some models (MiniMax, etc.) prepend.
  /// Handles both closed and unclosed (truncated) thinking blocks.
  static String stripThinkingTags(String input) {
    // Remove closed <think>...</think> blocks (case-insensitive, multi-line)
    var result = input.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '').trim();
    // Remove unclosed <think> block (everything from <think> to end)
    final thinkStart = result.toLowerCase().indexOf('<think>');
    if (thinkStart != -1) {
      result = result.substring(0, thinkStart).trim();
    }
    return result;
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

  /// Combined parsing pipeline: strip fences → extract (smart-quote-aware) → decode.
  ///
  /// Returns `null` if any step fails.
  static Map<String, dynamic>? parse(String input) {
    var text = stripThinkingTags(input);
    text = stripMarkdownFences(text);
    var extracted = extractFirstJsonObject(text);

    if (extracted == null) {
      // Try on raw input in case fence stripping broke something.
      extracted = extractFirstJsonObject(input);
    }

    if (extracted == null) return null;

    try {
      return jsonDecode(extracted) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
