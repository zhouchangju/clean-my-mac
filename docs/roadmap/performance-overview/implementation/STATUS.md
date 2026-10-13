# 性能整合开发状态

2026-10-13；DOING，goal active。已接入主App，功能开发与软件验收仍DOING；尚未交人工验收。

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

## 当前续接（以上早期记录仅作历史）

- 已有主工程接入：新增App/LocalMacCleaner/PerformanceIntegration.swift；App入口4处最小挂接与本地PerformanceUI产品引用。根Package和全部清理内核不改。主入口后续被另一个AI更新为async index，保留我们的UtilityRootView/@Bindable注入。不得拿早期baseline覆盖它的新初始化代码。
- 独立验证bundle com.localmaccleaner.performance-review，只用-lmcUITest自建目录。CUA确认统一导航与原存储界面，主动扫描32项/1缺口，菜单显示同一部分结果及已知占用/未知数；没有扫用户真实Data。
- 发现TimelineView.context.date可能是早于新样本的调度时间，造成新样本被未来时间判断误标过期；改用实际Date()，官方依据见Apple Context.date文档。新修复仍需fresh原生复验，不能继承旧画面。
- 新增失败数据独立lastKnownValue/lastKnownAt；质量仍failed而不是measured，不冒充0。设置立即作用于共享会话；慢间隔时效为3倍间隔（默认6秒）。NSWindow关闭/最小化/隐藏显式控制详情订阅。
- 修复快速重开pending acquire旧观察者可能结束新stream的竞态：UI renew lease，已取消acquisition不会替换健康订阅；有受控gate独立回归。
- Release最新17实际测试PASS，日志release-tests-current.log；App主构建main-build-async-index.log exit0。最新observationGeneration防旧存储观察者重挂的少量改动正在fresh构建（工具会话由本轮完成后更新，不将旧build继承）。
- 对方新增preparingIndex/indexPreparationError/prepareIndex；桥接已适配准备与失败，退出等待安全准备/扫描停止；超10秒取消退出并恢复采样/入口。
- 对方UI测试多次重启；发现live xcodebuild即停止本轮独立验证App。已精确停止本轮trace PID19168及review PID89906；两者终态，无本轮残留collector。不停止另一AI的App/test进程。

剩余：最新原生性能页/跳转/关闭后重开/退出验证，17测试后同版本全清理回归、第三功能接入证明、30次首画与50次切页、5分钟×3各模式资源样本、扫描并行/多屏/辅助功能、同源最终制品与18AC逐项审计。主App接入源部分仍未跟踪，另一AI清理源仍在开发；只提交本轮独占文件，共享App源码基线提交在交接明确后处理。
