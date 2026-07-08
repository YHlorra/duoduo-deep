import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:dlg_q/features/deep/tools/web_search_tool.dart';

class _MockAdapter implements HttpClientAdapter {
  final dynamic Function(RequestOptions) responder;
  _MockAdapter(this.responder);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future? cancelFuture) async {
    final response = responder(options);
    return ResponseBody.fromString(
      response is String ? response : response.toString(),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('WebSearchTool', () {
    test('execute returns formatted results on success', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockAdapter((options) {
        return '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Result 1: Foo\\nURL: https://x.com"},{"type":"text","text":"Result 2: Bar\\nURL: https://y.com"}]}}';
      });

      final tool = WebSearchTool(dio);
      final result = await tool.execute('Python 闭包');

      expect(result, contains('Result 1'));
      expect(result, contains('Result 2'));
      expect(result, contains('https://x.com'));
    });

    test('execute returns error message on HTTP failure', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockAdapter((options) {
        throw DioException(requestOptions: options, error: 'Connection refused');
      });

      final tool = WebSearchTool(dio);
      final result = await tool.execute('Python');

      expect(result, contains('搜索失败'));
    });

    test('execute returns "搜索无结果" when content empty', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockAdapter((options) {
        return '{"jsonrpc":"2.0","id":1,"result":{"content":[]}}';
      });

      final tool = WebSearchTool(dio);
      final result = await tool.execute('Python');

      expect(result, contains('搜索无结果'));
    });
  });
}
