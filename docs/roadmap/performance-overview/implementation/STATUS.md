# 性能整合开发状态

2026-10-13；DOING，goal active。仅已实现独立模块与开发预览，不能称主App合并完成，也尚未交人工验收。

## 本轮实际进展

- 用户更新授权为立即开始、持续检查其他AI改动、每功能验证后提交。当前先独占Packages/Performance，原存储负责人继续修改SQLiteScanStore；多次hash检查App入口、根Package、Xcode项目未变，仍不覆盖其工作。
- 三层性能模块及共享actor已实现；原始SDK结构、PID+启动标识、RSS/footprint分离、未知/权限/过期数据、排行、共享订阅、取消drain、睡眠基线、bounded stream。压力未验证来源明确unsupported，不用内存比例冒充。
- PerformanceUI及独立bundle开发预览已有性能详情、搜索排序、四张菜单卡片、设置；开发预览不打开清理数据库。
- 菜单选用NSStatusItem+NSPopover：显式DidShow/DidClose负责订阅，关闭后销毁面板内容，避免依赖SwiftUI保留视图判断生命周期。主App后续复用同实现。
- Release tests exit0，12项实际Swift Testing通过（不是上方XCTest 0 tests的空结果）。私有日志.local/performance-overview/release-tests.log。
- 原生CUA已观察进程表及搜索自身进程、菜单popover打开/ESC关闭、实时CPU/内存/启动盘卡。预览存储任务仍为尚未扫描，不是主App真实任务。

## 自检发现与限制

早期UI 99.9%与稍后top不同，增加同轮原始tick/reference/session对照后一致；不能声称已证明某个ABI/缓存根因。一次宿主用例错误假设idle必然增长而FAIL，实测负载期间idle确可不增长；移除该不属于产品契约的主机假设，保留数学口径和0–100范围校验。进程累计CPU经独立getrusage对照，0.8–1.2设计容差通过。

发现NSTableView动态更新reentrant警告，换只读ScrollView列式行减少系统delegate重入；最新source Release tests通过，最新新表格原生复验仍待完成。旧截图不可继承。

尚未完成：主App统一外壳/菜单入口、真实存储摘要和关闭/退出协调、偏好完整验证、第三功能接入证明、全存储回归、30次面板时延/50次切页、每模式5分钟3次CPU/RSS、扫描并行/多屏/辅助功能、最终同源制品和完整18AC审计。12测试不代表这些AC全部PASS。

## 提交

7a77f09：只读采样及规划文档。
8382ca1：共享采样及取消/复用回归。
UI与额外宿主校准将作为下一功能提交；不暂存另一AI的未跟踪清理代码。根工程起初无提交，因此不能用git add .创建混合基线。提交临时复用既有blog仓库配置的作者身份，只对单次commit指定，不改global配置。

## 续接

先核对当前工作区与原体验v2 CONTINUATION，再读Packages/Performance源码、release-tests.log及本文件。当前独立trace预览为验证进程，工具会话33683；不要启动第二collector或把旧运行binary当新source。需换版时只结束本轮创建的预览，不操作原LocalMacCleaner进程。

继续完善UI/缓存失败语义和设置；主App文件集成前重读并限定最小改动，必要时在私有copy和不同bundle下先验证，避免同bundle UI tests影响原开发。原清理Gate/schema/真实扫描保持原负责人边界。全部未验证项保持UNVERIFIED，最终完成前按PRD逐项证明。
