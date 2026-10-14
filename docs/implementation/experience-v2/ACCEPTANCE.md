# 体验 v2 当前验收：外部TCC等待；新等待提示仅fixture分项PASS

2026-10-13；goal active。真实Data run48FA94B9-4983-445B-A92D-150EC5544434/PID62394/旧resource exe3a30c314f7d29b08ccc53c88bf9f590e6211857ffab1ecb0a987106096e915f5，09:14:46Z仍running357612项/16777缺口/98390016B。完整主盘终态/覆盖UNVERIFIED，当前外部TCC等待，不因采样超时restart。

实际诊断：ownPID sample03全部2547producer样本在`FileReader.directory→openat`等待；过滤本bundle的resource-native-tcc-wait.log记录16:57:18 kTCCServiceMediaLibrary AUTHREQ_PROMPTING/签名不匹配旧grant。CUA安全拒绝UserNotificationCenter操作；未代答或更改权限。已提出用户async状态问题但未答，不能当许可或完成验收。

新等待banner App2d509c/UITest158808e源码APPROVE，ui01 exit65初始化timeout无case不计测试PASS。Releasewait exeSHA4e0ad61f154f060bfc4b1f133b82fff9aa1a2a7988cee286bdc4708514a6780b build/sign0；原bundle仅 `-lmcUITest -lmcStalledScanFixture`自建目录native验证warn/请求停止/30秒准备返回start可用/无fakeRun/notice消失，另真实32项fixture partial完成warn消失；零选择、preview禁用。scan-wait-native-fixture.json是该测试版本分项证据。

V2-08/11等待文案与fixture状态分项PASS；不能推出真实TCC阻塞syscall可取消、不能推出新wait制品默认ownindex/Data成功。live run未换binary；最新源的默认实机链与完整覆盖仍UNVERIFIED。旧250MiB quotaFAIL、UI初始化失败及M2Gatefalse/Trash/恢复阻塞原样保留。

## 既往证据与失败（历史）

# 体验 v2 当前验收：schema5源通过，产品全链待验证

2026-10-13。**goal active；schema4真实Data quota FAIL未被schema5实机证据替代**。紧凑源码关键安全APPROVE不等完整存储分析体验完成，1M容量实验test PASS但default预算FAIL。App异步初始化新改动后，V2-01–12所有需最新App/制品/realData断言仍UNVERIFIED。

## schema5已实际验证（平台冻结版）

`xcrun swift test --scratch-path .local/compact-build-v5`，compact-schema5-cache-cycle-final.log exit0（session91720），53reported，3opt-in规模基准skipped；50项实际tests包含系统Trash权限拒绝分支（真实Trash仍BLOCKED）。绑定Store5100bd/Adapter756a/Codec cd679a/Tests7349a25，关键安全源review APPROVE。

实际fixture与独立oracle：integer内部ID/UUID16B而public UUID保留，basename+parent完整路径与FI恢复，UInt64 varint/ns fallback/CRC/有界LZFSE，v4→5祖先身份/typed oracle、固定PlanUUID/date canonical payload与hash保持；真实fixtureMacPreflight替换叶子返回identityChanged。迁移freeSpace3×source+64MiB预检、strictDONE/事务rollback，VACUUM inode；future6只读拒绝不改schema/WAL/权限。缓存4096parents/8192paths、data_version外改失效、rollback/retire清缓存；递归UNION/sameScan/NULL根可达，否则整batchrollback。独立review暖缓存cycle≤2秒拒绝、计数不变，是新runtime反例PASS。

## 容量测量（不是产品目标完成）

| 版本/shape | 条目 | DB bytes | test | 默认250MiB预算 |
|---|---:|---:|---|---|
| root旧schema4合成参考（非合法Run/migration） | 200000 | 335470592 | 实验脚本exit0 | 超预算，仅参考 |
| schema5旧DESC typical，末次cache/cycle前 | 1000000 | 278249472 | exit0/测量PASS | FAIL，超6.14% |
| schema5 ASC/cache 100k（末次ancestor前） | 100000 | 26296320 | exit0/测量PASS | 本shape分项在预算内，不外推1M |
| schema5 ASC longRandom，最后ancestor前 | 1000000 | 413855744 | exit0/测量PASS | FAIL |

