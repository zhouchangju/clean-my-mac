# 目录组织与迁移方案

这是后续目标，不是当前文件树；先通过 PO-01，实施时按任务逐步迁移。

## 1. 目标目录

```text
clean-my-mac/
  Package.swift
  App/
    LocalMacCleaner.xcodeproj/
    LocalMacCleaner/
      LocalMacCleanerApp.swift
      Shell/
        AppRootView.swift
        AppRoute.swift
        AppDependencies.swift
        AppLifecycle.swift
        MenuBar/MenuBarOverviewView.swift
      Features/
        Storage/StorageModel.swift
        Storage/Views/
        Performance/PerformanceModel.swift
        Performance/Views/
        Overview/OverviewModel.swift
        Overview/OverviewSnapshot.swift
        Overview/Views/
        Settings/
      SharedUI/MetricCard.swift
      SharedUI/MeasurementStatusView.swift
      Resources/
    LocalMacCleanerUITests/
  Sources/
    CleanerDomain/
    CleanerCore/
    CleanerMacPlatform/
    CleanerExecution/
    CleanerCLI/
    PerformanceDomain/
    PerformanceCore/
    PerformanceMacPlatform/
    CSQLite/
  Tests/
    CleanerCoreTests/
    CleanerPlatformTests/
    CleanerExecutionTests/
    PerformanceCoreTests/
    PerformancePlatformTests/
  TestSupport/
    Storage/
    Performance/
  Resources/Rules/
  scripts/
  docs/
    development/
    implementation/
    roadmap/performance-overview/
  .local/
```

首版不为尚未开发的功能建立空目录。Overview 位于 App，是组合视图，不是底层指标服务。现有 TestSupport 可暂时保留，只有实际需要时才移动并调整 manifest。规则、研究文档与正在开发的实现证据不做批量改名。

## 2. Target 依赖

| Target | 允许依赖 |
|---|---|
| CleanerDomain | 保留现有 |
| CleanerCore | CleanerDomain |
| CleanerMacPlatform | CleanerDomain、CleanerCore、CSQLite |
| CleanerExecution | CleanerDomain |
| CleanerCLI | 保留现有 CleanerMacPlatform、CleanerCore |
| PerformanceDomain | Foundation，纯数据与采集协议 |
| PerformanceCore | PerformanceDomain |
| PerformanceMacPlatform | PerformanceDomain，系统框架 |
| PerformanceCoreTests | PerformanceCore、测试适配器 |
| PerformancePlatformTests | PerformanceMacPlatform、PerformanceDomain |

App 引用所需 library product 并装配服务。采集实现注入 Core；不能让 Core import MacPlatform。Xcode App target 必须显式纳入新 Swift 文件，当前 project 不能假定目录新增自动编译。Package.swift 暴露 product，Xcode 同步添加 packageProductDependencies。

首版沿用一个根 Package、多 target。只有模块出现独立版本/发行/复用需求时才拆独立 package。模块边界通过 import 与依赖图约束，不靠文件夹命名。

## 3. 旧代码映射

| 旧项目来源 | 目标 | 迁移要求 |
|---|---|---|
| Services/SystemMonitor.swift | Platform原始采样 + Core差值 | 校准CPU计数、首样本与失败状态 |
| Services/ProcessMonitor.swift | Platform进程采集 + Core进程差值 | 确认时间单位、PID复用、权限失败及数据来源 |
| Models/ProcessData.swift | PerformanceDomain纯快照 | 去NSImage，改可选/质量状态，真实启动身份 |
| ViewModels/ProcessListViewModel.swift | PerformanceModel + 共享会话 | 去硬编码/tmp日志、全局焦点定时器和重复订阅 |
| Views/DashboardView.swift | Performance/Overview卡片 | 中文、不同指标口径、未知状态与辅助功能 |
| SettingsView.swift/SettingsService | 功能设置适配 | 不直接搬全局单例；实际读取并验证设置 |
| AlertManager.swift | 首版不迁移 | 后续阈值策略/通知适配另定 |
| ProcessKiller.swift | 首版不迁移 | 后续独立执行模块；不能仅按PID阈值保护 |
| main.swift/打包脚本 | 不迁移入口 | 只保留clean-my-mac入口与构建体系 |

从已读源码知道旧模型含 NSImage、startTime 使用采样时间、footprint 失败回退虚拟内存。不得把旧测试全绿当成新口径正确；旧测试仅作为迁移线索。

## 4. 原生与数据兼容

保留 App target、bundle ID、既有 Application Support 根及 lmc CLI 行为。显示名暂不更改。性能设置用 performance.*，概览设置用 overview.*；旧独立 App 的 UserDefaults 不自动导入，后续若确有需要再设计显式迁移。
现有 index.sqlite、plans、transactions、receipts、staging、忽略和规则不因整合迁移。首版性能历史仅有限内存窗口，不写清理数据库。日志进入私有本应用路径并有上限，不记录完整进程参数或用户内容。
存储摘要从现有Store读取，禁止直接读SQLite并再实现一套聚合。如果读取必须经过App模型，先定义窄只读适配器，不用性能模块读取 CleanerModel。

## 5. 扩展约定

新功能先明确独立问题、测量来源、生命周期、数据位置、操作边界和验收；新增必要target与Features目录，在AppDependencies装配，在AppRoute添加路由，概览按静态明确类型接摘要。
不要预建万能执行器、事件总线、动态插件加载或统一庞大状态库。已有两个消费者需要同一能力后再提取共享实现；第三个功能接入时评估小型摘要协议。
具有文件变更或进程退出的功能必须独立设计执行接口与恢复/结果，不能借只读摘要获得授权。

## 6. 迁移与回退

先冻结交接基线，拆App不改行为，再新增target，再接两入口。每步独立验收；旧源工程保持完整，未验收前不删除。性能与菜单可分别由UI设置关闭，服务仍正确释放。
回退以恢复相应代码基线/关闭新入口为主；性能功能不改变清理数据库schema，因此不能用回退恢复或删除用户文件。所有既有存储schema修复归原开发计划，不纳入本次迁移。
