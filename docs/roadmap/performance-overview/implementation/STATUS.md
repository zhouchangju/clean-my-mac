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

## 最新交接点

94b72bf已提交App桥接/生命周期/失败历史值/17项回归；共享原App入口及pbx仍未跟踪，另一AI保留挂接并改async index，不覆盖、不混入其提交。

主App最新build-observation-generation与build-diagnostics-append均exit0；性能17tests exit0；原清理package regression报告53项正常退出（3 opt-in须按实际skip记录，不等完整M2）。

最新独立review bundle原生走查：性能页搜索自身进程与Footprint排序可用；CPU/内存/空间卡新样本不再误标过期；菜单CPU卡返回同一lmc-main性能页；Cmd-Q后PID73247已不存在，正常退出通过。点击关窗后CUA读取可能重新打开窗口，不能把该观察当隐藏状态验证。

为后续隐藏/资源验证新增-lmcUITest且-lmcPerformanceDiagnostics双开关，仅写本应用自建LMC-UI-*目录中的0600 performance-diagnostics.jsonl。数据只有本App pid/seq/订阅数/可见标题窗口数/扫描与准备状态/采样进程数/路由，不含进程名称或命令参数。追加记录不覆盖旧证据。最新诊断版本已build，未launch；本轮所有旧trace/review进程已结束，当前没有本轮活跃App/collector。

下一步：检查另一AI当前UI job与源改动；用最新main binary复制distinct performance-review bundle，带两个测试flag启动，查其自建目录log。用日志区分真正关窗和CUA自动重开，验证零订阅停止及重开；正常菜单/设置开关与扫描并行，30次面板/50次切页与5min×3资源模式，辅助功能/多屏、第三模块mock和最终18AC归档。再解决共享App基线提交与最终同源制品。不要把本轮原生分项或17tests记为全面完成。

## 2026-10-13 本轮续接点：资源采集中

当前实际进程：独立performance-review bundle PID28834，参数-lmcUITest -lmcPerformanceDiagnostics；没有打开真实用户索引。最新源码35文件hash在.local/performance-overview/current-source-before-build.json，build前后核对相同，current-build.log成功。

诊断路径/句柄：.local/performance-overview/active-diagnostics.json指向自建LMC-UI-E9CA924A-A235-4F76-84A9-03CC452FAC50/performance-diagnostics.jsonl。先读该文件和ps验证PID/command，不创建第二collector。

存储页baseline已完成，工具会话91063 exit0；实际300.0137秒、61样本、平均CPU0.0533%、RSS中位90.94MiB/最高93.06MiB、sequence始终0、subscriber0。原始resource-storage-baseline.json/jsonl。

详情资源collector工具会话81046，确认running：命令python3 .local/performance-overview/collect_resources.py detail --subscribers 1 --route performance --duration 930。当前默认完整进程排行、未搜索，记录每5秒；详情首105秒样本已有1个订阅、进程约1011、sequence54。继续轮询原handle；完成将生成resource-detail.json三组真实至少300秒区间。collector记录mode变化或源stale会终止并留failure，不能凭一次观察timeout重启。期间不要切换本App页面/菜单，否则详情数据失效。

扩展边界：临时副本添加第三摘要/独立路由/详情；Core/Domain/Platform所有文件hash不变，18项实际测试通过。production未加入测试功能；见EXTENSION-PROOF.md与私有extension-example-tests.log。

后续：detail完结后读三段CPU/RSS，接着overview（主窗口storage，打开面板，subscriber1，route storage）和both（性能页+面板，subscriber2，route performance），各930秒；hidden关窗需先从日志确认visible0/subscriber0，不调用CUA AX读取（可能重开），至少310秒。另补30次面板首画/50次切页、设置/重开/扫描并行/辅助功能/多屏、最终18AC审计及共享App基线提交。不要把存储baseline当hidden，也不要把临时扩展编译当生产存在第三功能。

本轮没有源码修改，只有验证与文档命令路径纠正。goal仍active，没有交人工验收。会话累计>50万token，已提醒用户/compact；压缩后按当前状态与实时工作区续接。

## 最新：详情资源FAIL及排行缓存修复

旧collector81046已exit1，非running。诊断源>10秒stale触发，原App PID28834仍活着并持续恢复日志；不能按失败collector再起重复。第一有效300.90秒段CPU5.65%（超过3%预算，FAIL），RSS中位107.31MiB/最高123.45MiB；仅一段有效，不是3组PASS。

sample 3秒指向每秒Timeline重排完整进程样本；新增controller ranking cache，新样本/search/sort变化失效，时效tick复用。Release18实际tests通过，宿主CPU校准改独立API前后上下界避开全进程枚举时间窗偏差。见AUDIT-REMEDIATION.md与所有保留日志。

新main-build-ranking-cache正在build（本轮结束后查进程/日志），未launch新版本；PID28834仍是旧binary。切换前确认另一AI UI job已结束，再只正常退出/停止本轮精确private review进程。新资源验证要新源hash、新binary；不得继承旧基线/18测试当全部软件PASS。goal active。

排行缓存修复的新main-build-ranking-cache.log已BUILD SUCCEEDED；原runtime PID28834仍旧binary，未启动新版本或新collector。18项Release tests已通过，新资源预算仍需fresh runtime复验。

## 最新续接：新缓存版本及50次原生切换

旧PID28834已精确SIGTERM且确认终态；已使用main-build-ranking-cache成功binary复制独立performance-review bundle并签名启动。binary与性能源hash：ranking-cache-runtime-manifest.json。当前新App PID50114，仅-lmcUITest -lmcPerformanceDiagnostics，自建目录LMC-UI-29CBE3B3-4B84-4D1B-B9A1-C2DD9C244464；active-diagnostics.json已指向新日志。

CUA 20+20+2+8次已确认性能/存储切换共50次；第43次一度AX树缺导航，重新读取原窗口恢复，再完成剩余8次，没有伪记失败为成功。最终storage日志subscriber0，sequence25；processSampleCount944为最后缓存，不代表继续枚举。原始native-switches-50.json；RSS终态约100MiB，缺同系列稳定前值，不将它直接记为增长<=10MiB通过。

已经切回默认完整CPU排行且无搜索，启动新collector：工具会话34368，命令collect_resources.py detail-cache --subscribers 1 --route performance --duration 930，PID50114。这是修复后新版本复验，不是重启旧失败collector；旧失败JSON与sample保留。先poll这个exacthandle，完成后读resource-detail-cache.json的3个真实>=300秒区间。期间不得改变当前页面/打开菜单；不要重复采集。

剩余完整验收与人工交付条件没有降低；goal active。

## 最新：新缓存版3组资源结果仍FAIL

collector34368已exit0，完成930.01秒；不是running，不重复启动。resource-detail-cache.json三段各>=300秒CPU分别3.164%、3.442%、4.238%，全部高于3%预算；RSS中位89.33/88.16/88.13MiB。数据完整但性能验收FAIL，不能把exit0当PASS。

新sample50114 3秒保留detail-cache-runtime-sample.txt。完整排行重算路径从早先747份主要栈降到22份（不同瞬时窗口，不是正式成本比例）；剩余SwiftUI布局/刷新还需定位。PID50114仍旧缓存版App存活、性能页1订阅，当前没有collector。换版本前验证精确进程，避免触及另一AI。

本轮50原生切换与resource结果已取得，尚未完成CPU修复/所有验收，goal保持active；下一步针对新sample确定第二批最小优化，再18tests/newbuild/new runtime重复3组，原FAIL全部保留。
