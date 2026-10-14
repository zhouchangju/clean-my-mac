# 体验 v2 独立源码审查

2026-10-13，10:16工作中快照。仅写本文件，不修改源码/测试/原始证据；其他协作者仍在工作。依据PLAN/V2验收、官方研究与本机runtime研究、所有新增Domain/Core/Platform/App源码与测试。Git尚无已跟踪开发diff，因此不虚构commit；以当前源码和`.local/source-reproduction`的前版作局部只读比对。竞品研究是设计输入，不是本产品PASS证据。

## Findings

### [HIGH] 旧索引迁移忽略SELECT执行错误，仍提交新版本

File: `Sources/CleanerMacPlatform/SQLiteScanStore.swift:48`–`:61`。

Issue: 迁移SELECT含 `json_extract(json, ...)`，while只判断 `sqlite3_step(rows)==SQLITE_ROW`，结束后不要求SQLITE_DONE。旧行JSON损坏导致SQLITE_ERROR时，循环结束并继续 `PRAGMA user_version=2; COMMIT`；坏索引没有被拒绝，未迁移行默认category/计数为other/0。table_info/user_version/prepare也有未检查返回码。损坏与真实空结果不能混淆。

Evidence: 本审查Python SQLite内存数据库执行相同窗口SELECT，单行 `json='{'`，实际输出 `OperationalError: malformed JSON`（命令exit0，因为明确捕获并打印错误）。这证明查询错误路径；尚未独立运行Swift故障索引初始化反例，源码控制流已可确定会把非ROW当循环正常结束。现有迁移测试只覆盖合法旧行。

Fix: 逐prepare/step核验SQL状态，循环最终必须SQLITE_DONE，所有失败显式ROLLBACK并保持user_version未升级。增加损坏JSON/prepare失败/中途错误fixture与重开数据库检查，不改变已有合法迁移expected。

### [MEDIUM] 硬链接去重统计与同层地图权重不一致

File: `SQLiteScanStore.swift`的`readEntries/children`；`App/LocalMacCleaner/LocalMacCleanerApp.swift:744`、`SpaceMap.partition`。

Issue: Store根/目录聚合和分类按inode的counted_allocated去重，但返回非目录Entry仍是原始stat allocated；SpaceMap直接把每个路径的raw allocated当面积。目录中普通文件a及其硬链接link各4096B时，父聚合为4096B，下钻却有两个4096B tile；再加入独立4096B文件b，地图为三份各1/3，而实际已知对象a与b各占1/2。文件原始stat显示可以保留，但占用地图不能把同一对象再次计面积。

Evidence: 现有`v2DashboardAndChildrenNeverDoubleCountTreeOrHardlinks`确实构造Documents/a.txt与link.txt，children两行仍各logical4096且map输入没有counted/unique字段；测试只断言根/category去重，没有覆盖地图weight。该反例为源码与现有真实fixture的组合推导；本审查未运行原生硬链接地图截图。

Fix: 地图采用去重对象权重（区分文件stat与计量贡献），或合并同inode为共享对象tile并明确路径数；列表保持真实stat和共享说明。补同层图weight sum与parent聚合一致的独立oracle，避免把用户文件原始allocated悄悄改成0。

## 保守边界与实现核对

- 新预设默认Data卷，只做scope/volume metadata解析，未自动枚举；用户点击才scan。生产挂载检查确认`/System/Volumes/Data`，Data别名仅在RuleEngine判定规范化，FileReader仍anchored真实scope路径。
- analysisMode测量app/repo但继承protect；直接选仓库子目录也经repositoryAncestor保护；Home/Data容器没有让整棵用户数据成为protect。凭据、AI会话/配置、其他用户未验证AI根、云同步、LMC状态依旧不深入。AI允许容器的隐藏兄弟使partial有显式缺口。
- 分类只是metadata用途归组，不授予删除；看板缓存建议计数仅candidate+RULE-DEV/AI命中，不凭Caches名字生成准入候选；缓存previewOnly、规则0/2、Activity unknown和Gate=false未改变。
- children同层/根排除，与全树catalog分离；地图只取本页前12项且说明零/未知未画。看板容量/可用来自本地卷API，已知分配明确不是可释放量；partial/cancelled/error有独立状态文案。大量全盘/权限行为仍需host证据。
- 新JSON压缩parentChain并根据父行hydration重建，fixture对首祖先根身份已验证。INSERT批次overflow/配额guard与transaction rollback仍存在，分类总额正常fixture与根统计一致。损坏DB/恶意父环/全量migration quota/目录对抗替换未全验，不泛化局部成功。
- App真实服务链为ScanCoordinator→SQLite dashboard/children/catalog→Planner/Preflight。查询/扫描/计划代次校验存在，scope变化清空结果选择/plan；原生确认按钮硬禁用，未见v2产生执行入口。
- 本轮Export修正已读：默认相对路径脱敏Users后用户名、当前用户名片段及常见秘密名称；完整路径仅explicit includeFullPaths。`exportRedactsDataRootUserAndPrivateNames`在本次独立测试通过。此为有限脱敏规则，不证明任意文件名无隐私。

## 实际检查与未测试限制

本审查独立 `swift test --skip Benchmark --skip systemTrash`：2026-10-13 10:14:28，exit **0**，**32 tests通过**。包含新preset metadata、Data alias保护、app/repo计量保护继承、分类与真实建议、同层children/catalog、硬链接统计、合法迁移、旧预检以及Export脱敏。只操作测试新建Fixture；没有Data/Home全盘扫描、没有Trash动作、未提权、安装或发布。

Python SQLite内存 malformed JSON实验如上。源码/文档读取和局部旧版diff均只读。未独立运行v2原生UI、Release构建/启动或看新增截图；不复用旧Release证据。当前3项XCTest正在由协作者跑，不能提前记PASS。新UI assertions至少仍保留一击预设无NSOpenPanel、真实分类看板、同层下钻/breadcrumb、空筛选/排序、真实plan且执行disabled。现有UI下载建议只断言search存在，不能单凭此证明分类列表内容正确。

主盘完整coverage、读内容spy/权限拒绝/云占位/挂载边界、取消迟到回调、全状态UI、VoiceOver、性能主线程busy和真实大目录均不能由本次单测替代；保持UNVERIFIED。旧M2清理/恢复仍BLOCKED，v2改进不能被当成完整v1清理交付。用户仍需实际接受新看板、建议与地图体验。

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 1 | warn |
| MEDIUM | 1 | info |
| LOW | 0 | note |

Verdict: WARNING — 迁移失败必须拒绝；地图共享对象计量需修正。只读v2正在复核，M2继续BLOCKED。

## 修后独立复核（10:23）

初审问题与实验原样保留。迁移SELECT已核验prepare，并保存每次step状态，最终必须SQLITE_DONE；失败由defer显式ROLLBACK，COMMIT后才标migrationCommitted。新增malformed旧JSON反例检查初始化throws、数据库user_version仍0、category列未新增；合法迁移expected未缩小。原HIGH结案。table_info/user_version仍未逐返回码检查，未发现现有错误路径会越过后续guard产生已确认错误升级，不将假设故障扩成新的finding。

地图新增独立mapWeights读取：目录用aggregate_allocated，叶子用counted_allocated；App根据当前同层rows IDs（默认100项、上限1000）取weight，rows/weights在同queryGeneration guard后同时发布。SpaceMap过滤、partition和显示面积字节均改用weight，列表仍显示原始stat。未重复计量的共享路径保留列表并标“共享·已另计”；前12项地图明确为本页比例，不声称整个目录。新增跨目录/同目录3个hardlink案例，确认只有一次非零贡献、每层weight sum与父aggregate一致、原始stat4096不改、ids限制返回严格匹配。原MEDIUM结案。

本审查独立 `swift test --filter v2`：2026-10-13 **10:22:58，exit0，7 tests PASS**。包含上述两个修正、合法迁移、真实dashboard/children、保护计量、preset metadata与Data根纯metadata核验；未扫描Data/Home、未运行系统Trash。SwiftPM等待已有构建结束后才运行，未终止协作者进程。另核对`experience-v2-platform-review-final.log`7项通过与`experience-v2/core-regression.log`10项通过（协作者运行），不冒充独立执行。

新版本证据核对（协作者运行，未由本审查重跑GUI/Release）：

- `.local/experience-v2-ui-02.log`：3原生测试、0失败、TEST SUCCEEDED（10:19:18），看板→同层地图/下钻/面包屑→真实大文件计划确认disabled、快捷preset、1000深色键盘搜索/排序与空Fixture均为新源码链。数据oracle由fixture/core证据补充，UI只存在控件不替文件安全/筛选expected。
- 深色UI02截图被其他App覆挡，不能作视觉通过证据。`.local/experience-v2-ui-dark-03.log`单例再次成功（10:21:59）；本审查未独立看其新截图像素，视觉状态须由实际查看者负责。
- `.local/verification/experience-v2/release-build.log`新路径BUILD SUCCEEDED；旧Release不继承。独立dist签名/启动与hash仍由制品负责人形成新回执，本审查此轮没有校验新binary。
- 新50k日志固定50102项，实占204800000B；三次wall **47.115/25.045/22.557秒**，RSS峰值 **16,449,536/18,956,288/18,956,288B**。日志明确uncontrolled-warm、mainThreadBusy=UNVERIFIED。当前PRD没有wall≤30秒预算，不能制造该FAIL；RSS满足≤500MiB，三个wall均保留，不能挑最快一次。前版更快的观察应作为性能回归调查输入，条件未完全控制不能伪造精确归因或宣称全盘耗时。

