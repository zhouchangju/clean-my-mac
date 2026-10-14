# 体验 v2 当前状态：真实扫描受外部TCC等待阻塞

2026-10-13；**goal active，真实主盘终态/完整覆盖UNVERIFIED；当前外部权限等待阻塞**。live scan `48FA94B9-4983-445B-A92D-150EC5544434` / PID62394 / exe `3a30c314f7d29b08ccc53c88bf9f590e6211857ffab1ecb0a987106096e915f5`于09:14:46Z仍running：357612processed/16777缺口/DB98390016bytes，未因观察超时重启。

ownPID sample03的2547个producer样本均等待`FileReader.directory→openat`；ownbundle-filtered `resource-native-tcc-wait.log`记录16:57:18 `kTCCServiceMediaLibrary AUTHREQ_PROMPTING`，签名与旧grant不匹配。CUA以安全原因拒绝UserNotificationCenter操作；没有代处理提示或更改权限。已提出用户async状态问题，未答不能视授权/答复，现保留准确run/PID等待。

## 新等待提示版本（只验证fixture）

App2d509c/UITest158808e等待banner源码APPROVE；ui01 exit65自动化初始化timeout无testcase，失败保留。新Releasewait exe `4e0ad61f154f060bfc4b1f133b82fff9aa1a2a7988cee286bdc4708514a6780b` build/sign0。原bundle以 `-lmcUITest -lmcStalledScanFixture`自建目录实测：等待warn→请求停止文案→30秒准备返回、start可用、无fakeRun/notice消失；另一真实32项fixture partial完成后warn消失，selection0/previewdisabled。证据`scan-wait-native-fixture.json`。

该fixture PASS不证明真实blocked syscall可取消，也不等新wait制品默认ownindex/Data runtime；真实live run仍旧3a30版本，源码变化不改变它。最新完整主盘仍UNVERIFIED/外部阻塞，M2Gatefalse/BLOCKED，旧quotaFAIL不变。续接[CONTINUATION](CONTINUATION.md)，历史以下保留。

## 既往证据与失败（历史）

# 体验 v2 当前阶段：schema5安全源已复核，真实主盘仍待验证

2026-10-13；**goal active，完整主盘分析仍未完成**。权威入口[CONTINUATION](CONTINUATION.md)。schema4真实Data quota FAIL历史继续保留；schema5紧凑平台源关键安全APPROVE，但两种1M元数据实验均超默认250MiB，不能整体绿色。

| 工作流 | 当前事实 | 边界 |
|---|---|---|
| schema5紧凑平台/迁移 | 最终53reported tests exit0，3opt基准skip；关键安全源APPROVE | 是50项实际测试含Trash拒权限分支，不是完整M2/全盘PASS |
| identity/Plan一致性 | v4→5完整FI/祖先oracle、固定Plan canonical/hash相同、真实fixture叶替换Preflight拒绝 | 独立复核通过，公共UUID/64位身份不降标准 |
| 循环/缓存安全 | 暖缓存外conn坏祖先环≤2秒拒绝、计数未变；batchrollback/data_version/cache清理 | 最新源码边界通过，不代真实主盘覆盖 |
| 规模实验 | 1Mtypical278249472B；1MlongRandom413855744B，测试测量PASS、default预算FAIL | 旧源/最后祖先收口前源；metadata-only，不是1M真实文件 |
| schema5 UI | full retry总exit65，其中7cases PASS；race定向exit0 PASS | 原初始化timeout与前台遮挡失败保留，不写一次全8exit0 |
| 中间compact Release | exe ba8ea6c399c8d70808ff16b3820825009cc08c32d0f4f9dd226fa67f29816c9d，build/verify0 | **未launch、未迁移真实DB、未Data扫描**，不当完成制品 |
| 新App异步准备 | root发现同步main-thread migration，正在改async初始化/中文准备/禁扫与old-v4自建UI | 最新App/Release/nativeData全部UNVERIFIED，旧UI/ba8制品不继承 |

当前没有真实Data active scan；root仅确认并结束本工程旧dist进程，不碰其他应用。仍需新源冻结、异步准备fixture/UI、freshRelease启动、真实DB安全迁移与Data到终态，再据实际资源证据决定ADR10；不quiet提250MiB、不丢普通leaf冒充complete。M2Gatefalse/BLOCKED保持。

旧失败/版本证据以下保留，当前以本节为准。

## 历史快照

# 体验 v2 当前阶段：规模失败，继续开发

2026-10-13；**goal active，完整主盘分析FAIL，体验v2不能整体PASS。** 权威续接入口：[CONTINUATION](CONTINUATION.md)。便捷入口/看板/分类/地图与局部测试已落地，但真实持续Data扫描在250MiB索引预算截断，不能用“主盘可启动”或fixture通过替代完整用户目标。

