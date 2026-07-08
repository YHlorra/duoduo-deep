import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dlg_q/features/deep/tools/fetch_url_tool.dart';

class _MockAdapter implements HttpClientAdapter {
  final String Function(RequestOptions) responder;
  _MockAdapter(this.responder);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future? cancelFuture) async {
    return ResponseBody.fromString(responder(options), 200, headers: {});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('FetchUrlTool', () {
    test('execute returns markdown content from Jina', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockAdapter((options) {
        // Verify the URL was prefixed with r.jina.ai
        expect(options.path, contains('r.jina.ai'));
        return '# Title\n\nMarkdown content here.';
      });

      final tool = FetchUrlTool(dio);
      final result = await tool.execute('https://example.com/article');

      expect(result, contains('Title'));
      expect(result, contains('Markdown content'));
    });

    test('execute rejects non-http URLs', () async {
      final dio = Dio();
      final tool = FetchUrlTool(dio);
      final result = await tool.execute('ftp://example.com');

      expect(result, contains('错误'));
      expect(result, contains('http'));
    });

    test('execute truncates long content', () async {
      final dio = Dio();
      final tool = FetchUrlTool(dio);
      final longContent = 'A' * 10000;
      dio.httpClientAdapter = _MockAdapter((options) => longContent);

      final result = await tool.execute('https://example.com/long');

      expect(result.length, lessThan(8200));
      expect(result, contains('已截断'));
    });
  });
}