原文全局测试32项不包含这两个后续新负例，已由上述7项独立补验。准入、活动、生产Gate、旧Trash未知/恢复限制未变化。新只读看板/快捷范围/建议/地图实现继续交付，不因旧M2阻塞停止体验范围；完整用户体验接受、真实Data bounded扫描/取消、权限coverage与资源主线程仍须实际证据。README和用户说明应明确“本轮只读体验已实现及分项验证”与“原v1清理恢复M2未完成”，不能把两者混成全部没做或完整清理已完成。

## Review Summary（修后）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 已报告v2源码问题修正后无确认的残余问题；适用于当前只读体验与Gate=false实现。性能主线程、完整host覆盖和用户体验验收仍未完成；原M2继续BLOCKED。

## schema3 索引维护再审（10:46）

schema3是新的源码范围，上节Approve不能继承为本次完成。读取新retireTerminalScans/archived summary、owner/nlink/dev/inode/HAS_MOVED核验、App ownStorageURL与maintenanceMayRun/cancel流程、ScanRun.stopReason向后兼容与Scanner赋值、dashboard/catalog global gap、全部Maintenance Fixture及新日志。

独立命令：`swift test --scratch-path .local/independent-review-index-schema3-20261013 --filter 'v2.*(Maintenance|SQLiteFull|StoppedRun|ReadableBranches)'`，全新scratch实际编译，2026-10-13 **10:45:56，exit0，6 tests PASS**。未扫描Data/Home、未操作系统Trash、未清SwiftPM缓存、未终止其他进程。覆盖旧已终结扫描清退→保留摘要→VACUUM同inode缩小→新scan成功，running/protectedScanIDs不清退、仅freelist压缩、替换/hardlink拒绝、old JSON兼容、读权限缺口不误标全局停止、SQLite13 full停止并全局未知且目标sentinel不变。

观察到的边界：维护仅删除应用索引entries/measured，scans JSON与ArchivedScanSummary保留；预先检查可用临时空间，事务失败rollback，VACUUM前后再次核验index/parent身份和SQLite HAS_MOVED。App新scan前清空选择/旧plan，maintenanceMayRun仅枚举本应用stateScope；transactions/receipts/plans/staging任一存在非目录/symlink、不可读或非空即保守不清退，未读取用户selectedScope判断维护资格。维护中scanning仍true阻止新scan，停止置cancelling后在coordinator建立前guard退出，不会因为cancel重新扫描。跨进程检查到操作之间仍有TOCTOU窗口，属于未来真实事务集成必须重新证明的边界；当前Gate=false且无生产executor，不制造当前误删finding。

root/batch/quota/取消的全局中止写stopReason；普通子目录permission gap继续扫描且不写全局stop。无root入库时summary保留globalUnknown≥1，dashboard/catalog提供protect synthetic gap。App noSuccessfulMeasurement将提前停止未计量展示为“未成功计量/未知”，不能冒充空目录。`real-host-first-scan.json`旧版200处理、0提交、index266158080超过quota262144000的 **FAIL**保留；该真实host失败不是已完整测量0，修后Fixture不替修后hostData接受。

原始共享build SIGSEGV失败记录不得删掉；fresh同源码不复现只能记录“本次fresh通过”，不能推出缓存为确诊根因或原故障不重要。`.local/verification/experience-v2-index-maintenance-verified.log`42项通过由协作者运行，benchmark跳过/Trash拒绝分支必须分开。`.local/experience-v2-ui-quota-06.log`新quota原生单例成功（10:39:49，TEST SUCCEEDED）；已知像素检查由负责人提供，本审查只核对日志和源码，未看其截图。

### [MEDIUM] 过滤掉synthetic global gap时分页仍减offset

File: `Sources/CleanerMacPlatform/SQLiteScanStore.swift:316`–`:321`（catalog）。

Issue: `issue != nil`即将所有后续SQL offset减1，但是否实际将synthetic gap插入第一页另由search/category/large/candidates条件决定。stopReason存在，搜索仅匹配真实“denied”缺口而不匹配global path/reason时，第一页没有synthetic行，第二页仍从offset-1开始，重复上一页最后条目。limit1/offset0和offset1返回同一真实row。不是目标清理风险，但覆盖问题列表应分页稳定，不能用重复行代替下一个缺口。

Fix: 先统一计算synthetic是否符合全部当前filter，只有实际进入结果集合时才占一个分页位置；补global存在但搜索仅命中两普通缺口的limit1逐页distinct expected。本审查已通知负责人，尚未独立跑新反例。

源码快照：Store `b4dc984f173e8b180b1bf1928ca1018712c828b32d83d4448307a216bd3b9e0d`；Scanner `1bde68ad48f67917e0aa9573f6b407009a6d1bb3b7e517ac88c5c749ba26e793`；App `97537855db2188e7fac54f064b55f529eb737f7229f276e6cc4999e522d0657f`；ExperienceV2Tests `88c349a622d7684221969721fd280287ffc0877561228bd096f41a6cf5f8db53`。源码可能由其他协作者继续修正。

## Review Summary（schema3 工作中）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 1 | info |
| LOW | 0 | note |

Verdict: APPROVE WITH NOTE — 当前维护源码无确认的CRITICAL/HIGH；覆盖列表筛选分页MEDIUM需修正。新schema3 host/制品接受不能继承旧版，原M2继续BLOCKED。

## schema4 增量统计与刷新性能再审（11:33 工作中）

本次新增schema4、scan_totals/category_totals、partial indexes和coalesced App刷新是另一源码范围，不沿用上节Approve。读取全部新增迁移/insert/counter/helper/retire/dashboard/display路径、App刷新状态机、counter负例与新benchmark实现。

独立 `swift test --scratch-path .local/independent-review-schema4-20261013 --filter v2`：2026-10-13 **11:32:51，exit0**。Swift Testing总报17项，其中50k回调基准明确skipped，**16项实际PASS**。新scratch完整编译12.76秒，没有使用共享旧build、没有清缓存、没有GUI同bundle测试/真实DB维护/Data扫描或系统Trash操作。原先catalog synthetic过滤分页MEDIUM已修：统一syntheticMatches再减offset，limit1逐页unfiltered/search/category expected独立通过，原问题结案。

### 增量统计与身份边界

- create在同事务建ScanRun、零总counter与7类counter；insert在单BEGIN事务中写entries、measured去重、祖先aggregate、scan/category累加及最终quota guard；重复ID/SQL_FULL/overflow触发ROLLBACK，不单独提交counter。
- nonnegativeSQLiteInteger严格INTEGER、非负；Boolean≤1；累计使用Int64 checkedAdd。旧schema3重建读取typed列，严格SQLITE_DONE；错误rollback保留version3，不把负typed坏值当0。Fixture验证跨batch hardlink只归因一次、分类fileCount独立对象、previewCount按候选路径、previewBytes仅去重计量、大文件数按路径语义，与原scan断言一致。
- dashboard从counter表读少量行，issues/topfolders bounded partial-index查询，避免原GROUP BY/CASE全树重算；同store actor synchronous查询期间不插入新batch。跨进程同库多个store/写者的快照一致性未证明，不宣称全部数据库并发已验。
- display用Entry身份本身可以无ancestor JSON，但生成计划仍通过 `store.entries`完整hydrated parentChain。独立Fixture断言selected缓存链count2通过。审查此时只有dashboard folders/issues hydrate=false，children/catalog仍默认hydrate；负责人若新增displayRows需再绑定其测试，不宣称未读到的优化已落地。
- retire保存Archive summary后，同事务删除scan_totals/category_totals/measured/entries；running/protected IDs保留，旧维护Fixture全部继续通过。

### App刷新状态机

receive只MainActor更新run并requestRefresh，不await SQLite；refreshRequested/urgent合并进single refreshTask，普通刷新至少间隔1秒，performRefresh捕获page/offset/parent/search/sort/category/issues，发布前核对上述context、scan generation和runID。scope/reset/newscan cancel旧refresh并清rows/weights；旧task结束才移交新请求，未见当前源码重复并行刷新入口。

terminal在扫描返回后 `refreshFinal(force=true)`，等待当前刷新task及续排任务完成，再解除scanning；settings/history不会吞掉final请求。任务取消、旧page变化、query错误以显式error/discard处理。此为源码评估，coalescing/迟到结果/final force仍须原生delay-fixture行为验证；未操作当前仍活的旧pid或同bundleGUI。

