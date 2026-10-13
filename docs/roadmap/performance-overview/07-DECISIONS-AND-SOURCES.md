# 决策、来源与待确认项

2026-10-13。这是设计记录；不代表实现已完成或软件已验收。

## 用户已确认

- clean-my-mac为主工程，整合find-mac-performance-issues性能监控。
- 要考虑未来继续整合其他功能。
- 菜单栏小型全局概览适合纳入后续方案。
- 本轮写文档、拆任务；等正在开发的功能完成后再实施。

## 建议采用的决策

一个App、两个UI入口、多功能target；沿用Swift6/macOS14+基线、identity与存储路径。先按需只读监控，不引入后台daemon、独立helper或动态插件框架。概览是组合层，不是新的采集模块。
首版不迁移旧进程退出与告警，不增加电池/温度等能力。预算和时效阈值是待验证设计参数。
共享逻辑不按想象提取；发生真实复用后再抽象。未来性能模块可独立package，但当前无必要。

## 当前源码依据

- [根Package](../../../Package.swift)：清理Domain/Core/Platform/Execution及CLI target。
- [App入口](../../../App/LocalMacCleaner/LocalMacCleanerApp.swift)：当前入口、导航、模型与视图集中。
- [活动判断](../../../Sources/CleanerMacPlatform/Activity.swift)：unknown不能推导inactive。
- [执行Gate](../../../Sources/CleanerExecution/Gate.swift)：原执行边界。
- [体验v2状态](../../implementation/experience-v2/STATUS.md)：持续更新，启动前重读。
- [原PRD](../../development/01-PRD.md)、[原架构](../../development/02-ARCHITECTURE.md)：本包只扩展只读入口，不替换清理契约。
- 源项目位于本机 /Users/leozhou/git/find-mac-performance-issues/MacPerformanceMonitor/。该绝对路径是当前机器线索，不是新App运行依赖；交接另一机器时需提供有范围的源码副本。

## 外部一手资料

查阅日期2026-10-13。外部功能存在不证明本项目实现、资源预算或内部架构。
- [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)：原生菜单栏入口。
- [Apple window style](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window)：卡片面板的候选实现。
- [Swift target](https://docs.swift.org/latest/documentation/packagedescription/target/)：模块和声明式依赖。
- [Swift concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)：actor与Sendable。
- [CleanMyMac Menu](https://macpaw.com/support/cleanmymac/knowledgebase/the-menu)：CPU/内存/存储等组合参考。
- [Stats官方仓库](https://github.com/exelban/stats)：独立监控形态参考，不引入其代码或依赖。

用户截图用作信息架构参考，不复制到仓库；图中的进程名、设备名与现状不作为本项目指标或测试数据。

## 待实施时核实

1. CPU原始API实际单位与时间源；选稳定的单调时钟，不复制旧实现注释当事实。
2. 系统压力等级来源是否可无提权稳定读取；不能证明则展示unknown，FR仍满足诚实状态要求。
3. 启动数据卷可用空间API口径、卷定位和挂载变更处理。
4. MenuBarExtra面板的可见性订阅、窗口激活与多屏行为；真实不满足后才改AppKit实现。
5. 当前开发结束后的Store摘要/任务/恢复状态接口，优先适配实际接口。
6. 资源预算与当前宿主噪声；未测不写PASS，必要调整需记录理由并更新FR/AC/任务。

这些工程问题可按已定范围解决，无需把例行实现选择变成新产品审批。新增后台监控、写操作或其他功能需要另定需求。