详细shape差异见[PERFORMANCE](PERFORMANCE.md)：旧200k目录JSON0/counters空、scanJSON容量marker，不视同分布压缩率或合法API迁移。typical写265.029s/RSS41.37MB；longRandom写276.443s、RSS26427392B/meanpath252.498，dashboard1.017ms/children2.886ms、sort31–55ms、非空搜索2.538/3.233s。测量cap2GiB只为footprint，生产250MiB未改；没有创建1M真实文件/扫描用户目标。旧版本指标不继承最终ancestor门禁hash。

## schema5原生UI与制品边界

fresh `.local/schema5-ui-build`，ui-schema5-final exit65自动化初始化timeout无case；同source full retry exit65，其中7cases PASS（真实看板/plan/map、denied+sparse、empty、pending保留、quota未知、indexretire、small dark）；race被Chrome/Ghostty前台遮挡，增加各导航前activate后仅race定向ui-schema5-race-final exit0 PASS，max1/stale discard/newscope invalidation/terminalflush断言均保留。11张retry+race图实际像素检查无遮挡。不能写一轮全8suite exit0。App当时2e7c429，UITest6bab590...。

root newcompact制品exeSHA ba8ea6c399c8d70808ff16b3820825009cc08c32d0f4f9dd226fa67f29816c9d build/verify0，**未launch/真实迁移/扫描**。随后发现App主线程同步migration，正在改async initialization/中文准备提示禁扫与真实old-v4 selfFixture UI；因此旧schema5 UI/App/制品成功不继承当前新改动，全部相应断言UNVERIFIED。

## 继续验收

新异步迁移成功/失败/取消准备态、禁扫和old-v4 fixtureUI；new source freeze/hash、freshRelease native launch、真实ownDB安全迁移、Data持续到终态与容量/权限/coverage。若预算不可达依据实际证据明确ADR10决定，不quiet升限、不漏普通leaf称complete。VoiceOver/主线程P95/M2清理恢复仍UNVERIFIED或BLOCKED。

## 前轮记录（历史）

# 体验 v2 当前验收：主盘规模路径FAIL

2026-10-13。当前用户目标仍active，**V2-01完整主盘扫描链与V2-12实际规模路径FAIL**；其余分项PASS不能提升完整v2。新compact schema5/6待实现/实测，全项不继承schema4证据。状态以[CONTINUATION](CONTINUATION.md)最终更新为准。

## 真实全盘最终失败

`.local/verification/experience-v2/performance-full-data-run.json`，中间制品exeSHA `7399ae9272d3a9117fed2e83f0da155e68fcc033c34cf657d1eb16daf851d918`。scanID10BE615D-3856-4FA7-8BAE-7910A45AAAAE/PID77906，Data一击5秒约13401项；最终154473项/13582缺口、约3分钟，partial/quotaExceeded，262107136bytes index。JSON早期state=running不覆盖追加terminal字段。目标是完成真实可用分析，不将此FAIL改成“可选小目录即可”。

dbstat entries204685312 bytes、payload165378048、unused37399857；entry_parent14733312、measured约17.4MB、allocated/UUID/topfolders/issues等。250MiB仍按基线保留，不quiet提高预算。旧B619/PID40265已主动cancel20445项/166缺口以换新版，非timeout重启；当前无活动扫描待新源。

## schema4版本定向实测（仅本版本）

- `xcrun swift test --scratch-path .local/index-debug-build`，experience-v2-future-version-final.log exit0（session96610 poll）：47reported，2基准默认skipped；实际系统Trash仍BLOCKED，测试仅拒权限分支。future version5 fixture拒绝，独立before/after验证marker/schema/WAL/parent755/file644未改；不是downgrade migration。
- `LMC_DASHBOARD_BENCHMARK=1 xcrun swift test --scratch-path .local/index-debug-build --filter v2FiftyThousandFilesWithRealDashboardProgress`，experience-v2-dashboard-progress-50k.log exit0（session99302 poll），3次50k真实fixture、每轮callback真实dashboard+children查询：

| trial | wall s | callbacks | total query ms | max query ms |
|---|---:|---:|---:|---:|
| 1 | 13.457714 | 62 | 234.607879 | 6.331334 |
| 2 | 13.220466 | 61 | 231.161038 | 6.506667 |
| 3 | 13.392310 | 62 | 232.702128 | 6.582708 |