### [MEDIUM] 未知未来数据库版本会被静默降级为4

File: `SQLiteScanStore.swift:63`、`:110`、`:155`。

Issue: oldVersion读取后没有拒绝>4；version5或更高跳过counter重建，却继续创建当前结构并 `PRAGMA user_version=4; COMMIT`。这会把未知未来schema当作当前schema并改写版本，可能以新建空counter展示0，破坏升级/降级边界。

Fix: 在任何当前schema DDL前核验版本，未来版本应保守拒绝并保持数据/版本不变；增加version5加业务marker的Fixture负例。已发送负责人；本审查尚未独立运行该新反例。不是Gate执行问题，不据此声称发生真实用户文件清理。

### Runtime证据限制

旧`slow-dashboard-query-plans.json`确切记录类别GROUP BY与issues排序TEMP B-TREE，是旧查询根因证据之一；负责人提供683主线程mostly idle、619协作采样中583 dashboard重算的profile结论，本审查未自行采样旧pid，不当作自身采样。新benchmark实现确实每次progress查询dashboard+children、独立计数/字节验证、3次wall/query/max/RSS/DB记录和EXPLAIN无TEMP B-TREE断言。该测试本审查这次skipped，实际3次回调成绩尚未核对，不用无callback旧成绩充作UI整体通过。主线程100ms95%、host停止响应和真实Data状态仍须Runtime复验；不能由source optimization声称已解决所有性能问题。

## Review Summary（schema4 工作中）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 1 | info |
| LOW | 0 | note |

Verdict: APPROVE WITH NOTE — 增量counter关键fixture通过；未来schema拒绝需补齐，display/App真实刷新和新callback性能验收待证据。Gate仍false、M2 BLOCKED，不能沿旧版Approve或无callback成绩宣布本次完成。

## schema4 future-version 修后与性能证据复核（11:41）

读取冻结Store `d60346eb6670bf1960bfe7d854c93b2fbd444dc9eb70a00156bc0a9ac3e3fd08`、ExperienceV2Tests `4655bb79d8103c524aadbf4ada2195c77ddfd9f8bf1e0dad5353dd2ecf9de50a`，App当前源码 `37c6dcf924b12f1b2219518543c824db715ae99e5f7e1c3f357541f555c334cd`。

Store新增read-only connection先核验 `PRAGMA user_version`严格prepare/INTEGER/ROW/DONE、合法0–4；未来版拒绝发生在chmod、journal_mode、DDL之前，随后RW打开再次核验版本才进入当前迁移。独立 **`swift test --scratch-path .local/independent-review-future-schema4-20261013 --filter v2FutureIndexVersionIsRejectedWithoutAnyMutation`** 全新scratch构建12.32秒，**11:40:55 exit0、1 test PASS**。schema5/WAL、整个sqlite_master结构、业务sentinel、parent0755/index0644全保留。原未来版本MEDIUM结案；未操作真实schema3 index/旧进程。未声称同用户恶意竞态全部解决，当前生产执行仍关闭。

coalescing源码收口：旧scope reset取消refreshTask，旧performRefresh发布必须同时满足scan generation/runID/page/filter/offset/parent，drain单task结束再续排；terminal force+等待刷新再解除scanning。未发现>80%置信度的新源码错误。此轮仍未读到children/catalog displayRows不hydrate改版（dashboard已无hydrate）；计划 `entries` 完整链保持，不能将性能意向列成已实现代码。

`experience-v2-future-version-final.log`协作者全包总报47，其中2 opt-in benchmark skipped、Trash仅permissionDenied拒绝恢复fixture分支，不能称47项真实业务验收。

**新真实回调基准**（协作者运行，本审查核对原始日志`experience-v2-dashboard-progress-50k.log`）：固定50102条，actual allocated204804096B；三次wall13.458/13.220/13.392秒，progress callback62/61/62，每次真实dashboard+children；查询累计234.608/231.161/232.702ms、单次max6.331/6.507/6.583ms。RSS峰23,150,592/23,248,896/23,248,896B，DB68,440,064/68,489,216/68,468,736B。EXPLAIN issues/topfolders/counter均使用预期索引，无TEMP B-TREE；新增index/counter页占用日志保留。实际字节/计数、quota/RSS assertions通过。条件为uncontrolled-warm-contended，mainThreadBusy=UNVERIFIED；这些成绩证明此次Fixture callback读链改进，不替真实全盘、原生主线程95%100ms或cancel host证明。

**新原生刷新竞态仍FAIL**：`.local/experience-v2-ui-coalesced-10.log` 11:40:06 TEST FAILED，8 tests中1失败；`testCoalescedRefreshDropsStalePageAndScope` line177 `XCTAssertNotNil`失败（期待observer匹配“丢弃旧视图 [1-9]”）。其余7例通过不掩盖该FAIL；本审查未实际跑GUI或看observer截图，不能据源码推断此失效为何未观察到，也不能将断言降低为通过。需要有效制造迟到query并证明单task/context丢弃/terminal新值，或定位实际bug后修正和重验。所有旧FAIL/profile/query计划证据保留。

## Review Summary（schema4源码修后）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 已报告schema4源码问题修正并独立负例通过；当前无确认的新增源码问题。**刷新竞态原生验收FAIL、整体Runtime尚未完成**，不能把源码Approve作为UI/host通过；本轮只读改进继续推进，旧M2仍BLOCKED。

## 冻结coalescer源码与新race日志收口（11:44）

本审查实际`shasum -a 256`核对冻结Store `d60346eb6670bf1960bfe7d854c93b2fbd444dc9eb70a00156bc0a9ac3e3fd08`、App `2e7c42936bbb151b34c61738fbbd470ae5bc23724f1862a91863ceec1d7b4e2e`、UITests `8c067bddfe1689009806ce8443828c8e3d6ed0fff945a33d4088f11efbd4d3c3`，与performance-source-hashes.json一致。Store不变，future5独立拒绝证据仍适用。

源码变化为**仅同时有 `-lmcUITest` 与 `-lmcRefreshDelayFixture`的延迟从1.5秒到4秒**及失败断言信息打印observer；没有mock数据或放宽保护、没有删除max active1/旧视图丢弃≥1/旧scope结果清除/计划disabled/新scan终态存在断言。数据仍来自Fixture实际扫描→SQLite children/catalog/dashboard→真实View。普通生产路径没有4秒delay。coalescer单task、context发布guard、invalidate cancel与terminal强制刷新源码保持此前检查结果；测试scan.status只有scanning解除后才存在，源代码是在refreshFinal之后才解除，不能把此间接证明扩大为全部terminal dashboard像素/字节oracle。

本审查读取`.local/experience-v2-ui-coalesced-11.log`：2026-10-13 **11:42:21，1 test、0失败、TEST SUCCEEDED**，新`testCoalescedRefreshDropsStalePageAndScope`通过29.744秒。前轮coalesced10仍保留8例/1失败（其余7例通过）；不能删掉旧FAIL。4秒窗口让现有等待active→切页动作实际观察到丢弃旧结果，不是以删除断言做PASS。

这是**构建者运行日志的独立复核**，不是本审查亲自原生GUI操作或视觉验收；本审查未截图、扫描真实Data、读取真实index或改权限。新race定向Runtime证据由FAIL推进到PASS，但主线程95%100ms预算、真实新制品启动/hostData停止与coverage、其他交互状态/VoiceOver仍UNVERIFIED或待负责人实际运行。Final Release尚在构建，不从旧build复制PASS；原M2执行恢复阻塞继续保留。

## Review Summary（冻结源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 冻结源码无确认的残余finding，新race运行日志已验证定向PASS。整体Runtime与新Release/host接受仍按实际证据逐项判定，不能green all；Gate=false，旧M2 BLOCKED。

## schema5 compact metadata 初审（源码未冻结）

此次是schema5新源码范围：`CompactMetadataCodec.swift`、`CompactIndexAdapter.swift`及Store适配，首编译/Fixture仍在进行。旧schema4Approve不覆盖此次变化。本审查只读当前源码并发送风险，未改真实DB、GUI、权限或执行Trash；此节不作APPROVE。

### [HIGH] rollback后决策/卷字典缓存保留悬空ID

File: `CompactIndexAdapter.swift/decision()`、`volume()`；`SQLiteScanStore.swift/insert()` rollback路径。

Issue: 第一次insert transaction里decision/volume INSERT后，did/vid立即存入adapter内存cache；后续重复ID/quota/其他错误引发SQLite ROLLBACK，缓存不回滚。下一合法batch使用同decision/volume时直接取已不存在的did/vid。entry_nodes没有相应FK防线，可写入悬空关系；随后entry JOIN decisions或volumeName失败，或回滚ID被另一字典值复用导致错误decision/volume解释。事务统计rollback不等于adapter状态rollback。

