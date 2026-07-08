# Upstream

本 fork 派生自 [xuanli199/duoduo](https://github.com/xuanli199/duoduo)。

## 元信息

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/xuanli199/duoduo |
| 上游协议 | MIT License |
| 原作者 | xuanli199 |
| Fork 起点 | 上游 `main` 分支 commit `ac377ab` (2026-07-06) |
| Fork 仓库 | https://github.com/YHlorra/duoduo-deep |
| Fork 维护 | YHlorra |

## 同步策略

本 fork **不主动同步上游**。理由：

1. 改动方向差异大（深度模式、SM-2、苏格拉底对话、Schema 约束等均为本 fork 专属方向）
2. 同步将引入大量冲突，人工合并成本高于价值
3. 上游如有重要安全 / 稳定性更新，会 cherry-pick 关键 commit

## 通用变更的回馈

本 fork 中**通用、与业务弱耦合**的部分（如 `json_extractor`、`output_constraint`）可作为独立 PR 回流上游。是否回馈由维护者逐项评估。

## 上游 LICENSE 说明

上游未在仓库放置独立的 `LICENSE` 文件（仅在 README 标注 MIT）。
本 fork 自带 [LICENSE](../LICENSE) 文件，包含原作者与本 fork 维护者的双版权声明，符合 MIT 协议关于"保留版权声明"的要求。

如需参考原始协议文本，可访问 https://opensource.org/licenses/MIT