RSSpeak23,248,896bytes；DB68,440,064/68,489,216/68,468,736bytes；独立allocated204,804,096bytes/logical51,200,036/entries50102。EXPLAIN四query使用index/PK、无TEMP B-TREE；新增index/counters成本36KiB。cache uncontrolled-warm-contended，保留当时旧nativeCPU99进程；mainThreadBusy/VoiceOver UNVERIFIED。该benchmark先于futureDB门禁补丁，热路径未变但不说最终hash完全重跑。
- freshDerivedData `.local/v2-progress-ui-build`，UI coalesced10原7cases通过，但race delay1.5秒小于GUI派发未制造窗口而计数断言FAIL；保留原log/xcresult。UI coalesced11仅测试delay4秒重跑race exit0，max query任务1、旧page结果丢弃、新scope失效、terminal最新Rows真实断言PASS；干净PNG `63BF4D18-A343-4BA9-B70F-1615FD3A80EE.png`已像素检查。不是完整新源8cases同时重跑PASS。
- formatter dir09定向XCTest exit0，真实000权限self-fixture topFolder/allocated/logical保持未知；正常稀疏文件0KBallocated/629.1MBlogical正确。3图经像素检查；dir07自动化初始化timeout exit65无case，dir08Unicode输入被SystemSettings窗口打断失败保留。
- 新v2-performance build/codesign/open0及源码review APPROVE；`performance-source-hashes.json`绑定Store/App/UITest当前版；独立APPROVE只为源码边界，不授予清理或证明真实主盘完成。

## compact下一版待验证

1M metadata数据库为存储规模实验，不是1M真实文件创建/全盘运行证明。schema5/6须验证lossless完整Entry/fullidentity重建、64位十进制/overflow、坏压缩与迁移rollback、root/UID/pending保护、basename路径/UUID映射和版本拒绝；普通叶子不能丢弃冒充complete。新fresh package/UI/Release/review+真实Data到终态全部UNVERIFIED，后续hash冻结再绑定。

## 前轮判据与证据（历史）

# 体验 v2 修复后验收状态

2026-10-13。首轮真实Data quota/误空看板FAIL作为历史保留；修复后真实bounded链分项PASS，不等全盘完成。**goal仍active，完整Data终态扫描UNVERIFIED**。最新unknown目录0/logical列错误显示修正后须重新绑定源码/原生UI，000 denied真实分支尚未运行。

| 判据 | 当前结论 | 证据边界 |
|---|---|---|
| V2-01 默认Data一击入口 | 分项PASS | native fixedRelease未auto扫，一击真实Data开始；完整扫描终态UNVERIFIED |
| V2-02 实时看板 | 分项PASS | native实时known/unknown非空，indexed累计；最后UI值修正需fresh验收 |
| V2-03 同层地图 | 分项PASS | 真实Data同层8rows/下钻；fixture跨hardlink去重，latest版新图待绑定 |
| V2-06/07 保护与alias | fixture定向PASS | 非敏感app/repo计量不可选，敏感不深入；不是完整真实Data访问spy证明 |
| V2-08 原生状态布局 | 部分PASS/UNVERIFIED | maintenance05+quota06，最新显示修正/denied branch/VoiceOver/主线程busy未验 |
| V2-09 Gate/失效 | 分项PASS | fixturePlanner/disabledGate，生产false；全部范围改变失效UI未验 |
| V2-10 新制品 | fixedRelease分项PASS | hash/verify/open对应修复后制品；最后源码改动不能继承旧制品 |
| V2-11 停止/覆盖 | 分项PASS | native取消/stopReason/unknown194，与完整Data coverage区分 |
| V2-12 长扫/性能 | UNVERIFIED | 完整Data仍待长扫终态与瓶颈检查，不能缩成boundedfixture完成 |

## 新实际证据

