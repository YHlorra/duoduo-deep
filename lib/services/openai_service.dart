import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';
import 'output_constraint.dart';
import 'json_extractor.dart';
import '../data/models/schemas/deck_schema.dart';

  /// Extracts the message content from an API response.
  /// Returns content regardless of finish_reason. Caller must check
  /// [Response] separately if truncation detection is needed.
  String _extractContent(Response response) {
    final data = response.data as Map<String, dynamic>;
    final choices = data['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('API 返回空结果');
    }
    final choice = choices[0] as Map<String, dynamic>;
    return choice['message']['content'] as String;
  }

  /// Extracts content and reports whether the output was truncated.
  ({String content, bool truncated}) _extractContentWithTruncation(Response response) {
    final data = response.data as Map<String, dynamic>;
    final choices = data['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('API 返回空结果');
    }
    final choice = choices[0] as Map<String, dynamic>;
    final finishReason = choice['finish_reason'] as String?;
    final content = choice['message']['content'] as String;
    return (content: content, truncated: finishReason == 'length');
  }

/// 判断是否为可重试的瞬时网络错误（无 response 或连接层错误）
bool _isTransientDioError(DioException e) {
  if (e.response != null) return false; // 有 HTTP 响应 → 非瞬时
  return e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.unknown;
}

/// 带指数退避的重试包装器。仅重试瞬时网络错误。
Future<T> _retryWithBackoff<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  String? operationName,
}) async {
  DioException? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } on DioException catch (e) {
      if (!_isTransientDioError(e)) rethrow;
      lastError = e;
      if (attempt < maxAttempts) {
        final delayMs = pow(2, attempt - 1).toInt() * 1000;
        LogService.instance.log(
          operationName ?? 'retry',
          'warn',
          'transient_error_retry',
          {
            'attempt': attempt,
            'maxAttempts': maxAttempts,
            'delayMs': delayMs,
            'error': e.message ?? e.type.toString(),
          },
        );
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }
  throw lastError!;
}

/// AI 厂商预设
class AIProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final List<String> models;
  final String keyHelpUrl;
  final String keyHint;

  const AIProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.models,
    required this.keyHelpUrl,
    required this.keyHint,
  });
}

