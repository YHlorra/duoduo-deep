import 'dart:convert';
import 'package:dio/dio.dart';

/// Exa MCP 搜索工具 — 通过 Model Context Protocol 调用 Exa 公开服务
/// (无需 API Key，expo MCP server 端点: https://mcp.exa.ai/mcp)
class WebSearchTool {
  final Dio _dio;

  WebSearchTool(this._dio);

  /// Tool 定义 — 发送给 LLM 的 JSON Schema
  static const toolDefinition = {
    'name': 'web_search',
    'description': '搜索互联网获取信息。当你需要了解某个概念的最新信息、最佳实践、示例代码、常见错误时使用。如果用户的问题需要最新或广泛的信息，请使用此工具。',
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': '搜索关键词。使用中文或英文，要具体明确。例如："Python 闭包 示例" 或 "React hooks best practices"'
        }
      },
      'required': ['query']
    }
  };

  /// Exa MCP 端点 — 公开服务，无需 API Key
  static const _exaMcpUrl = 'https://mcp.exa.ai/mcp';

  /// JSON-RPC request ID 计数器
  static int _requestId = 0;

  int _nextId() => ++_requestId;

  /// 执行搜索 — 通过 Exa MCP 调用
  Future<String> execute(String query) async {
    try {
      // 1. MCP initialize 握手
      await _mcpInitialize();

      // 2. 调用 web_search_exa 工具
      final response = await _dio.post(
        _exaMcpUrl,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
          },
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 8),
        ),
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': _nextId(),
          'method': 'tools/call',
          'params': {
            'name': 'web_search_exa',
            'arguments': {
              'query': query,
              'numResults': 5,
            },
          },
        }),
      );

      return _formatMcpResponse(response.data);
    } catch (e) {
      return '搜索失败: $e。请尝试其他关键词或跳过搜索。';
    }
  }

  /// MCP initialize 握手 — 幂等，多次调用安全
  Future<void> _mcpInitialize() async {
    try {
      await _dio.post(
        _exaMcpUrl,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
          },
          receiveTimeout: const Duration(seconds: 8),
        ),
        data: jsonEncode({
          'jsonrpc': '2.0',
          'id': _nextId(),
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': {},
            'clientInfo': {'name': 'duoduo', 'version': '1.0'},
          },
        }),
      );
    } catch (_) {
      // initialize 失败不阻塞 — 部分 MCP server 容忍无 initialize 调用
    }
  }

  /// 解析 MCP JSON-RPC 响应
  String _formatMcpResponse(dynamic rawData) {
    try {
      Map<String, dynamic> data;
      if (rawData is String) {
        // SSE 格式: data: {...} — 提取 JSON 部分
        final lines = rawData.split('\n');
        final jsonLine = lines.firstWhere(
          (l) => l.startsWith('data: '),
          orElse: () => '',
        );
        if (jsonLine.isEmpty) return '搜索返回格式异常';
        data = jsonDecode(jsonLine.substring(6)) as Map<String, dynamic>;
      } else if (rawData is Map<String, dynamic>) {
        data = rawData;
      } else {
        return '搜索返回格式异常';
      }

      // 检查 JSON-RPC 错误
      if (data.containsKey('error')) {
        final err = data['error'];
        return '搜索服务错误: ${err is Map ? err['message'] ?? err : err}';
      }

      final result = data['result'];
      if (result == null) return '搜索无结果';

      final content = result['content'] as List?;
      if (content == null || content.isEmpty) return '搜索无结果';

      final buf = StringBuffer();
      for (final item in content) {
        if (item is Map && item['type'] == 'text') {
          buf.writeln(item['text']);
          buf.writeln('---');
        }
      }

      final result_text = buf.toString().trim();
      return result_text.isEmpty ? '搜索无结果' : result_text;
    } catch (e) {
      return '搜索结果解析失败: $e';
    }
  }
}