- `.local/verification/experience-v2/final-release-build.log` exit0；fixedRelease exeSHA `06ba2901aab176ff267ead83959b20d98b8d199c339978671131458ff3d12de4`，codesign verify0、open native0。实际CUA精确路径首次默认Data不auto扫→一击内置开始→实时看板→停止。
- `.local/verification/experience-v2/real-host-fixed-scan.json`：29344项、unknown194、known约5.26GB、cancelled；stopReason明确未计量；old ownindex266158080→48037888 bytes，schema3/quick_checkok、2 archived summaries。目标mutation actions未调用；仅源码只读边界与UI路径证明，没有全盘文件diff/hash证明。
- `xcrun swift test --scratch-path .local/index-debug-build` exit0（session89776 poll），experience-v2-index-maintenance-verified.log：42 reported，benchmark skipped，Trash仅permission拒绝测试；真实系统Trash仍BLOCKED。新增600files旧DB超256KiB→quota无计量但全局unknown→仅terminal退役/VACUUM→new rows成功；active/pending保护、freelist compact、inode变/硬link拒绝、summary重开、stopReason缺字段兼容、max_page_count32真实SQLITE_FULL stop reason13/globalgap、target sentinel未变。
- 同命令experience-v2-issue-pagination-final.log exit0（session55384 poll），43 reported（1benchmark skipped，不计实际基准）。synthetic global issue只在匹配当前filter且显示时计OFFSET；limit1 offset0/1/2独立IDs、search/category/large/candidate空边界断言。
- xcodebuild Debug test，experience-v2-ui-maintenance-05.log/xcresult exit0，6case：原3cases+40KiB真实pipelinequota停止/旧ownindex重扫terminal退役/pending own staging非空skip维护。随后quota06定向exit0，`.local/experience-v2-ui-quota-06-attachments/365DAC44-1139-4A58-943B-E668C83456DA.png`已像素检查；05 dark图亦无遮挡。后续App新unknown目录/logical列fix需freshUI，不能把旧图继承。

SIGSEGV maintenance-first/diagnose/backtrace/lldb日志与LLDB attach拒绝保留；fresh独立scratch同代码运行通过，能说明与缓存/ABI相符，不能绝对归因或删历史失败。当前最终sourceHash待冻结，新Store分页SHA d28a5215357a9299ef3dab95b63dea242d220e6a54f9afbef24471b85c5b2004；对应fixturetest SHA a4eebf3eae4efddc3293829e2c7f542fe59b4fe4999a790bf9b49e568a5f94c6。

## 前轮判据/失败与维护前证据（保留历史）

# 体验 v2 当前验收

2026-10-13。**真实内置Data扫描路径FAIL，完整目标尚未完成。** 以下阶段结论优先于下方初始表。

- V2-01入口：维护前CUA一击确实解析Data并扫描，便捷入口分项PASS；可用真实扫描链FAIL（200processed/partial，索引超quota不能持久首批）。
- V2-02看板：真实Data FAIL：0entries/0KB/0unknown和无候选误导；不能以partial替完整覆盖，不能把未持久条目当没有文件。
- V2-11覆盖说明：真实Data FAIL：全局quota停止未反映为未知/未覆盖。schema3 stopReason/globalgap修复后须真实复验。
- 新schema3/maintenance其余V2-01–12当前状态UNVERIFIED，runtime维护fixture SIGSEGV两轮FAIL正在LLDB定位。此前平台/UI成功只绑定维护前版本，不继承。

证据：`.local/verification/experience-v2/real-host-first-scan.json`，exeSHA `5b9ce3ed082f4a2102ebbfc74c472afb0871603a0de0ed954686c375adedee4b`；CUA真实App一击内置scope `/System/Volumes/Data`，processed200/issues60/statepartial、dashboard0entries/0known/0unknown；index266158080 > quota262144000，quick_check ok；权限与目标文件未改。原始failure不能删改expected或缩成fixture来通过。

## 维护前版本实际命令（历史，不继承新源码）

- `xcrun swift test --filter CleanerPlatformTests` exit0（session76170 poll）；experience-v2-platform-regression.log，13实际tests/benchmark skipped。5个新fixture覆盖preset metadata只解析不枚举、app/repo保护计量不可选、ssh/session不深入、AI精确缓存边界、children/dashboard独立分类sum/count、0byte、512MiB sparse与hardlink。
- `xcrun swift test --filter v2` exit0（session63678 poll）；experience-v2-platform-review-final.log，7实际tests；malformed old schema0 JSON使migration失败并ROLLBACK，独立query schema/user_version未变；跨同层hardlink mapweights去重，分页IDs/空ID边界。
- `xcodebuild -project App/LocalMacCleaner.xcodeproj -scheme LocalMacCleaner -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath .local/experience-v2-build -resultBundlePath .local/experience-v2-ui-02.xcresult ARCHS=arm64 CODE_SIGN_IDENTITY=- test` exit0，ui02.log/xcresult，3cases。defaultinternal/noautoscan，一击internal/home/downloads无panel；真实fixture分类/建议、same-layer地图/下钻/返回、catalog筛选/大文件选择/Planner与disabledGate、最小dark键盘搜索/排序和emptyfixture。并非真实内置Data完成证据。
- 同命令改resultBundlePath为`.local/experience-v2-ui-dark-03.xcresult`与`-only-testing:LocalMacCleanerUITests/LocalMacCleanerUITests/testSmallDarkKeyboardSearchAndSort`，exit0；dark03.log；无遮挡App截图`.local/experience-v2-ui-dark-03-attachments/C71441FA-49DE-4E4B-BB89-CACF3F309E77.png`经像素检查。ui02的System Settings覆盖深色截图无效，保留本地不算rendered PASS。
- 平台first/second失败保留：源码追加duringbuild、#expect类型检查超时；third后实际通过。UI首轮exit65（fixture.git正确partial而测试错误expect completed、键盘失焦），CmdF FocusState修复后第二轮通过；新维护版本仍需重验。
- 维护前50k三次47.115/25.045/22.557秒，RSS16–19MiB；原PRD无wall30秒预算，不能自造此门槛。mainThreadBusy UNVERIFIED；这些不是schema3性能证据。

