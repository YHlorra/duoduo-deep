# 调查报告：题型单一化 + 总题量显示 + 每关题量可调

> 调查日期：2026-07-14
> 范围：仅调研，未改动任何代码。结论指向具体文件与实现方法，供后续开发排期。

## 一、结论速览（先说结论，再给证据）

1. **"深度模式只会出选择题"——这个说法不准确，但现象是真的。**
   - Schema 本来就支持 5 种题型（`multiple_choice` / `fill_blank` / `true_false` / `matching` / `ordering`，见 `deck_schema.dart:45-51`）。
   - 显示层 `question_widgets.dart` 也完整实现了 5 种 Widget（含 `MatchingWidget` / `OrderingWidget`），`QuestionWidget` 的 switch 覆盖全部类型——**显示层没有 bug，连线/排序题一旦生成就能渲染**。
   - 真正原因：**深度模式的 prompt 只给选择题示例 + schema 强制 `options` 必填**，把模型"挤"成了几乎只出选择题。而**快速模式 `content_analyzer.dart` 的 prompt 给全了 5 种题型格式**——这正好解释了你"之前碰到过其他题型"：之前大概率是快速模式出的包，现在你切到深度模式就用不了连线/排序了。

2. **"不显示总题量"——答题进行中确实没有数字。**
   - `quiz_screen.dart:374` 只画了进度条 `(_currentIndex + 1) / _questions.length`，没有"第 X / Y 题"文字。
   - 结果页（861 行）有"答对 X / Y 题"，但那是结束才显示。

3. **"每关约 5 题"——硬编码来源已定位。**
   - 随机模式：`home_screen.dart:409` 写死 `db.getSmartRandomQuestions(5)`。
   - 题包生成：深度模式 plan prompt 说"5-8 道"（508），快速模式说"5-10"（126）；schema `maxItems` 在 10 封顶。

---

## 二、Feature 1：恢复题型多样性（连线 / 排序等）

### 根因（3 处，都在生成侧）
| # | 位置 | 问题 |
|---|---|---|
| R1 | `deep_pipeline_controller.dart:558-587`（`_buildExpandSystemPrompt`）、`:361-399`（`_buildGenerationSystemPrompt`） | 示例 JSON 只给 `multiple_choice`，且无 `matching` / `ordering` 格式说明。模型默认照抄示例 → 全选择题。 |
| R2 | `deck_schema.dart:38`（deckJsonSchema）、`:189`（questionBatchSchema） | `question.required` 强制含 `options`。连线题本该用 `match_left` / `match_right`，却被 schema 逼着填 `options`。在 L3 严格模式下，模型若省略 `options` 会被拒收→重试/失败，**连线题几乎无法产出**。 |
| R3 | `deep_pipeline_controller.dart:478-512`（`_buildPlanSystemPrompt`） | 只说"至少 2 种题型"，无强制分布、无格式示例，约束力弱。 |

> 对照：快速模式 `content_analyzer.dart:33-129` 的 `_systemPrompt` 已含 5 种题型完整格式（58-118 行），所以快速模式能出多题型——这是"以前见过其他题型"的合理解释。

### 要改的文件 & 实现方法
- **`lib/features/deep/deep_pipeline_controller.dart`**
  - `_buildExpandSystemPrompt` / `_buildGenerationSystemPrompt`：在 JSON 示例里补 `matching`（含 `match_left` / `match_right` / `answer` 用 `条目1-匹配A|...`）与 `ordering`（含 `options` 打乱、`answer` 用 `|` 分隔）样例，格式直接复用 `content_analyzer.dart:58-118` 的写法。
  - `_buildPlanSystemPrompt`：把"至少 2 种题型"改为更强约束，例如"题型需覆盖至少 3 种，且必须包含 `matching` 或 `ordering` 中至少一种"。
- **`lib/data/models/schemas/deck_schema.dart`**
  - 将 `deckJsonSchema` 与 `questionBatchSchema` 的 `question.required` 中的 `options` **移出**（改成可选）。JSON Schema 的 `required` 无法按 `type` 分支，所以只能整体放开，然后在 prompt 里要求选择题/判断题/排序题仍填 `options`。这样连线题不再被必填 `options` 卡死（R2 修复）。
  - `questionPlanSchema`（`questionStub`）本就不强制 `options`，无需改。
- **无需改**：`question.dart`（fromJson 已正确读 match_left/match_right）、`question_widgets.dart`（已完整支持）。

### 验证方法
- 单测：构造含 `matching` 的 `questionBatchSchema` JSON，断言 `Question.fromJson` + `MatchingWidget` 渲染正常。
- 端到端：深度模式生成后，断言 `result.questions` 中 `type != multiple_choice` 的题存在（可在 `test/deep_stress_test.dart` 加题型分布断言）。