Fix/负例: 任何ROLLBACK清除可能尚未commit的字典cache，或只commit后缓存；用首次batch新decision/newvolume加重复entry故意失败，随后第二合法batch同decision/volume完整Entry/FI/decision roundtrip必须通过，再验证不同值复用ID不会串改。已反馈scanner_store/root。本节为确定源码反例，尚未独立运行新Fixture。

### [MEDIUM] compact迁移弱化typed计数字段校验

File: `CompactIndexAdapter.swift/migrateLegacy()`。

Issue: 旧typed列2…9只要求SQLITE_INTEGER，未要求counted/aggregate非负、unique_leaf/preview_cache≤1；modified应允许负，但其他计数不能允许。合法原JSON配合counted_allocated=-1或unique_leaf=2会迁入entry_nodes，逐字段roundtrip只核JSON/FI/decision，不能发现typed计量坏值，仍可能提交version5。这比schema4已有严格typed迁移回滚准则宽松。

Fix/负例: 分列明确语义：mtime有符号，字节/计数非负，Boolean为0/1；负typed/Boolean2须ROLLBACK并保留version4和原表。已通知负责人，尚未独立跑该负例。

### 其余已读边界及待证据

- 公共Entry/FileIdentity/Plan对象未在本次编码中降精度；device/inode/size/linkCount/uid是UInt64 varint，time可Int64 zigzag或原UTF8 string，UUID按16字节存储，volumeID由独立字典还原。parentChain由父rid链重建，而非作为执行时可省略信息。读链CTE限制depth128，同scan关联，首根需parent=nil/name空；缺链/循环应返回错误。新测试仍须覆盖UInt64.max、Int64.min/max与未知长time、坏CRC/截断/未知tag/缺volume/缺decision/缺父/cycle/跨scan。
- SQL函数lmc_entry/lmc_path仅做数据库读取与DTO重建，错误由sqlite3_result_error传出，读查询最终非DONE会拒绝；函数生命周期由SQLite注册destructor释放。分页SELECT adapter可在每行发祖先查询，catalog搜索/排序中的lmc_path可能对大量匹配行执行，必须用真实callback+EXPLAIN/页查询成本验证，不能用compact字节收益推断无CPU回归。
- Codec原长≤64KiB且LZFSE解码目标固定长度；提醒负责人再核整体frame/blob长度上限、压缩零长度/零payload及Unsafe baseAddress。独立只读 `swift -e` Data0 pointer实验本机两个地址非nil，**未复现crash**，不将假设崩溃列为finding。
- v4→v5整表迁移在Store事务内，逐字段roundtrip与条数核对、旧table删除在提交前；这些源码保护仍需冻结Fixture实际验证。Schema5现在是支持版本，future负例须升到6而不是沿schema4的“5即future”；拒绝仍必须先于DDL/journal/chmod，旧未来5WAL守护PASS不能直接继承新版本。

## Review Summary（schema5未冻结初审）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 1 | warn |
| MEDIUM | 1 | info |
| LOW | 0 | note |

Verdict: WARNING — rollback缓存和typed迁移问题须修复并独立负例复验。未冻结/未运行schema5验收，当前不批准新版；旧FAIL与schema4证据保留，Gate不开放。

## schema5 中间修正源码复核（未冻结，12:20）

本次仅只读复核，按要求没有重复整套suite、没有侵入协作者Fixture。resetCaches()清decisions/volumes/scanKeys，Store insert/create/retire的ROLLBACK后均调用，源码上原悬空字典cacheHIGH的修正方向正确；仍需首次新字典batch失败→后续batch合法roundtrip实际负例才能最终结案。migration init失败store不会继续使用，未要求其throw后缓存能复用。

Codec已加frame≤65568/schema metadata CHECK、compressed length>0/payload非空及可选baseAddress安全解包；坏空payload不会进入force unwrap。这是防护加强，本审查先前没有复现该crash，不能回写成已修复实际崩溃。迁移已改hydrate=true并比对restoredLegacyIdentity，以完整链/FI逐字段对照，不用省略链掩盖差异。

### [HIGH] typed校验字段偏移错位，拒绝合法迁移并放过坏preview

File: CompactIndexAdapter.swift/migrateLegacy SELECT typed列循环。

实际SELECT索引：2 counted_logical、3 counted_allocated、4 unique_leaf、**5 modified**、**6 preview_cache**、**7 aggregate_logical**、8 aggregate_allocated、9 aggregate_unknown。当前代码却允许 i==6 为负，且对 i==4 或 i==7 限制≤1。这把preview当mtime、把aggregate_logical当Boolean；旧目录aggregate_logical>1的正常v4会被“旧Boolean损坏”拒绝，mtime<0也被错误拒绝，同时negative preview可能通过。

应允许负值只在i5，Boolean≤1只在i4/i6；最好用具名列/独立字段而非裸数字猜偏移。已立即反馈scanner_store与root。需合法aggregate>1、negative mtime、preview=-1/2、unique=-1/2的固定迁移expected，合法完整Entry/链不变，坏值事务version4/旧表不变；不能以新空库schema5基础测试通过替代迁移。

证据当前源hash：Adapter ac15d28e92872f2c80d9056c207e092b5b2bea0d8c837f622a563327f1987fb6、Codec cd679a63e27b6eeb004805efd4a214bcc36947d29fd2c56324b8ae90c896f2ef、Store 326d387b26024c5f463a6395307dbd5d8823a1ad0886a76533973b98d59d71a7（仍在变更，非冻结制品）。

compact-schema5-third.log只运行1项基础dashboard test并通过；compact-schema5-regression-initial.log47项总报、28issues FAIL原样保留。旧Fixture容量阈值、旧schema构造、未来5负例在schema5后可能需重新构造，但必须保留不变量：真实quota/SQL_FULL确切失败且未知不当空、合法旧版迁移完整不损失、future6无修改。当前源码初审发现的列错位也可能是合法迁移失败原因，不能将全部初始失败归咎旧Fixture。尚无freeze/新完整Fixture证据，不作APPROVE。

## Review Summary（schema5中间）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 1 | warn |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: WARNING — rollback缓存已做源码修正但负例待验；typed迁移列偏移HIGH仍需修正。源码未冻结，首回归FAIL保留，不能批准新版。

## schema4 合成容量参考脚本审查

本审查只读 .local/verification/compact-schema4-baseline.py/result.json，不重复执行或生成第二数据库。参考表/索引结构基本忠实v4（scans/entries/measured/counters及4个entries索引）；ID唯一、父目录UUID和完整相对路径映射一致。200000是索引条目，含根+34000目录，普通叶子165999，不是200000个真实文件。所有路径为合成basename，无用户数据输入，6个决策仅合成用途说明，未给真实清理能力。

结果现已存在：200000条、34001目录、integrity_check=ok，DB335470592B，每条1677.353B；mean path115.689字符、JSON777.601字符/825.601 UTF8字节。5.964秒只是原始SQL生成容量参考耗时，不是扫描/API/迁移/增量aggregate/dashboard性能。未把此时间与产品Runtime比较。

口径差异必须保留：目录JSON logicalBytes/allocatedBytes为字符串0，真实v4通常nil且编码省略；目录aggregate全0、scan/category_totals未填、scan.json为synthetic而非可解码ScanRun。因此容量随该synthetic payload变化，不能称真实v4 API等价索引，不能拿它做合法迁移expected或覆盖protect/identity/plan验收。同布局压缩对比亦须明确这些差异。

脚本一般化保护不足已告root：OUT mkdir(exist_ok)+chmod可能跟随既有链接；DB.exists忽略broken symlink，SQLite连接仍可能跟随。建议复用前lstat目录/文件拒链接、独占O_EXCL|O_NOFOLLOW创建DB并核身份。**本次当前输出**由本审查lstat核对：目录实际非链接/uid501/0700，DB普通非链接/uid501/0600，未见外部写证据，不推断当前发生违规或要求中止已完成运行。源路径风险不作为产品源码批准证据；schema5仍待冻结及Fixture复验。

容量脚本修后只读确认：OUT在chmod前lstat需实目录且当前uid；DB使用O_CREAT|O_EXCL|O_NOFOLLOW独占占位，已有文件/链接拒绝；SQLite连接后、DDL前对照创建时dev/inode，变化即close拒绝。此前可复用覆盖/链接风险已补防护。result limitations已明确directory显式0与native nil、空counters/零aggregate和非ScanRun差异；scriptAfterRun明确这些保护是在首次运行后补入，**没有第二次容量运行**。本审查不重跑脚本或读取真实DB，旧容量log/数字未以修后执行伪装。schema5平台未冻结，worker报告50项通过仍须区分opt-in skip和Trash拒绝分支，不能由此脚本审查批准产品。

## schema5 暂冻结平台定向独立验证（12:40）

