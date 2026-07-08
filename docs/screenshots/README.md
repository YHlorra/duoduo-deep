# Screenshots

> 本目录存放 README 引用的项目截图。

## 拍摄清单

**当前状态**：已截 6 张（`home` / `deck` / `deep` / `ingestion` / `quiz` / `profile`），剩余 2 张（`concepts` / `settings`）待补。

| 文件名 | 截取页面 | 关键内容 | 大致尺寸 | 状态 |
|---|---|---|---|---|
| `home.png` | 学习路径 (`HomeScreen`) | 单元链 + 资源栏 + 底部 Tab | 1080×2400 | ✓ |
| `deck.png` | 题库列表 (`DeckListScreen`) | 搜索框 + 题包卡片 + 进度 | 1080×2400 | ✓ |
| `deep.png` | 深度模式目标 (`GoalCollectionScreen`) | 学习目的 + 水平选择 + 参考链接 | 1080×2400 | ✓ |
| `ingestion.png` | 题包导入预览 (`DeckPreviewScreen`) | 题目预览 + 解析 + 保存按钮 | 1080×2400 | ✓ |
| `quiz.png` | 答题屏 (`QuizScreen`) | 题目 + 选项 + 判题按钮 | 1080×2400 | ✓ |
| `profile.png` | 个人中心 (`ProfileScreen`) | 用户资料 + 统计 + 月度打卡 | 1080×2400 | ✓ |
| `concepts.png` | 概念页 (`ConceptListScreen`) | 概念列表 + 掌握度 | 1080×2400 | ⏳ |
| `settings.png` | 设置页 (`SettingsScreen`) | AI 配置 + 学习偏好 | 1080×2400 | ⏳ |

## 拍摄步骤

1. 准备真实数据：跑一次完整流程，导入 1-2 个题包，至少触发一次深度模式生成。
2. 切换到**深色 / 浅色** 两套主题各截一遍（最终选一套主推）。
3. Android 截屏快捷键：`adb shell screencap -p > out.png`，或设备组合键。
4. 导出 PNG 后放到本目录对应文件名。
5. 提交时连同 `pubspec.yaml` / 截图一起 commit。

## 注意事项

- 截屏前**清掉敏感信息**（API Key、个人题包名、用户头像）。
- 优先展示**空状态** + **有数据** 两个版本（README 各 1 张就够）。
- 若使用模拟器，建议分辨率 1080×2400（Pixel 6 默认）。
- 不要截到 IDE 调试信息或性能浮层。
