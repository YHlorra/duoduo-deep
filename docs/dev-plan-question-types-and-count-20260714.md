# 开发计划：题量显示 + 每关题量可调 + 题型多样性

> 配套调查报告：`docs/investigation-question-types-and-count-20260714.md`
> 状态：规划阶段（未改动任何代码）
> 调查已用代码逐条验证，本计划所有 file:line 均经核实。

## 总览

| 编号 | 功能 | 根因（已验证） | 风险 | 依赖 |
|---|---|---|---|---|
| ① | 显示总题量 | `quiz_screen.dart:374` 只画进度条，未 render 数字 | 低 | 无 |
| ② | 每关题量 5–20 可调 | `home_screen.dart:409` 硬编码 `getSmartRandomQuestions(5)` | 低 | ②.1 → ②.2/②.3 |
| ③ | 题型多样性（连线/排序） | deep mode prompt 只给选择题示例 + schema 强制 `options` 必填 | 中 | ③.1 → ③.2 → ③.3 |

**关键已验证事实（避免计划写错）：**
- `getSmartRandomQuestions(int count, {Duration cooldown})` 本就参数化（`database_helper.dart:279`）→ ② 接线零成本。
- `Question` 模型**已完整支持连线题**：`matchLeft`/`matchRight` 字段 + `toMap`/`fromMap`/`fromJson` 全链路落库解析（`question.dart:13-14, 63-64, 79-81, 90-91`）→ ③ **只改 schema + prompt，不动数据模型**。
- `options` 在模型里 `List<String>` 非 nullable，但 `fromJson` 用 `?? []` 兜底（`question.dart:89,98`）→ schema 把 `options` 改为可选**不会崩**，连线题会是空 `options`。
- `_startRandomLevel` 已持有 `WidgetRef ref`（`home_screen.dart:407`）→ ②.3 直接 `ref.read(questionsPerLevelProvider)`，无需升级 widget。
- provider 持久化范式：`StateNotifierProvider` + `SharedPreferences` 按 key 读写（仿 `socraticEnabledProvider:306-329`，key `'socratic_enabled'`，默认 false）。

## 交付顺序（按你确认的风险梯度）

① → ② → ③。三者相互独立，可单测隔离；③ 因要调 LLM prompt 且涉及生成回归，放最后。

---

## Feature ① — 显示总题量

**目标**：quiz 页进度条旁显示「第 X / Y 题」。

### Task ①.1 进度条旁加总数徽章
- **文件**：`lib/features/learning/quiz_screen.dart`（进度条约 `:374`，标签行约 `:389`）
- **改动**：在进度条同一行（或紧邻标签行）增加一个 `Text('第 $currentIndex / ${questions.length} 题')`。`questions` 是页面的 `List<Question>`（已是字段），当前题号从现有 index 状态读。
- **注意**：保持现有进度条组件不动，只新增文本节点；不引入新 State。
- **验证**：
  - `flutter analyze` 通过。
  - 手动/截图：进入任意 quiz，确认徽章随翻页更新（1/5 → 2/5 …）。
  - 推荐补一个 widget 测试：mock 长度为 N 的 `questions`，断言首屏显示 `1 / N`。

**DOD（①）**：quiz 页可见「第 X / Y 题」，翻页数字正确。

---

## Feature ② — 每关题量 5–20 可调

**目标**：设置页提供 5/10/15/20 选择，随机模式每关按此抽题，默认 5（向后兼容）。

### Task ②.1 新增 `questionsPerLevelProvider`
- **文件**：`lib/core/providers/providers.dart`（紧跟 `socraticEnabledProvider` 之后，约 `:330`）
- **改动**：
  ```dart
  final questionsPerLevelProvider =
      StateNotifierProvider<QuestionsPerLevelNotifier, int>((ref) {
    return QuestionsPerLevelNotifier();
  });

  class QuestionsPerLevelNotifier extends StateNotifier<int> {
    QuestionsPerLevelNotifier() : super(5) { _load(); }
    static const _key = 'questions_per_level';
    static const min = 5, max = 20;
    Future<void> _load() async {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_key) ?? 5;
      state = v.clamp(min, max);
    }
    Future<void> set(int v) async {
      state = v.clamp(min, max);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, state);
    }
  }
  ```
- **验证**：provider 单测——默认 5；`set(25)`→20；`set(1)`→5；`set(15)`→15；持久化后 reload 读回。

### Task ②.2 设置页加 chip 选择器
- **文件**：`lib/features/settings/settings_screen.dart`
- **改动**：新增「每关题量」分区，仿「每日 XP 目标」那块的 `Wrap` + `ChoiceChip` 写法；选项 `[5,10,15,20]`；`selected` 由 `ref.watch(questionsPerLevelProvider)` 决定；`onSelected` 调 `ref.read(questionsPerLevelProvider.notifier).set(n)`。
- **注意**：复用现有 ChoiceChip 样式，不新建组件；只接已有 provider。
- **验证**：
  - `flutter analyze` 通过。
  - 手动：设置页选 20 → 退出重进仍为 20；随机模式每关抽到 20 题（配合 ②.3 观察）。