- 旧run B61981AD/PID40265已在profile与换版前主动取消：20445项/166缺口；不是观察timeout重启，当前不再running。
- schema4增量计数、查询索引与single-coalesced UI已修性能。新中间制品`.local/dist/LocalMacCleaner-v2-performance.app`，exeSHA `7399ae9272d3a9117fed2e83f0da155e68fcc033c34cf657d1eb16daf851d918`，build/codesign/open exit0；真实Data一击约5秒13401项。
- 新run `10BE615D-3856-4FA7-8BAE-7910A45AAAAE` / PID77906已终态partial：154473项/13582缺口，约3分钟，quotaExceeded，index262107136 bytes。`performance-full-data-run.json`保留早期state=running，但其terminalState/count/reason及CONTINUATION为最终状态，不误读成仍在扫描。
- dbstat：entries204685312 bytes（payload165378048，unused37399857），其余索引/计量等约50MiB；不是只压JSON报告即可解决。当前无活跃扫描，等待新版本，不能重复同版。

## 当前分项证据

schema4新suite 47reported（2opt-in基准默认skip、Trash仅拒权限分支），future版本5独立拒绝/不改schema/WAL/权限PASS；源码review APPROVE不代host全盘完成。50k×3含真实dashboard/children callback：13.22–13.46秒、单次query最多6.58ms、RSS约23MiB/DB约68MiB。UI10原7casePASS但race未制造成功而FAIL；UI11测试delay4秒定向证明max并发1/旧页丢弃/范围失效/terminal最新结果PASS。失败与正确复验均保留。

## 下一步（DOING，不提前通过）

scanner_store实现/评估schema5/6 lossless紧凑存储、integer内部ID/UUID blob、basename+parent/full Entry重建与安全迁移；1M metadata storage实验。不能丢普通leaf假完整、quiet扩大250MiB预算或改变公共身份/Planner保护。root待冻结后fresh构建/review/UI和真实Data再次到终态。所有未来schema5/6验收UNVERIFIED，旧schema4证据不继承。

M2执行Gate=false、旧准入/Trash/恢复阻塞仍保留；本轮只读目标继续，无用户目标清理/提权/覆盖安装/发布/push。完整范围不是mock缩版。历史以下保留，当前以以上和CONTINUATION为准。

## 前轮快照（历史）

# 体验 v2 当前状态（修复后真实host复验）

2026-10-13；**DOING，goal仍active**。首轮quota/空看板FAIL已修正并在真实Data bounded链取得分项PASS；完整内置Data扫描尚未跑到终态，不能称全盘完成。最新看板unknown目录0与logical列误0修正后源码又变化，需fresh原生UI与新制品复验，不能继承前版图证。

实际CUA精确路径`.local/dist/LocalMacCleaner-v2-fixed.app`（exe SHA256 `06ba2901aab176ff267ead83959b20d98b8d199c339978671131458ff3d12de4`），首次默认Data不auto扫→一击先退役own旧terminal index→progress→主动停止：29344项、known约5.26GB、unknown194、cancelled与stopReason“剩余范围未计量”。取消UI响应约1.3秒。真实同层map 8rows，Library约4.61GB+未知、usr约652MB+未知、Spotlight物理未知。own index 266158080→48037888 bytes，schema3/quick_check ok，archived summaries2。证据real-host-fixed-scan.json。

此PASS只涵盖启动/实时看板/停止/专属索引维护；不是完整Data coverage、全树文件hash/diff不变或所有未知分支UI完成。扫描仅只读UI路径与源码边界审查，未调用target mutation action；没有提权或用户现有文件清理。

| 工作流 | 当前证据/状态 | 尚需验证 |
|---|---|---|
| 官方研究 | 8页研究DONE；原App运行未知 | 研究不代产品验收 |
| schema3自身index维护 | 旧index真实维护分项PASS；fixture安全保护/SQL_FULL/summary通过 | 所有新界面变动与完整host持续扫描 |
| 平台新suite | issue-pagination-final exit0，43 reported（50k skipped，Trash拒权限分支） | 不能记43实际含skip；最新源绑定下UI/review |
| 原生UI维护版 | maintenance05 6casePASS、quota06单项PASS；干净quota/dark图已观察 | latest dashboard修正、000 denied branch未跑 |
| bounded真实Data | start/progress/cancel/maintenance PASS | 继续真实长扫到终态，quota/覆盖/性能瓶颈 |
| 最新Release/review | fixed release verify/open exit0，最后MEDIUM分页修复已测 | 最终source冻结hash、独立review收口、新Release/UI |

原SIGSEGV两次日志保留，fresh scratch同代码通过，与旧缓存/ABI不匹配相符但没有绝对根因证明。旧M2准入/执行恢复阻塞继续保留Gate=false；不阻碍只读改进，不将范围缩为mock/fixture。最新验收见[ACCEPTANCE](ACCEPTANCE.md)，决定见[DECISIONS](DECISIONS.md)。