本审查重新读取暂冻结Adapter/Codec/Store与完整测试、SyntheticStorageCorpus，未操作真实DB、GUI或Trash。独立命令 swift test --scratch-path .local/independent-review-compact5-final-20261013 --filter 'compact5MetadataVector|compact5Rollback|v2MigrationBackfills|v2CountersAppend|v2FutureIndexVersion'：全新scratch完整构建37.52秒，**2026-10-13 12:39:15 exit0，5 tests PASS**。

原rollback字典HIGH由新decision/newvolume首次batch失败→第二合法batch相同字典/FI完整roundtrip实际验证结案。typed允许负只modified索引5、Boolean仅4/6已读修正；合法aggregate>1的v4 SQL Fixture实迁移/counter对照通过，原列错位HIGH结案。future现在6，WAL/schema/business/permissions保留负例独立通过。Codec直接UInt64.max附近device/inode/size/link/uid、Int64.min mtime与超Int64的ctime字符串精确往返；坏CRC和零长compressed拒绝、nil FI不读取volume通过。

v4 fixture由writeLegacyV4在自建DB写完整旧表、parent/路径、JSON省略链、dedupe/aggregate/counters，再由本版真实init迁移；不是把现有schema5删字段后声称旧索引。migration逐字段hydrate对照与独立counter固定expected通过。Plan.entries完整链有assertion，公共Domain/Plan未改；**没有发现同一个固定id/Clock计划在v4→v5前后完整canonical JSON/hash等价的实测case**，该分项保持UNVERIFIED，不能拿原Domain静态向量替代存储迁移链验收。

### [HIGH] 搜索递归CTE遇到坏目录环不收敛

File: SQLiteScanStore.swift/catalog搜索matched CTE（本次源码普通与slash两分支均UNION ALL）。

Issue: 非slash搜索base仅instr(basename)，matched递归无visited/depth。坏compact DB有两个目录parent互指且basename命中search时，UNION ALL无限重复展开；IN(SELECT rid FROM matched)永不完成，尚未进入有128depth保护的lmc_entry/ancestor解码，store actor可能卡住。slash分支同样应有明确循环边界，不能依赖SQLite求值次序先触发lmc_path错误。

独立Python SQLite内存实验使用相同CTE结构、两个循环目录，并设progress handler上限50×100指令，实际打印 UNION_ALL_CYCLE interrupted progress_calls50；相同查询改UNION去重得到count2。这是受控内存查询证明，不是运行无限真实DB查询。已告worker/root；建议UNION去重或visited/depth，并补owned坏目录环catalog普通search会及时拒绝的Fixture。

### [MEDIUM] directoryPaths缓存在insert写入绕过8192上限

File: CompactIndexAdapter.swift/insert目录分支。

Issue: path/pathBounded写入有8192 cap，但insert直接 directoryPaths[rid]=full relativePath，不检查上限；典型corpus每6条1目录且parents4096 cache命中可跳过pathBounded，1M写入可累计约166k完整目录路径。parents限制不限制directoryPaths。不能只以声明8192或小Fixture RSS断言其实际有界。

Fix: 所有directoryPaths写入走统一bounded setter，补超过阈值目录写入后cache有界/完整Entry仍正确的观测。已通知负责人。1M未终态，不推断RSS一定违反500MiB预算。

## 证据与剩余边界

query-regression.log协作者总报50 PASS，3个opt-in基准skip、Trash只是permission拒绝分支；不称50项真实主机全验收。compact-schema5-million-typical.log本审查读取时仅构建完成，实际1M实验仍未终态，不写容量/RSS/查询PASS。该实验显式2GiB额度仅测量，不改变产品250MiB默认预算；1M是metadata，不是创建/扫描1M真实文件。SyntheticStorageCorpus约17%目录、有长共同前缀，另有random形状；容量参考不能泛化为任意个人机器能完整扫描。

UTF8路径搜索优化与排序已有普通Fixture/regr运行，但坏链/缺父/缺字典/未知payload枚举、长深度/cycle、同一固定plan hash迁移、schema5实际Data升级/VACUUM后再启动以及新分页大query成本仍待定向证据。旧first/regression FAIL、旧共享SIGSEGV、旧host索引满0误报证据全部保留。本次新hash读数为Adapter7d6ece497108f30b41ebe2c85d50a22dfc7701fd5bb464e3e7b5150b54873d31、Codeccd679a63e27b6eeb004805efd4a214bcc36947d29fd2c56324b8ae90c896f2ef、Storec2b568b8708bf668d35fce7157cfe414c62c1f24e677accfc5d00776224cafa2、Testsd74e9ed0a1f9ef4de4633f92ba329a7a601bb62b342182c35ee68e11eadea583，后续修正将改变快照。

## Review Summary（schema5暂冻结复核）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 1 | warn |
| MEDIUM | 1 | info |
| LOW | 0 | note |

Verdict: WARNING — 原两问题实际定向通过并结案；新搜索循环HIGH和缓存上限MEDIUM需修正复验。未终态1M不计PASS，仍不批准本次schema5平台；Gate不开放，旧M2 BLOCKED。

## schema5 安全修正冻结源码独立复验（12:50）

实际hash核对：Store661a1c41c64f4a71d47dc00d10812b8eec7b37d86cc2213850c8f8c762a8f8a1、Codeccd679a63e27b6eeb004805efd4a214bcc36947d29fd2c56324b8ae90c896f2ef、Adapter5e03f036cd1d822d183e7552e3991f990e8f23542e808c5a5184bd9ff501417a。

独立 swift test --scratch-path .local/independent-review-schema5-safety-20261013 --filter 'compact5MigrationPreserves|compact5CorruptParent|compact5Rollback|compact5MetadataVector|v2FutureIndexVersion'：全新scratch构建31.19秒，**2026-10-13 12:49:31，exit0，5 tests PASS**。固定planID/Clock的v4 Fixture原Entry→v5 decoded完整FI/链、canonical bytes/hash完全相同；Fixture原叶移动到held并用新文件替换后，真实MacPreflight准确identityChanged且replacement内容未改。此前该Plan hash缺口现由独立实际证据补齐，不扩大为所有执行/恢复PASS。

matched两搜索分支已UNION去重，坏parent循环普通search≤2秒抛错负例独立通过，原搜索HIGH结案。所有directoryPaths写入点（insert/path/pathBounded）均执行8192 cap；parents4096/decisions128/volumes64与rollback reset维持，原insert cache上限MEDIUM源码结案（未独立观察cache内部count，1M RSS不能冒充尚未完成的实测）。旧rollback/typed/UInt64/CRC/future6独立负例继续通过。

迁移源临时空间先核 sourceSize×3+64MiB，完整链逐字段对照、迁移count statement最终DONE/finalize后才DROP，扫描sid为显式稳定整数，避免VACUUM后用rowid身份变化。所有这些只针对owned索引；本审查没有启动真实v4迁移或GUI。

### [HIGH] 写入祖先聚合仍存在无界递归环路径

File: 当前Store insert() ancestor aggregate UPDATE，约line295。

Issue: 该CTE仍UNION ALL、无visited/depth。当前Adapter已缓存合法父目录路径后，自建DB故障注入把父目录改成环，再insert该父下合法名可以走cached parent校验而跳过pathBounded，随后ancestor UPDATE重复循环，尚未提交/rollback。读catalog环已修不等于写入环已拒绝。正常scanner不产生目录环，此为坏索引/缺链failclosed边界，不声称用户文件已有误删。

Fix: 祖先写CTE也去重/有界，并要求可到合法root，否则throw rollback；只改成UNION后继续更新坏环也不构成拒绝。已同时反馈worker/root，可在同CTE要求root存在并核受影响行数，避免每leaf完整hydrate导致新性能退化。补owned故障parentcycle→insert及时拒绝、统计不变和cache清理负例，不运行无限真实DB查询。此前Python bounded内存实验已经证明UNION ALL环重复，不新增无限实验。

## 新容量/Runtime证据边界

compact-schema5-safety-final.log协作者总报52通过，其中3个opt-in基准skip、Trash仅权限拒绝分支；不能说52个完整功能验收。新ASCmodified100k metadata实验协作者log完成，通过容量约263B/项与queries；该规模不替1M。旧modifiedDESC/cachesource的1M278MB超250MiB预算FAIL保留，不将旧数字当当前冻结源码性能。当前compact-schema5-million-longrandom.log本审查读取时只有build完成，实验未终态，容量预算/RSS/查询仍UNVERIFIED。Final Release/App8cases/rootData真实接受正在独立推进，本审查没有操作GUI，不能预先记录通过。

## Review Summary（schema5安全冻结再审）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 1 | warn |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: WARNING — 已报告搜索/缓存问题与固定计划等价已实际补齐；写入坏parent环仍需拒绝边界和定向复验。1M/新Runtime未终态不计PASS；原M2 BLOCKED。

## schema5 最终写链环修正独立复验（12:56）

本审查实际SHA核对冻结Store **5100bd7a77b3ced2913a77945e034f55505981ab060d97a67c687eea4c3429ac**、Adapter **756a364bfb392a8df18ffe038ce574da769c23d612cee59db3ed4038fb450124**、Codec **cd679a63e27b6eeb004805efd4a214bcc36947d29fd2c56324b8ae90c896f2ef**、Tests **7349a25e73ea9743828c9e27c74393913b5093d2a4864373609eebc861314dad**。

