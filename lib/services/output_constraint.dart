import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

/// Output constraint levels for structured output support.
enum OutputConstraintLevel {
  /// Provider supports strict JSON Schema (response_format json_schema).
  level3Strict,
  /// Provider supports json_object response_format.
  level2Json,
  /// Provider has no structured output support; rely on prompt engineering.
  level1Prompt,
}

/// Detects provider capability for structured output.
class ProviderCapability {
  static const _probeSchema = <String, dynamic>{
    'type': 'object',
    'properties': {'x': {'type': 'string'}},
    'required': ['x'],
    'additionalProperties': false,
  };

  static final Map<String, OutputConstraintLevel> _cache = {};
  static Completer<OutputConstraintLevel>? _inFlight;
  static OutputConstraintLevel? _forcedLevel;

  static void forceLevel(OutputConstraintLevel level) {
    _forcedLevel = level;
  }

  /// Reset static state for testing. Does NOT affect production behavior.
  static void resetForTest() {
    _forcedLevel = null;
    _cache.clear();
    _inFlight = null;
  }

  static Future<OutputConstraintLevel> detect(
    String baseUrl,
    String model,
    String apiKey,
  ) async {
    if (_forcedLevel != null) return _forcedLevel!;

    final key = '$baseUrl::$model';
    final cached = _cache[key];
    if (cached != null) return cached;

    if (_inFlight != null) return _inFlight!.future;

    _inFlight = Completer<OutputConstraintLevel>();
    final level = await _probe(baseUrl, model, apiKey);
    _cache[key] = level;
    _inFlight!.complete(level);
    _inFlight = null;
    return level;
  }

  static Future<OutputConstraintLevel> _probe(
    String baseUrl,
    String model,
    String apiKey,
  ) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    // Step 1: Try strict JSON Schema
    try {
      final response = await dio.post(
        '$baseUrl/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': 'Return {"x":"ok"}'},
          ],
          'temperature': 0,
          'max_tokens': 10,
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'probe',
              'strict': true,
              'schema': _probeSchema,
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;
          if (content != null) {
            final decoded = _safeJsonDecode(content);
            if (decoded is Map && decoded.containsKey('x')) {
              return OutputConstraintLevel.level3Strict;
            }
          }
        }
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && (status == 400 || status == 422)) {
        // Fall through to step 2
      } else {
        return OutputConstraintLevel.level1Prompt;
      }
    }

    // Step 2: Try json_object
    try {
      final response = await dio.post(
        '$baseUrl/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': 'Return {"x":"ok"}'},
          ],
          'temperature': 0,
          'max_tokens': 10,
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;
          if (content != null) {
            final decoded = _safeJsonDecode(content);
            if (decoded is Map && decoded.containsKey('x')) {
              return OutputConstraintLevel.level2Json;
            }
          }
        }
      }
    } on DioException catch (_) {
      // Fall through
    }

    return OutputConstraintLevel.level1Prompt;
  }

  static dynamic _safeJsonDecode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }
}
