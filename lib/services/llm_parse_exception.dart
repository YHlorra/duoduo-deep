// Base class for LLM output parsing exceptions.
//
// ponytail: callers still throw bare Exception; wire these in when adding
// per-type error handling to DeepPipelineController / ContentAnalyzer.
abstract class LlmParseException implements Exception {
  String toUserMessage();
}

/// Provider does not support the requested response_format.
class ProviderUnsupportedException extends LlmParseException {
  final String detail;
  ProviderUnsupportedException([this.detail = '']);

  @override
  String toUserMessage() =>
      '当前 AI 接口不支持结构化输出，已降级为普通模式。${detail.isNotEmpty ? '（$detail）' : ''}';
}

/// Could not extract any JSON from the response.
class JsonExtractException extends LlmParseException {
  final String raw;
  JsonExtractException(this.raw);

  @override
  String toUserMessage() =>
      'AI 返回格式异常，无法提取题目数据。建议：换一个模型或重试。';

  @override
  String toString() => 'JsonExtractException: ${raw.substring(0, raw.length.clamp(0, 100))}...';
}

/// LLM-based JSON repair also failed.
class JsonFixFailedException extends LlmParseException {
  final String raw;
  JsonFixFailedException(this.raw);

  @override
  String toUserMessage() =>
      'AI 多次返回异常格式，建议切换模型或稍后重试。';

  @override
  String toString() => 'JsonFixFailedException: ${raw.substring(0, raw.length.clamp(0, 100))}...';
}

/// LLM returned empty content.
class EmptyResponseException extends LlmParseException {
  @override
  String toUserMessage() => 'AI 未返回内容，请检查网络后重试。';
}
