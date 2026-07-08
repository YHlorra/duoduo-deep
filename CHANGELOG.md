# Changelog

本 fork 的所有变更。Fork 起点为上游 `xuanli199/duoduo` `main` 分支 commit `ac377ab` (2026-07-06)。

## [Unreleased]

### Added（fork 新增）

**深度模式（`lib/features/deep/`）**
- `deep_pipeline_controller.dart` — tool-calling 推理管道
- `goal_collection_screen.dart` — 学习目标输入
- `pipeline_progress_screen.dart` — 管道执行进度展示
- `tools/web_search_tool.dart` — 联网搜索
- `tools/fetch_url_tool.dart` — URL 抓取
- `tools/learning_goal.dart` — 目标模型

**概念页（`lib/features/concept/concept_list_screen.dart`）** — 按概念聚合卡片

**服务层**
- `json_extractor.dart` — JSON 解析 + LLM 自修复
- `output_constraint.dart` — Provider 能力探测 (L3/L2/L1) + 降级
- `llm_parse_exception.dart` — 解析异常类型
- `sm2_algorithm.dart` — SuperMemo SM-2 间隔重复
- `socratic_dialog_service.dart` — 苏格拉底对话

**数据层**
- `data/models/schemas/deck_schema.dart` — JSON Schema 定义
- `data/models/app_prefs.dart` — 应用偏好模型

**测试（`test/`）**
- `core/provider_cache_pair_test.dart`
- `features/deep/tools/fetch_url_tool_test.dart`
- `features/deep/tools/web_search_tool_test.dart`
- `services/deck_schema_test.dart`
- `services/json_extractor_test.dart`
- `services/output_constraint_test.dart`
- `services/sm2_algorithm_test.dart`

### Changed（fork 修改上游文件）

- `lib/services/openai_service.dart` — 工具循环 + 错误处理
- `lib/services/content_analyzer.dart` — 快速模式增强
- `lib/features/learning/quiz_screen.dart` — 答题屏重写
- `lib/features/settings/settings_screen.dart` — 设置屏重写
- `lib/features/ingestion/ingestion_screen.dart` — 导入屏
- `lib/data/database/database_helper.dart` — v1→v2 数据库迁移
- `lib/core/providers/providers.dart` — Riverpod 装配
- `lib/data/models/deck.dart` / `question.dart` — 模型扩展
- `pubspec.yaml` — 依赖调整
- `android/gradle.properties` / `gradle-wrapper.properties` — 工具链
- `test/widget_test.dart` — 测试更新
- `.gitignore` — 排除内部文档

---

## 上游基线

- 上游仓库：https://github.com/xuanli199/duoduo
- 上游协议：MIT License
- 上游 commit：`ac377ab` (2026-07-06) — 填空题 AI 判题
- 上游 commit 数：4