insert每batch先检查PRAGMA data_version，外部连接commit改变代次则清所有相关cache；aggregate祖先CTE改UNION去重、同scan递归，并要求该集合有parentNULL根才UPDATE。sqlite_changes==0准确拒绝缺根/坏环并触发整batch ROLLBACK及cache reset，不继续更新未知结构。原write环HIGH结案。

独立 **swift test --scratch-path .local/independent-review-compact5-cycle-final-20261013 --filter compact5WarmCacheExternalParentCycleRejectsWholeInsertBatch**，全新scratch构建48.25秒，**2026-10-13 12:55:37 exit0、1 test PASS**：实际先扫描暖父cache、外部owned Fixture连接改parent为环、再insert及时throw≤2秒，counter不变且new行0。未操作真实index/用户Data/GUI/Trash，未清build缓存；当前所有已报告源码finding有修正与必要定向复核，无确认残余CRITICAL/HIGH/MEDIUM。

compact-schema5-cache-cycle-final.log协作者全包总报53通过，3个opt-in基准skip、Trash仍为permission拒绝分支，分项口径继续保留。此前固定Plan canonical/hash真实迁移等价、实际MacPreflight replacement identityChanged、future6/64位codec/rollback字典测试已由本审查独立5项补验；本次最后改动只影响cache外部代次和ancestor写环，不将上述证据泛化成执行恢复M2通过。

## 容量与Runtime不能随安全批准变绿

compact-schema5-million-longrandom.log旧ASC源码的metadata1M实验已终态：**413855744B，413.856B/项，超过产品默认262144000B → 容量预算FAIL**；写入276.443秒，RSS26427392B，dashboard1.017ms、children2.886ms，排序31–55ms，basename搜索2.538秒/fullpath3.233秒。实验测试exit0只证明其显式2GiB测量环境成功，不是产品250MiB额度通过，也不是扫描真实1M文件。代码最后cycle/cache改动后没有重跑性能，不能把旧成绩标为当前最终源码Performance PASS。

旧1M typical/DESC超预算、全部初始失败/共享SIGSEGV/真实host旧index满0误报，以及baseline差异全部留存。容量需求/资源预算需负责人基于真实Data终态作明确决定，不能本审查擅改预算。新Release/App UI/真实迁移与完整hostcoverage尚须各自新版本证据；主线程95%100ms/VoiceOver/执行恢复仍按未验或旧BLOCKED保留。

## Review Summary（schema5最终安全源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: **APPROVE** — 仅批准上述最终hash源码的安全与正确性复核，已报告问题结案。**1M长路径容量预算FAIL，整体Runtime/新制品host接受尚未完成，Gate=false、旧M2 BLOCKED**；源码批准不等于全部目标完成。

## App后台索引初始化源码审查（新增范围）

本审查只读新App完整初始化/状态/按钮/测试Fixture与UtilityApplication storage持有关系，未编辑源码、运行GUI/新真实index迁移。实际hash：App151ee08d587c272d2224e39ad6a83796a1722c4429c67241fee7fefd7831bdc7、UITestsa9f010208521f76815574426eb51beab44f12b9a5ba6cf154f9d3e99b99662fd。

SQLiteScanStore整个同步init（含真实迁移/VACUUM）移入Task.detached(priority:.utility)，其actor结果作为Sendable返回；外层Task继承MainActor，仅发布store/准备状态/中文error，没有在MainActor重复init。UtilityApplication.shared持有单个storage，与窗口生命周期分开；后台任务有self持有直到完成，源码未见窗口切换生成多个并行准备任务。未设计取消初始化或重试，失败保持indexPreparationError且scan/quick守门，未自动扫描/提权；大真实准备中关闭应用/中断后的SQLite恢复仍须host验证，不以线程移出主线程证明所有资源/重启行为。

preparingIndex默认true，准备中文状态显式；scan.start/三个快捷扫描/自选目录按钮在准备期禁用，startScan另需store非nil/非preparing/error=nil，quickScan有同守门。导航仍可用，但只有run非nil才查询，准备期间不会隐式启动Data扫描。失败中文且不自动重试；自选只解析范围，失败后不能开始扫描。原Gate=false不变。

新LegacyIndexFixture仅在同时 -lmcUITest 与 -lmcMigrationFixture 且有本App新建private temp fixture时调用，数据库URL固定该新目录index.sqlite，不接受用户路径。旧v4三行root→Downloads→实际2MiB安装包，FI来自真实元数据，JSON省略链、measured/typed/祖先aggregate/旧counters+索引实际写入，再由真实Store init迁移并summary读出。没有mock summary、用户旧库或fixture外删除。准备期8秒延迟也只双flag；**延迟在SQLiteScanStore.init之前**，UI测试文案明确为迁移前等待窗口，不能用它证明大型实际迁移CPU/I/O期间的UI响应预算。

新增testBackgroundLegacyV4MigrationKeepsPreparationResponsive保留准备状态/scan禁用/导航、ready后启用、旧三项2097152B和随后真实扫描断言。源码.Release日志experience-v2-async-index-build.log BUILD SUCCEEDED（协作者运行），只证明构建/Swift并发类型检查，非本审查独立GUI。

本审查读取experience-v2-ui-async-index-final.log时suite仍未終态，已有scope.internalDisk等待失败、scope.downloads不存在等FAIL。原9项尚不能称通过，不能将早期sourceBuild PASS或旧8case PASS继承；失败根因本审查没有足够证据诊断。root新版hash还需重新构建与host接受，本审查未接触真实Data/DB。

## Review Summary（后台初始化源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 当前App后台初始化源码未发现确认问题。**新UI测试已有失败/未终态，大真实索引迁移与最终制品未接受**；此源码批准不代表9UI或actualHost通过，容量FAIL/旧M2 BLOCKED继续保留。

## App幂等准备入口增量复核（13:28）

仅审本次App/UITest差异，未改源、操作GUI、读取真实DB或碰并行PerformanceIntegration/Performance任务。实际hash App **71eff525fc06b95230d1d4619d32fa026660c0fb152e6ec9a8018ecc96be4e85**、UITests **662a2afad8d54fe06a4781063530cfd105dafb79503d800b0476abe0564a05f5**。

constructor现在只准备路径/忽略/显式预选scope metadata，把indexURL/quota保存；CleanerView.task调用MainActor prepareIndex，indexInitializationStarted先置true，再启动Task等待detached.utility的真实Store init/迁移。窗口/route出现多次不会重复准备同一个model，prepare失败不自动重试；UtilityApplication.shared storage持有关系沿已审证据，未扩大读取selectedScope。没有新增auto scan、prefs/network、提权或Gate能力。

旧8case launch helper默认明确等待scan.start enabled并assert没有index.failed，解决准备尚未完成即点击的测试竞态；新增migration case选择waitForReady:false，仍保留准备中文/scan quick禁用/等待阶段可导航/真实v4三项2097152B/随后点击才实际scan断言，没有删除失败条件。8秒仍位于实际Store init之前，不能把它当大索引迁移CPU/I/O主线程实测。

**日志已终态核对（运行者为负责人，本审查只读日志）**：隔离com.localmaccleaner.schema5uitest migration单例13:20:56 TEST SUCCEEDED，1case0fail；isolated-final13:27:53 TEST SUCCEEDED，**9 tests0fail**。全套285.926秒，small dark143.811秒存在已报告SystemSettings中断，不作为快速交互/主线程预算证明。本审查没有亲自GUI或截图像素验收。原bundle async-index-final13:12:46 **9tests19fail/TEST FAILED**保留，另一原bundle只menu/noWindow失败亦不得被隔离成功覆盖。

父任务提供SDK已确认macOS15+ Scene.defaultLaunchBehavior(.presented)的计划，但本审查对上述71eff525全文rg没有defaultLaunchBehavior/presented/#available，实际Scene仍只有Window.defaultSize。**该presented分支不能记作此hash已实现/已审**；后续Scene改动需新hash增量审查、原bundle定向窗口启动/恢复及14 fallback证据，不能用隔离bundle结果批准尚未存在的修正。

## Review Summary（71eff525增量）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 当前幂等prepare/ready等待源码无确认问题，隔离9UI新证据已通过；**原bundle窗口/hostData、尚未读到的presented分支及整体资源预算仍未接受**。容量FAIL与旧M2 BLOCKED保留，不green all。

## Scene启动可用性包装增量审查（52e1a54）

实际SHA App **52e1a54f9785b98d6ff1fe71da04311dcc8646268c4f504d457b8df3cf8ddb64**，UITests仍 **662a2afad8d54fe06a4781063530cfd105dafb79503d800b0476abe0564a05f5**。仅只读本次Scene helper，没有操作任何App/真实DB/权限，没有修改PerformanceIntegration或并行功能。

