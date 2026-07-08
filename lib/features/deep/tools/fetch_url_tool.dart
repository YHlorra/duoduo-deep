import 'package:dio/dio.dart';

/// 网页抓取工具 — 使用 Jina Reader (https://r.jina.ai) 获取 Markdown 全文
/// 替代自写 HTML 解析，输出更干净且对 LLM 友好
class FetchUrlTool {
  final Dio _dio;

  FetchUrlTool(this._dio);

  /// Tool 定义 — 发送给 LLM 的 JSON Schema
  static const toolDefinition = {
    'name': 'fetch_url',
    'description': '抓取网页全文内容。当你需要获取某个链接的完整文章、教程、文档内容时使用。注意：仅当搜索结果中的链接确实包含你需要的信息时才抓取，不要盲目抓取所有链接。',
    'parameters': {
      'type': 'object',
      'properties': {
        'url': {
          'type': 'string',
          'description': '要抓取的完整 URL，包含 http:// 或 https:// 前缀'
        }
      },
      'required': ['url']
    }
  };

  /// Jina Reader 端点 — 公开服务，把目标 URL 拼到 path 里
  /// 返回纯 Markdown，比自写正则剥离 HTML 更可靠
  static const _jinaReaderUrl = 'https://r.jina.ai/';

  /// 执行抓取 — 通过 Jina Reader 中转
  Future<String> execute(String url) async {
    try {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        return '错误: 仅支持 http/https 链接。';
      }

      // Jina Reader 接收 URL 作为 path，返回 Markdown 全文
      final response = await _dio.get<String>(
        '$_jinaReaderUrl$url',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; DlgQ/1.0)',
            'Accept': 'text/plain',
          },
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
        ),
      );

      final markdown = response.data ?? '';
      if (markdown.isEmpty) {
        return '抓取结果为空，可能页面需要登录或被反爬拦截。';
      }

      // 截断到 8000 字符（Markdown 通常比 HTML 紧凑）
      if (markdown.length > 8000) {
        return '${markdown.substring(0, 8000)}\n\n[内容过长，已截断]';
      }
      return markdown;
    } catch (e) {
      return '抓取失败: $e';
    }
  }
}