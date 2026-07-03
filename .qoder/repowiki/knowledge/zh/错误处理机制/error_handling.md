该 Flutter 应用采用基于 `Exception` 的简单错误处理策略，主要依赖 Dart 原生的 `try-catch` 块进行异常捕获与传播。系统未定义自定义错误类型或错误码体系，而是直接使用通用 `Exception` 携带字符串消息。

### 1. 核心策略
- **异常抛出**：在业务逻辑层（如 `OpenAIService`、`ContentAnalyzer`）通过 `throw Exception('...')` 主动抛出运行时错误，通常用于标识配置缺失、API 调用失败或数据解析异常。
- **异步错误捕获**：在 UI 层（`ConsumerStatefulWidget`）和状态管理层（`StateNotifier`）使用 `try-catch` 包裹异步操作，防止应用崩溃并更新 UI 状态。
- **状态管理集成**：利用 `flutter_riverpod` 的 `AsyncValue` 处理异步数据流中的错误状态（`AsyncValue.error`），实现加载、成功与错误状态的统一管理。

### 2. 关键实现细节
- **网络与 API 服务**：`lib/services/openai_service.dart` 在 API Key 缺失、HTTP 状态码非 200 或返回结果为空时抛出 `Exception`。
- **数据解析容错**：`lib/services/content_analyzer.dart` 在解析 AI 返回的 JSON 时采用双重策略：先尝试直接解析，失败后通过正则提取 JSON 块；若仍失败或题目列表为空，则抛出异常。单个题目解析失败会被静默跳过（`continue`）。
- **UI 反馈**：`lib/features/ingestion/ingestion_screen.dart` 捕获分析过程中的异常，并将其转化为 `_errorMessage` 字符串显示在界面上，同时重置加载状态。
- **数据库操作**：`lib/data/database/database_helper.dart` 目前未显式包含 `try-catch` 块，依赖 SQLite 插件抛出的原生异常向上层传播。

### 3. 开发规范与建议
- **避免静默失败**：在 `ContentAnalyzer` 中跳过无效题目的做法可能导致用户困惑，建议记录日志或提供部分成功的提示。
- **统一错误类型**：当前所有错误均为通用 `Exception`，建议引入自定义错误类（如 `ApiError`、`ParseError`）以便上层进行更精细的错误处理（如区分网络错误与业务逻辑错误）。
- **全局错误处理**：目前缺乏全局错误拦截器（如 `FlutterError.onError` 或 Riverpod 的全局观察者），建议在 `main.dart` 中补充以捕获未处理的异常。