## 新维护版本待补证据

精确schema3 migration/summary、terminal退役与pending保留、固定身份ownindex VACUUM、危险自身state拒绝、ENOSPC/取消与全局gap；两次SIGSEGV根因修复后fixture/runtime独立复验；新原生UI/Release/hash/真实Data bounded扫描复验。VoiceOver、真实权限升级、UI cancel、范围变化计划失效、主线程busy、恢复仍未测UNVERIFIED。

## 初始验收判据（保留）

# 体验 v2 验收

2026-10-13；以下完成判据覆盖PLAN的新产品目标，不以研究报告或静态界面代替实现。所有初始状态UNVERIFIED；每次更新必须绑定新源码/规则/fixture版本、宿主、命令exit、原始证据与限制。旧M2 BLOCKED与本轮只读改进分开。

| ID | 新版本判据 | 所需独立证据 | 状态 |
|---|---|---|---|
| V2-01 | 默认内置Data范围、点击才启动、我的文件/下载/自选入口；内置扫描不打开NSOpenPanel | fixture preset/root oracle + native启动/点击回执 | UNVERIFIED |
| V2-02 | 真实SQLite容量/分配/分类/同层目录/建议/缺口看板；未知与未扫不当0 | 独立固定字节布局/SQL分页结果与rendered一致 | UNVERIFIED |
| V2-03 | 地图排行同一层；下钻/面包屑/上移，父子不重复计量 | 独立同层ID/大小expected + native导航 | UNVERIFIED |
| V2-04 | 分配/逻辑/mtime排序、名称路径筛选、建议卡片导向真实列表 | fixture排序/分类oracle + native筛选动作 | UNVERIFIED |
| V2-05 | 仅真实规则称缓存候选；previewOnly不选/不可执行；普通整理与保护计量区分 | 保护/previewOnly/大文件人工decision表 + Planner/Gate断言 | UNVERIFIED |
| V2-06 | app/repo metadata可计量但保护继承不可选；credential/session/cloud不深入 | 自建app/repo/敏感/alias fixture独立文件manifest与metadata/content spy | UNVERIFIED |
| V2-07 | Data别名仅规则判定规范化；实际读取保持anchored/no-follow/单卷 | alias与非alias相同决策oracle；链接/跨卷/范围负例 | UNVERIFIED |
| V2-08 | 1000×680/1180×780、深浅色、空/扫描中/完成/取消/partial/错误/长路径 | 真实原生UI截图+动作结果；截图不替filesystem证明 | UNVERIFIED |
| V2-09 | 导航/选择/范围/规则/忽略变化计划失效，Gate=false不变 | 真实fixture业务链+UI确认disabled/失效验证 | UNVERIFIED |
| V2-10 | 新独立Release构建、启动与源码hash、独立review | 新build exit/hash/codesign/open/UI观察；旧artifact不继承 | UNVERIFIED |
| V2-11 | 覆盖与权限指引准确、不自动提权/终止其他App/清理用户数据 | partial/error实测+范围/覆盖文案核对 | UNVERIFIED |
| V2-12 | 真实大目录资源与交互没有明显回归 | 固定fixture计数/时间/RSS；主线程busy与VoiceOver未跑则UNVERIFIED | UNVERIFIED |

当前仅有官方研究与新Domain源码存在证据；未收到体验v2构建/UI/fixture运行，禁止把旧swift-test-final/旧ui-activate/旧release-manifest提升为新版本PASS。后续原始失败必须保留；条件skip不是实际验收。
