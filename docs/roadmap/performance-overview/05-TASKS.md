# 子任务与依赖

15个任务；均NOT_STARTED，未启动实现。任务详情逐项包含需求、文件职责、依赖、验证方法、通过与失败边界。

| 任务 | 内容 | 阶段 | 依赖 | 需求 | 状态 |
|---|---|---|---|---|---|
| [PO-01](tasks/PO-01.md) | 现有开发交接与基线冻结 | R0 | 当前开发交接 | FR-01、FR-18 | NOT_STARTED |
| [PO-02](tasks/PO-02.md) | 拆分App外壳与存储界面 | R1 | PO-01 | FR-01、FR-09、FR-15 | NOT_STARTED |
| [PO-03](tasks/PO-03.md) | 定义性能领域契约与target | R1 | PO-01 | FR-07、FR-11、FR-15 | NOT_STARTED |
| [PO-04](tasks/PO-04.md) | 实现系统CPU、内存及卷采集 | R1 | PO-03 | FR-03、FR-04、FR-05、FR-11 | NOT_STARTED |
| [PO-05](tasks/PO-05.md) | 实现进程采集与身份差值 | R1 | PO-03 | FR-06、FR-07、FR-11 | NOT_STARTED |
| [PO-06](tasks/PO-06.md) | 共享采样会话与订阅调度 | R1 | PO-04, PO-05 | FR-08、FR-14 | NOT_STARTED |
| [PO-07](tasks/PO-07.md) | 性能详情与中文进程排行 | R2 | PO-02, PO-06 | FR-06、FR-07、FR-11、FR-16 | NOT_STARTED |
| [PO-08](tasks/PO-08.md) | 存储概览与任务只读适配 | R2 | PO-02 | FR-05、FR-10、FR-17 | NOT_STARTED |
| [PO-09](tasks/PO-09.md) | 全局概览组合与卡片 | R2 | PO-06, PO-08 | FR-03、FR-04、FR-05、FR-10、FR-11、FR-16 | NOT_STARTED |
| [PO-10](tasks/PO-10.md) | 菜单栏面板与主窗口路由 | R2 | PO-07, PO-09 | FR-02、FR-08、FR-09、FR-16 | NOT_STARTED |
| [PO-11](tasks/PO-11.md) | 设置、窗口关闭与退出协调 | R2 | PO-10 | FR-02、FR-12、FR-13、FR-14 | NOT_STARTED |
| [PO-12](tasks/PO-12.md) | 扩展边界与安全隔离验证 | R3 | PO-11 | FR-15、FR-17 | NOT_STARTED |
| [PO-13](tasks/PO-13.md) | 自动化回归与故障场景收口 | R3 | PO-12 | FR-01、FR-07、FR-08、FR-11、FR-13、FR-17 | NOT_STARTED |
| [PO-14](tasks/PO-14.md) | 原生交互、指标准确性与资源验收 | R3 | PO-13 | FR-02、FR-03、FR-04、FR-05、FR-08、FR-09、FR-10、FR-12、FR-14、FR-16 | NOT_STARTED |
| [PO-15](tasks/PO-15.md) | 独立构建、制品与交接验收 | R3 | PO-14 | FR-01、FR-18 | NOT_STARTED |

## 顺序与协调

PO-01先确认当前开发交接。PO-02与PO-03在文件职责明确后可分开推进；PO-04/05共享领域类型要协调。PO-06后接性能UI，PO-08接存储摘要，PO-09组合概览，PO-10菜单与路由，PO-11生命周期，PO-12至15验证/交付。
当前不安排并行开发；表内可分离不代表允许覆盖共享文件。Package.swift、App入口、Xcode项目由单一协调者修改。预估工期未给出，不用虚构工时替代任务验证。

## 需求与验收追踪

每个PO-FR-01至18在PRD映射同号PO-AC。任务可覆盖多项，关联AC须在最终同版本证据中收口；PO-13单元通过不等PO-14宿主通过。
后续完成记录写implementation/PO-xx.md，执行时才创建；记录基线、结果和未解项，不覆写原体验v2状态。本包README是新功能入口，原清理契约继续有效。
