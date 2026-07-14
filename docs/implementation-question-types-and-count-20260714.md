# 实现记录：题量显示 + 每关题量可调 + 题型多样性

> 配套计划：`docs/dev-plan-question-types-and-count-20260714.md`
> 日期：2026-07-14 | 状态：**已实现并通过 analyze + 全量 test（87 项绿）**

## 改动清单

### ① 显示总题量
- `lib/features/learning/quiz_screen.dart`：进度条下方新增「第 X / Y 题」文本（读 `_currentIndex+1` / `_questions.length`），不改进度条组件。

### ② 每关题量 5–20 可调
- `lib/core/providers/providers.dart`：新增 `questionsPerLevelProvider`（`StateNotifierProvider<int>`，默认 5，`clamp(5,20)`，SharedPreferences key `questions_per_level`）。
- `lib/features/settings/settings_screen.dart`：新增「每关题量」卡片（选项 5/10/15/20，仿「每日 XP 目标」的 `Row+Expanded+GestureDetector`，接 `ref.watch` / `ref.read(...).set`）。
- `lib/features/home/home_screen.dart:409`：`getSmartRandomQuestions(5)` → `getSmartRandomQuestions(ref.read(questionsPerLevelProvider))`（`_startRandomLevel` 已持 `ref`，零 widget 升级）。

### ③ 题型多样性（恢复连线/排序）
- `lib/data/models/schemas/deck_schema.dart`：`deckJsonSchema` 与 `questionBatchSchema` 两处 `question.required` 均移出 `options`（连线/排序题不再被强制填 options，L3 严格校验下可正常产出）。
- `lib/features/deep/deep_pipeline_controller.dart`：生成 / 展开 / 计划 三处 prompt 补 `matching` + `ordering` 的 JSON 示例（字段命名复用 `content_analyzer.dart`），并强化规则「至少 2 种题型，且必须含 ≥1 道连线/排序题」。

## 验证结果
- `flutter analyze`：**零 error**（仅预存 `info` 级 lint，均指向既有代码，与本次改动无关）。
- `flutter test`：**87 项全绿**。
  - 新增 `test/models/question_test.dart`：matching / ordering 无 `options` 可正确解析且不崩。
  - 新增 `test/providers/questions_per_level_test.dart`：provider 默认 5 且钳制到 5–20。
  - 更新 `test/services/deck_schema_test.dart`：同步新契约（`options` 不再 required，并补 `questionBatchSchema` 断言）。
- 随机模式透传确认：`getSmartRandomQuestions` 的 SQL（`database_helper.dart:315-327`）**不按 `type` 过滤**，故 deep 生成的连线/排序题会自动进入随机模式（无需 ③.4）。

## 待手动验收（无法自动化）
- quiz 页进度条下显示「第 X / Y 题」且随翻页更新。
- 设置页「每关题量」可选 5/10/15/20，退出重进保持；选 20 后随机关约 20 题。
- deep 模式生成牌组出现连线/排序题且可正常作答（Widget 已存在，无需改 UI）。

## 提交记录
三功能各自独立 commit + 1 个 docs commit，已推 `origin/main`（2026-07-14）：
1. `feat(quiz): show current question index and total count`
2. `feat(settings): make per-level question count configurable (5-20)`
3. `feat(deep): restore matching and ordering question types`
4. `docs: investigation, plan, and implementation notes for question types and count`

> 推 `main` 会触发 `nightly.yml` 自动构建签名 release APK 并发布为 `nightly` prerelease。
> 「待手动验收」三项仍待真机/真实 deep 生成验证，不阻断发版但建议验收后再向用户宣告。