---

## 三、Feature 2：答题进行中显示总题量

### 现状
- 进度条：`quiz_screen.dart:372-381` 的 `QuizProgressBar(progress: (_currentIndex + 1) / _questions.length, ...)`，只有条、没有数字。
- 标签行（`quiz_screen.dart:389-415`）目前只有"题型 / 难度 / 认知层级"三个徽章，没有题号。

### 要改的文件 & 实现方法
- **`lib/features/learning/quiz_screen.dart`**
  - 在进度条上方或标签行中加一行：`Text('第 ${_currentIndex + 1} / ${_questions.length} 题')`（或直接"共 N 题"徽章）。`QuizProgressBar` 本身只吃 `progress`，**不要改它**，在外面补 Text 即可。
  - 位置建议：标签行（`Row`，389 行起）最右追加一个"共 N 题"徽章，与题型/难度视觉一致。

### 验证
- 手动：进入任意题包/随机关，顶部出现"第 1 / 8 题"。
- 纯 UI 文案，无需单测（若做可加 widget test 断言文案含 `/`）。

---

## 四、Feature 3：每关题量 5–20 可调（切换按钮）

### 现状
- 随机模式：`home_screen.dart:409` 硬编码 `getSmartRandomQuestions(5)`。`getSmartRandomQuestions(int count, ...)` 已接受 `count` 参数（`database_helper.dart:279`），改动成本极低。
- 题包生成：深度 plan prompt "5-8"（508）、快速 "5-10"（126）；schema `maxItems`：deckJsonSchema=10（25）、questionPlanSchema=10（140）。
- 设置页已有同类 UI 范式：`settings_screen.dart:386-422` 的"每日 XP 目标" chip 选择器，可照搬做"每关题量"。

### 实现方法（推荐分两档，先覆盖核心诉求）

**A. 新增持久化设置 `questionsPerLevel`（int，默认 5，范围 5–20）**
- `lib/core/providers/providers.dart`：仿照 `socraticEnabledProvider`（303 行）新增 `questionsPerLevelProvider`（`StateNotifier` + SharedPreferences key `questions_per_level`，默认 5）。

**B. 设置页 UI**
- `lib/features/settings/settings_screen.dart`：新增"出题设置"卡片，仿 386-422 的 chip 行，选项 `[5, 8, 10, 15, 20]`；读取/保存走 `questionsPerLevelProvider`。

**C. 随机模式接线（核心诉求）**
- `lib/features/home/home_screen.dart:409`：`getSmartRandomQuestions(ref.read(questionsPerLevelProvider))` 替代硬编码 `5`。

**D.（可选）题包生成接线**
- `deep_pipeline_controller.dart`：plan prompt 的"5-8"改为读取目标数量（经 `LearningGoal` 或新增参数字段传入）；`questionPlanSchema` `maxItems` 10→20。深度模式靠 batch 循环（已支持）自然扩到 20。
- `content_analyzer.dart`：prompt 的"5-10"改可配置；`deckJsonSchema` `maxItems` 10→20（仅 quick 模式走该 schema 校验）。
- 注意：题量到 20 会增加 token 与生成时长（深度模式每批 `maxTokens: 4096`，20 题≈7 批，可接受）。

### 验证
- 设置选 20 → 随机模式进关 → 断言抽题数 = `min(20, 题库总数)`。
- （可选）深度模式目标 20 → 断言 `plan.length` 接近 20。

---

## 五、影响面 & 风险

- **改 schema（options 移出 required）**：L3 严格模式下，选择题仍会填 `options`，连线题不再因缺 `options` 报错——整体更稳，不是退化。需回归"选择题/判断题"解析单测确保无回归。
- **题量上限 20**：生成成本上升；`getSmartRandomQuestions` 在题库不足时返回更少（已有 cooldown 逻辑），不会崩。
- **显示层无需改动**：5 种题型 Widget 已就绪，修复生成侧即生效。

## 六、建议实施顺序

1. **Feature 2（显示总题量）**——最小风险、即时可见，先做。
2. **Feature 3（设置 + 随机模式接线）**——中等风险，覆盖"每关题量"核心诉求。
3. **Feature 1（题型多样性：deep prompt + schema）**——核心体验修复，需 prompt 调优 + 回归测试。
4. （可选）**Feature 3 的题包生成覆盖**（D 档）——视 token 预算决定。

---
*注：本文件为调研产物，所有改动待排期后实施。涉及 schema 修改时务必同步更新 `test/` 下相关解析单测。*
