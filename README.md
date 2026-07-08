# 多多学 · Duoduo Learn (Deep Fork)

> 多邻国风格的自定义题库学习 APP —— 创建你自己的知识题包，AI 帮你拆题，游戏化打卡学习。

---

> [!IMPORTANT]
> **📜 版权与 Fork 声明**
>
> 本仓库是 [xuanli199/duoduo](https://github.com/xuanli199/duoduo) 的**二次开发增强版**（fork），基于上游 `main` 分支最新 commit。
>
> - 上游版权 © [xuanli199](https://github.com/xuanli199)，原项目采用 [MIT License](https://opensource.org/licenses/MIT)
> - 本 fork 版权 © 2026 YHlorra & duoduo-deep contributors
> - 完整协议见 [LICENSE](./LICENSE) · 上游说明见 [UPSTREAM.md](./UPSTREAM.md) · 变更记录见 [CHANGELOG.md](./CHANGELOG.md)
>
> 在保留原协议声明的前提下，本 fork 新增了**深度模式 (Deep Mode)**、SM-2 间隔重复、苏格拉底对话、JSON Schema 约束、概念页等能力。

---

## 这是什么

一款基于 AI 的个人题库学习 APP。粘贴一段学习材料（文本/图片/URL），AI 帮你自动拆成可练习的题目；每道题对应一个**概念**，答对答错都会被记录，SM-2 算法按记忆曲线安排下一次复习时间。

不是 Duolingo 复刻 —— 是你自己的学习材料 + 你自己的 AI 出题逻辑 + 你自己的复习节奏。

---

## ✨ 特性

- 🧠 **深度模式** —— 给一个学习目标，AI 联网查资料 + 抓 URL + 自动出题，从目标到题包全流程
- 📐 **跨厂商稳定输出** —— 自动探测 LLM provider 能力等级，输出不合规时自动降级
- 🔧 **JSON 自修复** —— LLM 输出不合规时本地先修，修不好再让 LLM 自己重写
- 🧮 **SM-2 间隔重复** —— 经典 SuperMemo SM-2 算法，答得越稳复习间隔越长
- 💬 **苏格拉底对话** —— 答错不直接给答案，反问引导你主动回忆
- 📚 **概念页** —— 所有题包的概念聚合成一张图，看你真正掌握了多少
- 📝 **多题型** —— 单选 / 多选 / 判断 / 填空 / 匹配 / 排序
- 🎮 **游戏化** —— XP / Streak / Hearts / 每日目标 / 月度打卡 / 21 个成就
- 🔒 **本地优先** —— 数据存本机 SQLite，API Key 存 SharedPreferences，不上云

---

## 📱 截图

### 首页
学习路径与每日目标

![首页](docs/screenshots/home.png)

### 题包导入
AI 拆题输入 + 解析预览

![题包导入](docs/screenshots/ingestion.png)

### 答题屏
题型交互 + 即时判题

![答题屏](docs/screenshots/quiz.png)

### 深度模式
目标收集 + 管道进度

![深度模式](docs/screenshots/deep.png)

---

## ✅ 适合 / ❌ 不太适合

**适合**

- 想用 AI 整理学习材料（粘贴文本/图片/URL → 自动出题）
- 需要间隔重复算法巩固记忆
- 偏好本地存储，不愿意把数据交给在线服务
- 想换不同 OpenAI 兼容 provider 实验

**不太适合**

- 需要跨设备同步（本地存储，不上云）
- 想要开箱即用的现成题库（这里没有，要自己喂内容）
- 上架 Google Play Store

---

## 📥 下载

前往 [Releases](https://github.com/YHlorra/duoduo-deep/releases) 下载最新 APK。Release key 签名，sideload 安装到 Android 设备即可。

最新版 [v0.1.1](https://github.com/YHlorra/duoduo-deep/releases/tag/v0.1.1)（57MB，39/39 tests ✅）。

---

## 📄 License

双重版权 © 2026：

- 原项目 [xuanli199/duoduo](https://github.com/xuanli199) —— MIT License
- 本 fork YHlorra & duoduo-deep contributors

完整协议见 [LICENSE](./LICENSE)。

---

## 🙏 致谢

- 原项目：[xuanli199/duoduo](https://github.com/xuanli199)
- 上游说明：[UPSTREAM.md](./UPSTREAM.md)
- 变更记录：[CHANGELOG.md](./CHANGELOG.md)
- 开源组件：见 `pubspec.yaml`