### Task ②.3 随机模式接线
- **文件**：`lib/features/home/home_screen.dart:409`
- **改动**：
  ```dart
  final questions = await db.getSmartRandomQuestions(ref.read(questionsPerLevelProvider));
  ```
  （`_startRandomLevel` 已持有 `ref`，无需改签名/升级 widget。）
- **验证**：
  - `flutter analyze` 通过。
  - 集成手测：设置选 10，开随机关 → 该关约 10 题（受库中可用题量上限约束，不足时取实际最大值）。
  - 回归：默认不设置时行为等同旧版（每关 5）。

**DOD（②）**：设置页可设 5/10/15/20；随机每关抽题数跟随设置；旧用户未设置时仍为 5。

---

## Feature ③ — 题型多样性（恢复连线/排序等）

**目标**：deep mode 生成的牌组恢复全 5 类型，重点补回 `matching` / `ordering`；quick mode 本就支持，无需改。

### Task ③.1 schema 放开 `options` 必填
- **文件**：`lib/data/models/schemas/deck_schema.dart`（`question.required`，约 `:38`）
- **改动**：把 `options` 从 `required` 数组移除（改为可选）。`match_left`/`match_right`/`ordering` 等保持可选。
- **理由**：连线/排序题本不该有 `options`，L3 严格 schema 校验下强制 `options` 会导致这类题被拒/被挤成选择题。
- **验证**：
  - 新增/扩展 schema 单测：一个 `matching` 类型、无 `options` 的 JSON 经 `parse`/`fixJson` 能正确产出 `Question`（且 `type==matching`、`matchLeft`/`matchRight` 非空、`options` 为空列表而不崩）。
  - `flutter analyze` + `flutter test test/...schema` 通过。

### Task ③.2 deep mode prompt 补题型示例
- **文件**：`lib/features/deep/deep_pipeline_controller.dart`（expand prompt 约 `:558-587`；plan prompt；generation prompt）
- **改动**：
  - 在 expand / generation 的题型说明里，补 `matching` 与 `ordering` 的 JSON 格式示例（**直接复用 `content_analyzer.dart:33-129` 已有的连线/排序格式写法**，不要另写一套）。
  - plan prompt 把「至少 2 种题型」强化为「必须包含 ≥1 道连线题或排序题，且整体 ≥2 种题型」。
- **注意**：保持与 quick mode 的字段命名一致（`match_left`/`match_right`），避免模型输出 schema 不容的键。
- **验证**：
  - 单测/快照：断言展开后的 prompt 字符串包含 `matching` 与 `ordering` 关键词及格式示例。
  - `flutter analyze` 通过。

### Task ③.3 生成回归 + 随机模式透传确认
- **文件**：`lib/features/deep/deep_pipeline_controller.dart`（测试桩）；`database_helper.dart`（确认 `getSmartRandomQuestions` 不按 `type` 过滤）
- **改动**：无代码改动，纯验证。
  1. 用历史/固定 fixture（一段 deep generation 输出）跑 `parse` → 确认能产出 `matching`/`ordering` 题。
  2. **确认 `getSmartRandomQuestions` 的 SQL 不按 `type` 过滤**（调查阶段已见其只按 deck due 概念与冷却期排序，未排除类型；此处最终确认）。若意外发现按类型过滤，则新增 Task ③.4 放开该过滤。
- **验证**：
  - `flutter test` 全绿。
  - 端到端手测：用 deep mode 生成一个多主题牌组 → 随机模式后续关卡中能看到连线/排序题出现。

**DOD（③）**：deep 生成牌组含连线/排序题；随机模式能抽到并正确渲染（Widget 已存在，无需改 UI）。

---

## 验证总闸（Definition of Done，全局）

- [ ] `flutter analyze` 全绿
- [ ] `flutter test` 全绿（含 ① 徽章测试、② provider 钳制测试、③ schema 解析测试）
- [ ] 手动三关验收：① 显示 X/Y；② 设 20 随机关约 20 题；③ deep 牌组出现连线/排序且可作答
- [ ] 旧用户无设置时行为完全向后兼容（每关 5、总题量未显示与否不受影响）

## 提交纪律（Ship）

- 三个功能**各自独立 commit**（最好各开一个 openspec change，仿 `openspec/changes/structured-output-schema/`）。
- 不夹带无关重构；不删不改与本次无关的注释/代码。
- ③ 涉及 LLM 行为，合并前需真实跑一次 deep 生成确认题型多样，不能只看单测通过。

## 风险与未决项

- **未决（已降级）**：`getSmartRandomQuestions` 是否按 `type` 过滤——调查阶段未见过滤，Task ③.3 最终确认；若过滤则加 ③.4。
- **token 预算**：deep 生成更大牌组（若未来要把「每关题量」也作用于生成侧）会涨 token，本计划按假设 1 暂不覆盖，需时单列 change。