body调用普通launchScene函数：macOS15+构造mainWindow.defaultLaunchBehavior(.presented)，14回退同一个mainWindow；两分支都经SceneBuilder.buildLimitedAvailability得到同一受限Scene existential，再由buildOptional返回。该包装只决定窗口呈现，不启动scan；现有prepareIndex幂等入口/Gate/隔离Fixture逻辑未改。

本审查实际用xcrun定位当前MacOSX26.1 SDK，读取SwiftUI arm64e-apple-macos.swiftinterface：SceneBuilder.buildLimitedAvailability为public/macOS13+，实现返回LimitedAvailabilityScene；buildOptional在macOS13+将该marker包装cast为LimitedAvailabilityScene。两个分支只使用前者的返回值，因此在产品最低14上这一路类型擦除与cast有确定来源；没有强转任意不相关Scene或使用private runtime selector。_LimitedAvailabilitySceneMarker虽有下划线，在SDK中确为public marker，使用范围局限helper。SDK接口检查不证明14实机/窗口恢复已成功。

前两次buildEither/availability写法编译FAIL仍保留；single-scene-presented-retry.log记录旧尝试Failed to produce diagnostic/build failed，不能删掉或当当前版本Runtime。负责人报告本52e1a54编译成功，本审查没有另跑构建/GUI。隔离71eff525的9case成功属于前版，**不继承为52e1a54原bundle新窗口策略验收**；原bundlemenu-only/noWindow失败仍需要新版exact Release定向启动与恢复、mac14 fallback（尚无实机证据）。

已报告的共享UtilityRootView顶栏新增后存储header截图裁切属于Runtime布局待验；本审查没有亲自看新像素，不能凭Scene helper sourceApprove关闭该缺口。root后续需要在不改变并行feature功能的前提实际验证最小窗口/入口可点击/真实Data准备与scan终态；不能把窗口presented等同已无裁切。容量预算FAIL和MainThread/旧M2限制继续适用。

## Review Summary（Scene helper源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 52e1a54启动包装源码及本地SDK声明未发现确认问题。**批准仅源码，原bundle启动/恢复与布局/host接受仍未验证**，旧编译/Runtime失败保留。

## HSplitView存储布局增量复核（13:58）

实际SHA App **a9b87b26b63d5e49d92284bfafd6cf32048c5c74e018e980869b96fdf118ee67**、UITests **d1ca3b30cc6b95c87821b7ea8192e4842a5b95a72a144527673bfad9a5370bd2**。只读本次布局/测试差异，不编辑源、不驱动App、不触碰PerformanceIntegration。

CleanerView将嵌套NavigationSplitView换成HSplitView：左侧List保留CleanerPage tags、selection Binding/changePage并显式sidebar style，宽度180–220；右侧仍同header→真实page内容→footer，无新增scan/执行路径。prepareIndex幂等task、搜索/排序/分类refresh、cmd-F FocusState、sheet/错误提示、选择eligible守门、准备期start/quick禁用、扫描时选择禁用、cancel一次停止、plan confirm硬disabled均保留。没有因布局修正绕过保护或暗选文件。

新testStorageHeaderVisibleAtBothSizesAndThemes循环1180浅/深及1000浅/深四组合，等待index ready，检查标题与自选/start/三preset动作hittable并frame完全包含window，保存独立截图。日志experience-v2-header-isolated-final.log **13:57:31 TEST SUCCEEDED，1 testcase0fail**；该单case确实执行四组合。本审查仅独立读取源码/log，没有亲自看这组像素或做原生GUI，不能冒充完整视觉接受。旧sidebar/map/plan业务测试未因新单case成功自动继承本hash完整PASS。

负责人已报告旧52e1a54 exact native Release（exe603256…）真实原bundle出现lmc-main Window、后台旧index升级后Settings可导航、经scope.internalDisk启动真实Data扫描；这明确是**旧immutable binary**的host证据，不能用本a9b87b布局test替旧binary裁切状态，也不能从负责人提供“进行中”推断Data已完整终态。此前原XCTest menu/noWindow失败记录保留；它不等于生产native启动必然失败。root后续新制品原bundle布局/扫描/停止/coverage接受需按其实际hash记录。

## Review Summary（HSplitView源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — a9b87b布局源码无确认问题，四组合frame/hittable日志验证通过；批准不涵盖亲自像素或新hash全链host接受。容量FAIL/MainThread未知与旧M2 BLOCKED继续保留。

## 上次终态结果只读恢复独立审查（14:35）

本次确实执行独立源码/日志/自建Fixture审查，不将此前modelcapacity未开始的尝试计作review。未启动原bundle、读取/写入真实DB、干预旧原Drive53CDA106/PID62689或改任何产品源。实际当前SHA Store **1c4cee92e0e2bdcf69b108ef58be673fd25bca9dad17361757bbbaa75267d2bf**、App **8522472ad5a08d652df55911cd92716b3707b776ce7b39457f17a0bb818c8903**、UITests **2dd312756cdee03335d640ec4415f79fc45e40620d4b1915473b940cec5b1d08**。

Store latestRetainedTerminalRun仅SELECT仍有entry_nodes的scans，不自动恢复running/preparing、已清退仅archive summary的记录。逐行strict decode、runID==SQL id核验，整体SQLITE_DONE；坏JSON/身份不符抛错不挑较旧合法记录掩盖故障。按finishedAt或startedAt取最新，tie用UUID固定顺序。独立 **swift test --scratch-path .local/independent-review-retained-snapshot-20261013 --filter latestRetainedTerminalSnapshot**，全新scratch56.97秒构建，**14:28:29 exit0、2 tests PASS**，覆盖terminal四状态/active/preparing/archive、tie、坏候选不fallback。协作者55总报通过仍需区分opt-in skip和Trash权限拒绝分支。

App在prepare ready前读终态，在detached.utility只stat saved root，经MacFileReader.scope拒symlink/不可读范围，比device/inode/kind、volumeID与owner；不要求mtime一致是浏览历史的明确设计，不能声称当前文件未变。身份变更/读取失败只notice、不载结果；符合时还原旧scope/run/date/partial/stopReason，selection从空新建、旧plan无授权；restoredSnapshot在controller select/preview和checkbox/pageSelect/plan入口双层锁定。导航、地图、排序、旧known/unknown允许浏览，但数据日期与“文件可能已变化、重新扫描才能选择”明确，未autoScan/恢复active/execute/prefs/network。

初审发现并实际反馈HIGH：header直接startScan未清restoredSnapshot，fresh完成仍不可选择；Root已在ready guard后立即清锁，后续原run/rows/selection/plan清空完整保留。新UI定向证据补齐后结案。准备中不能新scan，恢复refresh与freshscan代次/cancel guard沿已审coalescer，不让旧rows发布覆盖新run。

测试证据按版本保留：

- 初restore-snapshot-ui.log **14:23:36 1case0fail TEST SUCCEEDED**（test63.006秒、工具67.474秒）只充分证明日期/noAuto/partial/active/replacedRoot与旧结果可浏览。其单击Downloads后只focus，早先disabled检查可能只命中目录；即使旧2MiB叶子也原本previewOnly，不能用该弱断言证明eligible恢复锁。初PASS仍保留，不升级成完整leaf安全验收。
- restore-snapshot-ui-rescan.log **1case2fail/TEST FAILED**保留，错误定位为测试找了不存在的plan.confirm ID；产品实际ID为plan.confirmTrash，修测试后仍保留原disabled断言，没有隐藏失败。
- restore-snapshot-ui-eligible.log **14:34:21 1case0fail TEST SUCCEEDED**（test99.978秒、工具106.785秒），case循环completed/partial/active/root替换四情况。双flag private旧v4加原本trashEligible的600MiB真实sparse叶子，parent正确指向Downloads目录、run4，先detail.enter+breadCrumb到真正leaf再断言disabled。完整场景进一步header直接freshscan32→旧notice消失→freshlarge leaf enabled→选中→preview enabled→confirmTrash disabled，真正区分旧浏览锁与fresh解锁。部分状态保留stopReason；active/root替换无restore/no自动扫描。本审查仅独立核对运行日志/测试源码，未亲自GUI或像素验收。

最新App8522472比上述运行binary另加**仅LegacyIndexFixture的large_count按普通logical≥512MiB从真实entries派生**（原fixture原样写0不忠实旧counter）。源SQL字段顺序/父ID/同层rawIdentity/四与原三情况已核合理；该compile后改动下次build/re-run仍UNVERIFIED，不能把此前eligible日志视为此最新fixture counter改动已经运行。它不改变产品恢复controller/Store逻辑；背景迁移原3项case仍不加EligibleRestoreFixture，原expected3项2097152B保持。

## Review Summary（只读恢复源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 新Store只读终态选择已独立Fixture通过，恢复浏览锁与header重扫解锁修正已有效UI负例补齐；当前源码无确认残余问题。**最新fixture统计小改待重跑，新binary host恢复/真实Data仍不得继承旧binary结果**；所有旧FAIL、容量FAIL与旧M2 BLOCKED继续保留。

