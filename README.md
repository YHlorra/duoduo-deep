# 多多学 Duoduo Learn (Deep Fork)

> 多邻国风格的自定义题库学习 APP — 创建你自己的知识题包，AI 帮你拆题，游戏化打卡学习。

> **🪝 Fork 声明**
> 本仓库是 [xuanli199/duoduo](https://github.com/xuanli199/duoduo) 的二次开发增强版，基于上游 `main` 分支最新 commit。
> 原项目采用 MIT License，版权归原作者 `xuanli199` 所有。本 fork 在保留原协议基础上新增了**深度模式 (Deep Mode)**、SM-2 间隔重复、苏格拉底对话、JSON Schema 约束、概念页等能力。
> 完整差异与时间线见 [CHANGELOG.md](./CHANGELOG.md)。原项目声明保留在 [UPSTREAM.md](./UPSTREAM.md)。

---

## ✨ 核心特性

### 🆕 本 fork 新增

- 🧠 **深度模式 (Deep Mode)**：基于 tool-calling 的多步 LLM 推理管道，支持联网搜索 + URL 抓取，从目标自动构建可学习题包
- 📐 **JSON Schema 约束**：自动探测 provider 能力等级 (L3 / L2 / L1) 并优雅降级，跨厂商稳定输出
- 🔧 **JSON 自修复**：`json_extractor` 在 LLM 输出不合规时尝试本地修复，必要时 LLM 自愈
- 🧮 **SM-2 间隔重复**：经典 SuperMemo SM-2 算法，按记忆曲线调度复习
- 💬 **苏格拉底对话**：通过反问引导用户主动回忆，巩固薄弱概念
- 📚 **概念页**：按概念聚合卡片，可视化知识结构
- ⚙️ **设置页重构**：AI 配置 / 学习偏好 / 进度重置统一管理

### 来自上游（原版功能）

- 🏠 **学习路径首页**：按题包顺序学习，知识点模式 + 随机挑战模式
- 📝 **多题型支持**：单选 / 多选 / 判断 / 填空 / 匹配 / 排序
- 🤖 **AI 拆题**：粘贴文本、拍照识别、分享内容，AI 自动生成题包
- 🎮 **游戏化系统**：XP 经验值 / 连续打卡 Streak / 心数 Hearts / 每日目标 / 月度打卡 / 21 个成就徽章
- 🧠 **填空题 AI 判题**：本地不匹配时调用大模型语义判断

---

## 📱 截图

> 待 `docs/screenshots/` 填充 — 建议至少包含 6 张关键页（见 `docs/screenshots/README.md`）

| 页面 | 描述 | 文件 |
|---|---|---|
| 首页 | 学习路径与每日目标 | `docs/screenshots/home.png` |
| 题包导入 | AI 拆题输入 + 解析预览 | `docs/screenshots/ingestion.png` |
| 答题屏 | 题型交互 + 即时判题 | `docs/screenshots/quiz.png` |
| 深度模式 | 目标收集 + 管道进度 | `docs/screenshots/deep.png` |
| 概念页 | 概念聚合与掌握度 | `docs/screenshots/concepts.png` |
| 设置 | AI 配置 + 学习偏好 | `docs/screenshots/settings.png` |

> 截图未上传时，此处显示占位符。

---

## 技术栈

| 分类 | 技术 |
|---|---|
| 框架 | Flutter 3.5+ / Dart 3.x |
| 状态管理 | Riverpod |
| 本地存储 | SQLite (sqflite) + SharedPreferences |
| 网络请求 | Dio |
| AI 服务 | OpenAI 兼容 API（多厂商 + tool-calling） |
| 动画 | flutter_animate |
| 字体 | Google Fonts |
| 分享接收 | receive_sharing_intent |

---

## 项目结构

```
lib/
├── app.dart                    # 主应用入口 & 底部导航
├── main.dart                   # 应用启动
├── core/
│   ├── constants/              # 颜色、主题常量
│   └── providers/              # Riverpod 全局 Provider 定义
├── data/
│   ├── database/               # SQLite 数据库 Helper（含 v1→v2 迁移）
│   └── models/
│       ├── deck.dart           # 题包模型
│       ├── question.dart       # 题目模型
│       ├── app_prefs.dart      # 🆕 应用偏好
│       └── schemas/            # 🆕 JSON Schema 定义
├── features/
│   ├── home/                   # 首页（学习路径）
│   ├── deck/                   # 题库管理
│   ├── learning/               # 答题界面 & 题型组件
│   ├── ingestion/              # AI 拆题导入
│   ├── concept/                # 🆕 概念页
│   ├── deep/                   # 🆕 深度模式（pipeline / tools / 目标 / 进度）
│   ├── profile/                # 个人页（统计、成就、打卡日历）
│   └── settings/               # 设置页
├── services/
│   ├── gamification_service.dart   # 游戏化服务
│   ├── openai_service.dart         # AI 接口 + tool-calling 循环
│   ├── content_analyzer.dart       # 快速模式内容分析
│   ├── json_extractor.dart         # 🆕 JSON 解析与自修复
│   ├── output_constraint.dart      # 🆕 Provider 能力探测
│   ├── sm2_algorithm.dart          # 🆕 SM-2 间隔重复
│   └── socratic_dialog_service.dart # 🆕 苏格拉底对话
└── shared/
    └── widgets/                # 公共 UI 组件

test/
├── core/                       # 🆕 Provider 单元测试
├── features/deep/tools/        # 🆕 深度模式工具测试
└── services/                   # 🆕 服务层单元测试
```

---

## 快速开始

### 环境要求
- Flutter ≥ 3.5
- Dart ≥ 3.x
- Android SDK
- JDK 17+

### 安装运行

```bash
git clone https://github.com/YHlorra/duoduo-deep.git
cd duoduo-deep
flutter pub get
flutter run                       # 连接真机/模拟器
flutter build apk --release       # 出 Release APK
```

> 构建时如遇 Java Runtime 缺失，请设置 `JAVA_HOME` 环境变量指向 JDK 17。

### 配置 AI 接口

在 APP 设置页面中配置：
- API 地址（兼容 OpenAI 协议的任意接口）
- API Key
- 模型名称
- 高级：tool-calling 开关、Schema 约束等级

> 本 fork 不会上传你的 API Key 到任何服务器，所有配置仅存本机 SharedPreferences。

---

## 下载

前往 [Releases](https://github.com/YHlorra/duoduo-deep/releases) 页面下载最新 APK。

---

## License

MIT — 双重版权 © 2026 [xuanli199](https://github.com/xuanli199)（原版） + 2026 YHlorra & duoduo-deep contributors（本 fork）

完整协议见 [LICENSE](./LICENSE)。原项目说明见 [UPSTREAM.md](./UPSTREAM.md)。

---

## 致谢

- 原项目：[xuanli199/duoduo](https://github.com/xuanli199/duoduo) — MIT License
- 本 fork 使用的开源组件：见 `pubspec.yaml` 与各 LICENSE 头
