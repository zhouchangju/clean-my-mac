# 性能整合开发职责

2026-10-13：用户更新授权，允许现在开始，在开发中持续检查其他AI改动，不必等原功能全部结束。

本轮先独占 `Packages/Performance/` 与本目录；不修改存储Domain/Core/Platform/Execution或正在编辑的App入口。独立Swift Package用于并发隔离，主App后续通过本地package产品接入。此工程细化替代原单根manifest方案，不改变单仓库、单App、多模块产品结构。

共享文件修改前重新核对hash/修改时间、最新体验v2状态与当前进程；源码活跃修改时不覆盖。不启动同bundle UI测试或操作另一AI正在运行的App。根README/Package/Xcode项目暂不提交。功能提交只暂存本轮负责文件；原工程尚无提交，不以git add .收录其开发中内容。

当前状态：性能Domain/Core/Platform可以独立实施；主App集成等待当前文件负责人交接或证明无重叠修改。清理Gate、数据schema与真实扫描任务继续由原开发负责。

## 接入阶段职责更新

私有完整App副本/独立bundle先构建成功后，在hash未变条件下仅追加App入口4处挂接及Xcode本地产品引用；新增PerformanceIntegration.swift由本轮独占。原App存储逻辑由另一AI继续编辑。对方已保留挂接并新增async index；本轮只在自己的桥接文件适配其新状态，不覆写LocalMacCleanerApp.swift。现有原生UI测试活跃时暂停本轮桌面交互，只做独立package/构建验证。