## ADR-10-R1资源预算增量独立审查（16:37）

实际当前hash：Domain IndexResourcePolicy **5bba3ef1645b9e29d4f0282f9a1bda668e8ec15ba20ae55bcf8e55d4bc7d08ca**、Store **1d5776d3b199969d3b8f94395490cc0724a5e2e1424569d8a3203ca9291a0478**、App **bcf7092f7b6e0cafad562bc0f839a3487df4d5c73d9f0f5b32637ab9eefd8277**。本审查不launch原bundle、不写hostDB或执行真实Data扫描，只新建自己的scratch与Fixture。

读取DECISIONS ADR-10-R1：原250MiB是可重开的工程资源设计预算，现基于真实旧Data981096 processed/980896 committed、59分17秒quota停止和每条约267B数据，显式统一提高默认max到1GiB，并新增索引所在FS至少1GiB可用余量。原250MiB主盘/1M实验FAIL原样保留，不把预算修改重写为旧结果通过。约4M容量只是线性估计，真实全盘仍须新binary終态，不以删明细或选小目录替代原scope。记录当前成本/替代方案/1GiB仍不够时下一步，未降低执行、身份、protect、unknown、pending或Gate条件。

源代码共享Domain常数1_073_741_824，Store默认、App pending/default与Settings文案一致，CLI使用Store默认没有静默独立250MiB覆盖。每batch插入前与COMMIT前requireAvailableReserve先assert本应用index/parent身份，再statfs其父目录，checked UInt64 f_bavail×f_bsize；未知statfs、blockSize0、overflow或不足抛quotaExceeded。当前SDK mount.h核对f_bavail uint64_t、f_bsize uint32_t，转换无signed负值trap。COMMIT前检查位于transaction do内，throw路径ROLLBACK+compact.resetCaches，保留counter/rows原状态；没有读取selectedScope来决定磁盘预算、没有提权/清缓存/清用户文件。

独立 **swift test --scratch-path .local/independent-review-resource-policy-20261013 --filter 'sharedIndexResourceBudget|unavailableIndexReserve'**，全新scratch15.41秒构建，**2026-10-13 16:36:08 exit0、2 tests PASS**。检查精确常数/1GiB算术、UInt64 overflow/block0拒绝、minimumAvailable=max强制不足→无new rows/counter改变、sentinel内容不变、Scanner partial/stopReason/global unknown，以及仅Fixture explicit min0 override。未实际消耗主机空间来逼低余量。

**证据缺口不省略**：minimumAvailable=max用例在第一次batch前检查即拒绝，不曾实际走“第一次通过、事务中写完后COMMIT前余量不足”的故障注入；该第二检查rollback只有源码位置及已有一般rollback断言支持，分项仍UNVERIFIED。同样没有本次Store statfs syscall失败/真实可用空间跨阈值实机证明。并发其他程序可能改变空间样本，检查不是OS磁盘独占预留；不声称所有写入/迁移/创建元数据都受该batch guard替代，既有迁移/VACUUM空间检查仍单独适用。这些是验证边界，不制造当前确认源码bug。

index-resource-policy-regression.log协作者全包57总报PASS，3opt-in skip/Trash仅拒绝分支，不能称全部Runtime通过。restore-snapshot-ui-final.log **14:38:03 TEST SUCCEEDED**，1case0fail/test76.249秒、工具77.653秒，补齐前次仅Fixture large_count派生改动后的实际UI运行；本审查读取日志，非亲自GUI或hostRestore接受。最新App除共享预算/Settings文案变化外，已审restore锁/直接重扫清锁与执行禁用保持。

## Review Summary（资源预算源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — ADR-10-R1明示的有限资源预算及共享/保留空间守门源码未发现确认问题，必要独立边界Fixture通过。**COMMIT前余量故障注入/新binary真实Data完整终态仍未验；旧250MiB FAIL不改绿，Gate=false、旧M2 BLOCKED**。

## COMMIT前余量故障注入增量独立审查（16:44）

实际hash Store **eab2ff5d25b79bad2c6fff89147de84ae8cc8f1c5f6d6399606522cb5d797a82**、Tests **9e9f947f7cfda2b3693922be1f20d0e5e193fa2ae086e5b0fe1ececb6e898f54**。只读源码及自建Fixture运行，不修改真实DB或产品源。

DEBUG seam由三处完整 #if DEBUG包围：私有ceiling队列、internal actor setter、requireAvailableReserve中min(native,ceiling)。必须先通过assertIndexIdentity、真实statfs和checked乘法才能应用ceiling；unknown/native失败不会由注入补成成功。ceiling只能降低样本，UInt64.max等于不降低，不能增加可用空间或扩大maxBytes/权限/规则。无App/CLI/launch参数/prefs调用该internal方法。Package.swift与Xcode工程未额外把DEBUG定义到Release；标准Release源码条件编译排除队列、setter和注入分支。本审查未另跑新Release二进制符号检查，不冒充已对新制品做nm证明。

独立 **swift test --scratch-path .local/independent-review-commit-reserve-20261013 --filter commitReserveFailureRollsBackEveryIndexEffectAndAllowsExactRetry**，全新scratch构建15.64秒，**2026-10-13 16:43:41 exit0、1 test PASS**。真实private index先有root，新batch引入新volume/decision/普通file；注入[UInt64.max,0]使第一次真实可用不变，第二次在entries/counter/aggregate写完后拒绝COMMIT，catch实际ROLLBACK+cache reset。summary/preview/category计数、rootaggregate、entry_nodes只留root、inode_seen0、decision/volume各只原1条和目标sentinel内容均保持；清注入后相同Entry精确retry，完整FI/decision和字节/preview/inode计数正确。这补齐上节明确的COMMIT前故障注入缺口，**不是实际把主机磁盘填到不足**。

协作者index-resource-policy-commit-regression.log全包58总报通过仍需区分3opt-in skip/Trash拒绝分支。纯算术overflow/block0、首次reserve不足分项沿之前独立2test证据；本次不改变原250MiB FAIL、真实Data终态或主线程未知、旧M2阻塞，不因为新增unit绿灯宣布全部目标完成。

## Review Summary（DEBUG reserve seam源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — DEBUG only-lower/native-first测试接缝无确认问题，COMMIT前整批回滚及精确重试已独立实际通过。新Release/真实Data完整范围仍需相应制品证据；Gate不开放。

## 长时间无进度提示与取消文案源码增量审查（17:10）

实际hash App **2d509c13b3284ee672a8fe69d5c3e3788a939d84a1152980691618a72fd7f83c**、UITests **158808e6a5d7d39b835710fd1de418831f14db4a51b7d848271b50c15eb32737**。本审查仅只读本次源码与运行日志，没有启动/取消真实PID62394、处理其TCC窗口、修改hostDB或产品源。

新增lastScanProgressAt为ContinuousClock.Instant，startScan显式初始化、同generation receive刷新；TimelineView每1秒重新检查单调elapsed，正常阈值30秒。提示只说较长时间未收到进度，可能在等待文件系统/系统权限，并提醒自行处理提示且不会自动授权，不把TCC当已确认原因。它不改ScanRun/统计、不强制结束、伪造取消终态或打开清理Gate。取消状态文案改为“已请求停止”，而非已经停止读取；真实阻塞调用返回/调度后的行为仍沿既有cooperative cancel，不宣称系统调用可强制中断。

测试专属阈值1秒与准备期30秒sleep均需testRoot存在且 -lmcStalledScanFixture，testRoot只在 -lmcUITest私有新tmp目录建立。单独flag在普通用户scope不起效；延迟不用于真实scan。准备cancel仅置请求，sleep返回后generation/cancelling guard退出，run仍nil，没有假造completed/cancelled扫描记录，扫描/选择/权限保护未削弱。

新testScanWaitNoticeAndStopDuringPreparation保留notice/非自动授权文字、plan disabled、cancel请求后等待文案与cancel按钮disabled、最终start再次可用/run status仍不存在，以及重开正常真实Fixture32项且无等待提示。**其边界仅测试准备等待与cooperative cancel前置guard**，不是实际openat/TCC卡住时取消请求能否及时中断、也不是原2秒normal-fixture预算的替代。

实际只读scan-wait-ui01.log：**17:08:59 TEST FAILED**，Runner failed to initialize for UI testing / Timed out while enabling automation mode。尚未进入该testcase，不记录行为PASS，也不将环境初始化失败诊断为此源码逻辑故障。新隔离bundle为com.localmaccleaner.scanwaituitest，重跑行为仍UNVERIFIED；本审查未授权/驱动其他App来解决环境。

## Review Summary（扫描等待提示源码）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 提示/单调时间与仅测试准备延迟源码无确认问题。**新UI行为尚未执行，真实阻塞syscall取消不宣称已验**；环境失败保留，执行Gate不开放。