## 前轮状态与原始失败（历史，以上为当前）

# 体验 v2 实施状态

2026-10-13；**DOING / 真实内置Data扫描适用路径FAIL，goal仍active**。用户目标仍是比较CleanMyMac各页面后实际改善便捷全盘/看板/分类建议，未收缩为fixture或文档交付。旧M2阻塞不阻碍只读改进，生产ExecutionGate仍false。

## 当前关键失败

CUA实际打开新dist（exe SHA256 `5b9ce3ed082f4a2102ebbfc74c472afb0871603a0de0ed954686c375adedee4b`），一击`scope.internalDisk`扫描`/System/Volumes/Data`：processed200、60缺口，立即partial；dashboard却0 entries/0KB/0unknown并显示无候选。own index 266,158,080 bytes > quota 262,144,000 bytes，旧trial scan已72073项/partial687，schema2 migration膨胀；SQLite quick_check ok。第一批不能持久化，不能当“没有文件”。原始`.local/verification/experience-v2/real-host-first-scan.json`，status FAIL。没有修改权限/目标文件。

## 修复工作

专属self-index maintenance与schema3正在实现：持久summary/stopReason/global gap；退役terminal index rows、保留running/preparing/pending关联；VACUUM只处理固定身份自身index。App plans/transactions/receipts/staging任一非空、链接、不可读则拒绝maintenance；取消不继续调度target。fixture runtime SIGSEGV已复现两次，LLDB定位中；失败日志保留。当前尚未对真实own index执行新维护，未再验证真实Data扫描。

**schema3/maintenance源代码改变后，旧v2fixture/UI/Release成功不得继承。当前新维护版本构建、fixture、UI、新dist与真实Data复验仍UNVERIFIED。**

| 工作流 | 版本/状态 | 实际证据 |
|---|---|---|
| 官方逐页研究 | DONE（研究） | 8页官方文本/来源；原App运行与像素UNVERIFIED |
| v2维护前平台 | 定向PASS，不等新版本PASS | platform-regression exit0，13实际tests+benchmark skipped；review-final exit0，7实际v2 tests，独立分类/同层/保护/migration反例 |
| v2维护前原生UI | 定向PASS，不等真实Data路径PASS | ui02 exit0，3 cases；dark03 exit0单项；ui02深色截图被System Settings覆盖无效，无遮挡dark03另留 |
| v2真实内置Data路径 | FAIL | real-host-first-scan.json：quota停止但空看板错误 |
| schema3/维护修复 | DOING，runtime FAIL待定位 | maintenance-first/diagnose/lldb/backtrace日志；两次SIGSEGV，不能记通过 |
| 新版本制品/全套复验 | UNVERIFIED | 等新源码hash、fixture/UI/独立review、dist启动与真实Data复验 |

原始历史见本文件下方；新验收索引[ACCEPTANCE](ACCEPTANCE.md)，决定/版本[DECISIONS](DECISIONS.md)。不能将realData适用FAIL用fixture成功替代或mark goal complete。

## 初始交接快照（保留历史）

# 体验 v2 实施状态

2026-10-13；当前 DOING。范围以[PLAN](PLAN.md)为准：实际改善内置存储一击扫描、真实分析看板/分类建议、同层空间地图下钻、搜索排序和覆盖指引。文档研究完成不等产品体验完成。

| 工作流 | 当前状态 | 实际产物与证据边界 |
|---|---|---|
| 官方逐页研究 | DONE（研究） | cleanmymac-official-research.md：8个主页面、官方文本与来源；原App运行/像素/实际清理 UNVERIFIED |
| 新Domain契约 | DOING | StorageAnalysis.swift 已建立preset/category/sort/volume/dashboard类型；未独立验证新版本构建 |
| Scanner/Store | DOING | 只读保护计量、Data别名规则映射、SQL看板/分类/同层查询正在实现 |
| 原生App体验 | DOING | 默认内置范围与快捷入口、看板、地图、建议、覆盖提示正在实现 |
| 新fixture/原生UI验证 | UNVERIFIED | 尚未收到新版本实际命令/退出码/原始产物；旧Release测试不能继承 |
| 新Release交付/独立复核 | UNVERIFIED | 需新版本构建、hash、独立目录启动与review证据 |

只读体验改进独立于旧M2执行阻塞推进。生产ExecutionGate必须保持false；旧规则准入0/2、活动覆盖unknown、Trash/Recovery阻塞仍保留，不据竞品研究放宽清理。现有用户文件无真实清理授权；所有mutating验证只用自建fixture。

新验收索引见[ACCEPTANCE](ACCEPTANCE.md)，工程决定与源码版本见[DECISIONS](DECISIONS.md)。旧docs/implementation/及日志保持历史，不将2026-10-12旧制品数据当本轮验收。
