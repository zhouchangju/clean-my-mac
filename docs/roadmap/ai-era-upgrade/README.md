# AI 时代升级（AI Era Upgrade）文档包

创建日期：2026-10-14。状态：**本期五项功能已全部交付并通过验收（见
[implementation/STATUS.md](implementation/STATUS.md)）**；后续阶段见
03-TASKS.md。

目标：把 Local Mac Cleaner 从"只读空间分析工具"升级为适配 AI 时代使用方式的
Mac 清理与体检工具：吸收腾讯 lemon-cleaner 的交互分析精华（空间地图下钻、重复
文件、大文件分类、垃圾规则库），融合本地磁盘/内存 Guardian Skill 作为"专家体检
引擎"，并内置本地 AI Runtime（Codex CLI / OpenCode 等）的检测与调用，用 AI
方式完成空间分析与清理建议。

## 文档索引

| 文档 | 内容 |
|---|---|
| [01-PRD.md](01-PRD.md) | 需求背景、第一性原理审视、功能需求、非目标与安全契约 |
| [02-TECH-DESIGN.md](02-TECH-DESIGN.md) | 架构、模块划分、数据流、接口契约、GPL 清洁室边界 |
| [03-TASKS.md](03-TASKS.md) | 任务拆解（4 个并行工作流）、验收标准、依赖关系 |
| implementation/ | 各任务实施状态与证据（实施时填写） |

## 一句话范围

本期交付（全部只读分析 + 协议受控动作，不触碰执行门）：

1. **AI 中心**（新顶层页面）：AI Runtime 自动检测 / 默认 Runtime 设置 / 选择
   Runtime 执行空间分析（推荐 + 解释，不执行删除）。
2. **体检中心**（AI 中心内）：调用 `mac-storage-guardian` / `mac-memory-guardian`
   Skill 的只读审计，友好呈现结果与建议；内存体检在 Skill 协议门控下提供受控
   终止闲置 Codex 进程动作。
3. **空间地图 v2**：全页矩形树图（squarified），支持点击下钻、面包屑、前进/
   后退、悬停详情、权重压缩与 top-N 截断。
4. **重复文件分析**：尺寸分桶 → 头部哈希 → 全量哈希三段漏斗，只读结果页。
5. **大文件分类与规则扩充**：文件类型分类（含 AI 模型类型）+ lemon 规则路径
   表中安全可移植的部分以 previewOnly 规则形式扩充种子规则库。

## 边界声明（继承既有契约）

- `ExecutionGate.enabled = false` 保持不变；本包所有功能不新增任何删除执行路径。
- lemon-cleaner 为 GPLv3/GPLv2，**不复制其任何代码**，仅清洁室重实现公开算法
  （squarified treemap、哈希漏斗等）并以事实性路径知识重写规则表。
- 性能预算不回归：新功能全部按需触发，无定时器、无后台轮询。
