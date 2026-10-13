# 性能监控整合与菜单栏概览：后续开发文档包

版本 v0.1，2026-10-13。状态：**DOING；用户已授权立即开发，当前实现进展见[STATUS](implementation/STATUS.md)**。

用户要求：以当前 clean-my-mac 为主工程，将 find-mac-performance-issues 的性能监控能力整合进来；增加菜单栏全局概览，并为后续功能保留扩展边界。用户随后更新为现在开始、持续检查其他AI改动；可独立实现的模块先推进，共享文件改动仍需避免重叠。

本包不替换现有清理 PRD、执行契约或正在进行的体验 v2 计划。任何清理执行限制仍以现有契约及届时实际状态为准。只读监控整合不以清理 M2 全部完成为前提，但必须通过当前开发交接与基线冻结。

## 阅读顺序

| 文档 | 内容 |
|---|---|
| [01-PRD](01-PRD.md) | 场景、范围、需求编号、产品行为及阶段 |
| [02-TECHNICAL-DESIGN](02-TECHNICAL-DESIGN.md) | 流程、架构、技术难点、接口与状态 |
| [03-DIRECTORY-AND-MIGRATION](03-DIRECTORY-AND-MIGRATION.md) | 目标目录、文件迁移、target 依赖与数据兼容 |
| [04-ACCEPTANCE](04-ACCEPTANCE.md) | 验收案例、独立判据、资源预算与证据 |
| [05-TASKS](05-TASKS.md) | 子任务总表、依赖、交付范围及逐任务文件 |
| [06-HANDOFF](06-HANDOFF.md) | 启动条件、开发交接 Prompt、失败处理 |
| [07-DECISIONS-AND-SOURCES](07-DECISIONS-AND-SOURCES.md) | 已确认需求、设计建议、来源、未决事项 |

## 启动边界

当前体验 v2 的 [STATUS](../../implementation/experience-v2/STATUS.md) 会持续变化。本包不复制它的实时状态，也不将今天的失败或成功视为启动时的最新事实。
先执行 [PO-01](tasks/PO-01.md) 的交接：由当前开发负责人交出最终源码和验收记录，确认没有重叠写入，再记录基线；之后才开始修改源码。

任务文件已更新为实施状态；完整验收缺口见[验收状态](implementation/ACCEPTANCE-STATUS.md)，详细历史见implementation/STATUS.md。未完成的软件验收仍UNVERIFIED。文档链接、编号和依赖检查通过不代表软件通过。用户已在本次会话授权开发与逐功能本地提交；这不授权修改用户现有文件、退出用户进程、安装、发布或清理现有数据。

## 交付目标

一个仓库、一个原生 App、两个展示入口：主窗口处理完整工作流；菜单栏面板提供当前状态、既有扫描摘要及跳转。两入口共享服务，核心模块按功能隔离。首版包含 CPU、内存、启动卷空间、当前存储任务、性能详情；电池及其他能力后续单独评估。