/// 内置 AI 厂商列表
class AIProviders {
  static const List<AIProviderPreset> builtin = [
    AIProviderPreset(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      models: ['gpt-4o-mini', 'gpt-4o', 'gpt-4-turbo'],
      keyHelpUrl: 'https://platform.openai.com/api-keys',
      keyHint: 'sk-...',
    ),
    AIProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      models: ['deepseek-chat', 'deepseek-reasoner'],
      keyHelpUrl: 'https://platform.deepseek.com/api_keys',
      keyHint: 'sk-...',
    ),
    AIProviderPreset(
      id: 'qwen',
      name: '通义千问 (百炼)',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      models: ['qwen-turbo', 'qwen-plus', 'qwen-max'],
      keyHelpUrl: 'https://bailian.console.aliyun.com/?apiKey=1',
      keyHint: 'sk-...',
    ),
    AIProviderPreset(
      id: 'moonshot',
      name: '月之暗面 (Kimi)',
      baseUrl: 'https://api.moonshot.cn/v1',
      models: ['moonshot-v1-8k', 'moonshot-v1-32k', 'moonshot-v1-128k'],
      keyHelpUrl: 'https://platform.moonshot.cn/console/api-keys',
      keyHint: 'sk-...',
    ),
    AIProviderPreset(
      id: 'zhipu',
      name: '智谱 AI',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      models: ['glm-4-flash', 'glm-4-air', 'glm-4-plus', 'glm-4v-plus'],
      keyHelpUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
      keyHint: '...',
    ),
    AIProviderPreset(
      id: 'gemini',
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      models: ['gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-2.0-flash'],
      keyHelpUrl: 'https://aistudio.google.com/apikey',
      keyHint: 'AIza...',
    ),
    AIProviderPreset(
      id: 'custom',
      name: '自定义',
      baseUrl: '',
      models: [],
      keyHelpUrl: '',
      keyHint: '',
    ),
  ];

  static AIProviderPreset? getById(String id) {
    for (final p in builtin) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Result of a tool-calling loop (Phase 1: research).
///
/// [toolResults] contains the raw output of every tool execution (search
/// results, fetched pages), in order. [finalContent] is the LLM's last text
/// message (may be null if all rounds returned content=null). [toolsSupported]
/// is false when the provider doesn't support tools and we fell back to a
/// plain [chatCompletion] — in that case [finalContent] is already
/// schema-constrained and [toolResults] is empty.
class ToolLoopResult {
  final String? finalContent;
  final List<String> toolResults;
  final bool toolsSupported;

  ToolLoopResult({
    this.finalContent,
    this.toolResults = const [],
    this.toolsSupported = true,
  });
}

/// AI 服务（兼容 OpenAI 接口格式）
class OpenAIService {
  static const String _apiKeyKey = 'ai_api_key';
  static const String _modelKey = 'ai_model';
  static const String _baseUrlKey = 'ai_base_url';
  static const String _providerIdKey = 'ai_provider_id';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
  ));

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_apiKeyKey);
    if (key != null) return key;
    // 兼容旧版本 key
    final oldKey = prefs.getString('openai_api_key');
    if (oldKey != null) {
      await prefs.setString(_apiKeyKey, oldKey);
      await prefs.remove('openai_api_key');
      return oldKey;
    }
    return null;
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
  }

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString(_modelKey);
    if (model != null) return model;
    // 兼容旧版本
    final oldModel = prefs.getString('openai_model');
    if (oldModel != null) {
      await prefs.setString(_modelKey, oldModel);
      await prefs.remove('openai_model');
      return oldModel;
    }
    return 'gpt-4o-mini';
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelKey, model);
  }

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? 'https://api.openai.com/v1';
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  Future<String> getProviderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_providerIdKey) ?? 'openai';
  }

  Future<void> setProviderId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerIdKey, id);
  }

  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// 调用 AI Chat Completions API（OpenAI 兼容格式）
  ///
  /// Set [throwOnTruncation] to false to return truncated content instead of
  /// throwing — callers that can handle partial output (e.g. two-pass
  /// generation) should use this.
  Future<String> chatCompletion({
    required String systemPrompt,
    required String userContent,
    String? imageBase64,
    double? temperature,
    OutputConstraintLevel? outputConstraint,
    Map<String, dynamic>? schema,
    int maxTokens = 4096,
    bool throwOnTruncation = true,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('未设置 API Key，请先在设置中配置');
    }

    final model = await getModel();
    final baseUrl = await getBaseUrl();

    LogService.instance.log('chatCompletion', 'info', 'request', {
      'model': model,
      'baseUrl': baseUrl,
      'maxTokens': maxTokens,
      'hasSchema': schema != null,
      'outputConstraint': outputConstraint?.name,
      'hasImage': imageBase64 != null,
    });
    final sw = Stopwatch()..start();

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    if (imageBase64 != null) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': userContent},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'},
          },
        ],
      });
    } else {
      messages.add({'role': 'user', 'content': userContent});
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature ?? 0.7,
      'max_tokens': maxTokens,
    };

    if (outputConstraint == OutputConstraintLevel.level3Strict && schema != null) {
      body['response_format'] = {
        'type': 'json_schema',
        'json_schema': {
          'name': 'output',
          'strict': true,
          'schema': schema,
        },
      };
    } else if (outputConstraint == OutputConstraintLevel.level2Json) {
      body['response_format'] = {'type': 'json_object'};
    }

    try {
      final response = await _retryWithBackoff(
        () => _dio.post(
          '$baseUrl/chat/completions',
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          ),
          data: jsonEncode(body),
        ),
        operationName: 'chatCompletion',
      );

      if (response.statusCode != 200) {
        throw Exception('API 请求失败: ${response.statusCode}');
      }

      final String content;
      if (throwOnTruncation) {
        content = _extractContent(response);
      } else {
        final result = _extractContentWithTruncation(response);
        content = result.content;
        if (result.truncated) {
          LogService.instance.log('chatCompletion', 'warn', 'output_truncated', {
            'contentLength': content.length,
            'maxTokens': maxTokens,
            'model': model,
          });
        }
      }
      sw.stop();
      LogService.instance.log('chatCompletion', 'info', 'response', {
        'contentLength': content.length,
        'durationMs': sw.elapsedMilliseconds,
        'model': model,
      });
      return content;
    } on DioException catch (e) {
      sw.stop();
      final status = e.response?.statusCode;
      final errorMsg = e.response?.data?.toString() ?? e.message ?? '';
      LogService.instance.log('chatCompletion', 'error', 'dio_error', {
        'status': status,
        'errorMsg': errorMsg,
        'durationMs': sw.elapsedMilliseconds,
      });
      if ((status == 400 || status == 422) &&
          errorMsg.contains('response_format')) {
        // Graceful degradation: retry without response_format
        body.remove('response_format');
        final retry = await _dio.post(
          '$baseUrl/chat/completions',
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          ),
          data: jsonEncode(body),
        );
        if (retry.statusCode != 200) {
          throw Exception('API 请求失败: ${retry.statusCode}');
        }
        // Cache the degradation so future calls skip L3 immediately
        ProviderCapability.forceLevel(OutputConstraintLevel.level1Prompt);
        LogService.instance.log('chatCompletion', 'warn', 'degraded_to_prompt', {
          'reason': 'provider_unsupported_response_format',
          'status': status,
        });
        return _extractContent(retry);
      }
      rethrow;
    }
  }

  /// 带 tool call 的对话（支持多轮工具调用）— Phase 1: 研究阶段
  ///
  /// 循环执行：调用 API → 解析 tool_calls → 执行工具 → 追加结果 → 再次调用
  /// 直到无 tool_calls 或达到 maxToolCalls 上限。
  ///
  /// 不再做 post-hoc reformat。返回 [ToolLoopResult]，包含所有工具执行结果
  /// ([ToolLoopResult.toolResults]) 和 LLM 最终文本 ([ToolLoopResult.finalContent])。
  /// 调用方负责将 toolResults 结构化后喂给下游生成调用。
  ///
  /// 若 API 返回工具不支持错误，自动降级到普通 chatCompletion（此时
  /// [ToolLoopResult.toolsSupported] 为 false，[ToolLoopResult.finalContent]
  /// 已是 schema 约束的输出）。
  Future<ToolLoopResult> chatCompletionWithTools({
    required String systemPrompt,
    required String userContent,
    required List<Map<String, dynamic>> toolDefinitions,
    required Future<String> Function(String toolName, Map<String, dynamic> args) executeTool,
    double? temperature,
    int maxToolCalls = 5,
    OutputConstraintLevel? outputConstraint,
    Map<String, dynamic>? schema,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('未设置 API Key，请先在设置中配置');
    }

    final model = await getModel();
    final baseUrl = await getBaseUrl();

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userContent},
    ];

    String? finalContent = '';
    final toolResults = <String>[];

    LogService.instance.log('chatCompletionWithTools', 'info', 'loop_start', {
      'toolCount': toolDefinitions.length,
      'maxToolCalls': maxToolCalls,
    });
    final loopSw = Stopwatch()..start();

    for (var round = 0; round <= maxToolCalls; round++) {
      try {
        final response = await _retryWithBackoff(
          () => _dio.post(
            '$baseUrl/chat/completions',
            options: Options(
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
            ),
            data: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': temperature ?? 0.7,
              'max_tokens': 4096,
              'tools': toolDefinitions.map((t) => {
                'type': 'function',
                'function': t,
              }).toList(),
            }),
          ),
          operationName: 'chatCompletionWithTools',
        );

        if (response.statusCode != 200) {
          throw Exception('API 请求失败: ${response.statusCode}');
        }

        final data = response.data as Map<String, dynamic>;
        final choices = data['choices'] as List;
        if (choices.isEmpty) {
          throw Exception('API 返回空结果');
        }

        final message = choices[0]['message'] as Map<String, dynamic>;
        final content = message['content'] as String?;
        final toolCallsRaw = message['tool_calls'] as List?;

        if (content != null) {
          finalContent = content;
        }

        if (toolCallsRaw == null || toolCallsRaw.isEmpty) {
          // 无工具调用，返回收集到的结果
          return ToolLoopResult(
            finalContent: finalContent,
            toolResults: toolResults,
            toolsSupported: true,
          );
        }

        // 追加 assistant 消息（含 tool_calls）
        messages.add(Map<String, dynamic>.from(message));

        // 执行每个工具调用
        for (final tc in toolCallsRaw) {
          final tcMap = tc as Map<String, dynamic>;
          final id = tcMap['id'] as String;
          final function = tcMap['function'] as Map<String, dynamic>;
          final name = function['name'] as String;
          final argsRaw = function['arguments'] as String;

          Map<String, dynamic> args;
          try {
            args = jsonDecode(argsRaw) as Map<String, dynamic>;
          } on FormatException {
            args = {'raw': argsRaw};
          }

          final result = await executeTool(name, args);
          toolResults.add(result);

          messages.add({
            'role': 'tool',
            'tool_call_id': id,
            'name': name,
            'content': result,
          });

          LogService.instance.log('chatCompletionWithTools', 'info', 'tool_call', {
            'round': round,
            'toolName': name,
            'resultLength': result.length,
          });
        }
      } on DioException catch (e) {
        // 若 API 不支持 tools 参数，降级到普通对话
        final errorMsg = e.response?.data?.toString() ?? e.message ?? '';
        if (errorMsg.contains('tools') || errorMsg.contains('tool')) {
          LogService.instance.log('chatCompletionWithTools', 'warn', 'degraded_to_plain', {
            'reason': 'provider_unsupported_tools',
            'errorMsg': errorMsg,
            'round': round,
          });
          final content = await chatCompletion(
            systemPrompt: systemPrompt,
            userContent: userContent,
            temperature: temperature,
            outputConstraint: outputConstraint,
            schema: schema,
          );
          loopSw.stop();
          LogService.instance.log('chatCompletionWithTools', 'info', 'loop_complete', {
            'rounds': round,
            'toolResultsCount': toolResults.length,
            'toolsSupported': false,
            'durationMs': loopSw.elapsedMilliseconds,
          });
          return ToolLoopResult(
            finalContent: content,
            toolResults: [],
            toolsSupported: false,
          );
        }
        rethrow;
      }
    }

    // 达到 maxToolCalls 上限，返回已收集的结果
    loopSw.stop();
    LogService.instance.log('chatCompletionWithTools', 'info', 'loop_complete', {
      'rounds': maxToolCalls,
      'toolResultsCount': toolResults.length,
      'toolsSupported': true,
      'hitMaxToolCalls': true,
      'durationMs': loopSw.elapsedMilliseconds,
    });
    return ToolLoopResult(
      finalContent: finalContent,
      toolResults: toolResults,
      toolsSupported: true,
    );
  }

  /// AI 判断填空题答案是否正确
  ///
  /// 当用户答案与标准答案不完全匹配时，调用大模型判断语义是否等价。
  /// 返回 true 表示正确，false 表示错误。
  Future<bool> judgeFillBlankAnswer({
    required String question,
    required String userAnswer,
    required String correctAnswer,
  }) async {
    const systemPrompt = '你是一个判题助手。你的任务是判断用户的填空题答案是否与标准答案在语义上等价。'
        '允许的情况包括但不限于：同义词、近义词、不同的表述方式、大小写差异、标点差异、简称与全称。'
        '你只需要回答 JSON 格式：{"correct": true} 或 {"correct": false}，不要输出其他内容。';

    final userContent = '题目：$question\n'
        '标准答案：$correctAnswer\n'
        '用户答案：$userAnswer\n'
        '请判断用户答案是否正确。';

    try {
      LogService.instance.log('judgeFillBlankAnswer', 'info', 'judge_request', {
        'questionLength': question.length,
        'userAnswerLength': userAnswer.length,
        'correctAnswerLength': correctAnswer.length,
      });

      final result = await chatCompletion(
        systemPrompt: systemPrompt,
        userContent: userContent,
        temperature: 0.0,
        outputConstraint: OutputConstraintLevel.level3Strict,
        schema: fillBlankJudgeSchema,
      );

      final parsed = JsonExtractor.parse(result);
      if (parsed != null) {
        final correct = parsed['correct'] == true;
        LogService.instance.log('judgeFillBlankAnswer', 'info', 'judge_response', {
          'correct': correct,
          'resultLength': result.length,
        });
        return correct;
      }
      // 解析失败不再静默返回 false — 抛异常让调用方决定降级策略。
      throw Exception('AI 判题返回内容无法解析');
    } catch (e) {
      // API 调用或解析失败 — 抛异常让调用方决定降级策略。
      LogService.instance.log('judgeFillBlankAnswer', 'error', 'judge_failed', {
        'error': e.toString(),
      });
      throw Exception('AI 判题失败: $e');
    }
  }
}
