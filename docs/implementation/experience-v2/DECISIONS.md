# 体验 v2 工程决定与版本

2026-10-13；当前实施中。PLAN的用户目标保持不变，不将完成判据缩小为研究/文档。

- 首次启动默认内置Data范围，但不自动扫描；显式点击后一击建立真实scope。它是便捷存储分析入口，不保证权限盲区覆盖完整。
- 只读空间计量可进入app/repo元数据；ScanProtected状态继承，候选/选择/Planner仍拒绝。凭据、会话、云同步与未恢复事务不深入。
- Data卷别名规范化只用于规则分类；真实定位保持anchored路径/no-follow/卷身份，不能把显示路径归一化当文件操作授权。
- 看板、分类、同层地图/排行必须使用同次真实SQLite结果；未知/未扫描不归0，分配/逻辑/估计不混加。目录地图不混用全树父子大小。
- 建议卡片是审阅导航与用途/影响说明。只有规则实际匹配才称缓存，seed仍previewOnly；不提供假健康分、精确可释放量或未实现功能卡片。
- 竞品证据分官方描述/原App运行/设计推断。8页官方研究已交，原App运行与截图像素未核验，不冒充完整竞品用户验收。
- 新版本需新源码hash、fixture与原生UI/runtime/build证据；2026-10-12 Release与旧M2日志保留历史，不能继承为新代码PASS。
- 生产ExecutionGate=false不变，旧M2准入/执行恢复阻塞不阻碍授权的只读产品改进，不据此mark goal complete。

## 实施中版本快照

以下仅绑定当前输入与新Domain；最终源码仍会变化，待实际证据完成后刷新完整hash。

- `docs/implementation/experience-v2/PLAN.md` SHA256 `74537b7db00a539a2a83a8ac71fdca4b8486c4020940f7f67b774d0f33252655`
- `Sources/CleanerDomain/StorageAnalysis.swift` SHA256 `f8d1a161c4a544bc4279314d9202d9a57c2b50a95dc149e6e48cb9e0164d4c4a`

## 真实Data失败后的修复决定（2026-10-13）

真实Native默认scope不能完成有意义看板，status FAIL而不是“无候选”；继续同一产品目标，不缩成mock/test版本。quota仍250MiB，不通过提高上限掩盖历史index膨胀。

schema3需存可持久ScanSummary、ScanRun.stopReason optional与全局unknown gap；专属自身index维护可以退役终态rows，但不碰running/preparing/受pending关联保护的scan。VACUUM必须验证是本App固定身份selfindex，不能成为任意路径清理。自身plans/transactions/receipts/staging非空、symlink或不可读则skip维护；取消不调度target。当前是实施设计，未通过runtime验收，不提前声称安全或已真实维护。

新maintenance fixture两次SIGSEGV真实FAIL，保留first/diagnose/LLDB/backtrace证据；根因未闭合时所有新版本PASS禁止继承。此前App SHA5860083...与旧v2dist SHA5b9ce3...是维护前版本，当前不得当最终制品。待final源hash/evidence完整后刷新。

## 维护修复与真实host分项复验

真实ownindex退役/固定身份VACUUM已在正常权限下运行，266158080→48037888 bytes；archived summaries2、quick_checkok/schema3。只处理App自身终态index数据，不宣称清理用户文件或释放收益。

bounded真实Data复验验证启动/实时看板/停止，非完整全盘coverage。取消仍保留unknown/stopReason；继续长扫验证真实终态和覆盖性能瓶颈，不能把目标缩成fixture完成。

新SQL syntheticIssue分页修复已定向通过。最新App unknown目录0/logical列误0修正后的源与UI还需冻结重验；000 denied原生分支未测保持UNVERIFIED。fixed release与旧UI证据只绑定当时hash，最终hash后再刷新。

旧缓存SIGSEGV与freshscratch成功表现与缓存/ABI问题相符，但未确定绝对根因。保留失败及LLDB attach拒绝记录，不凭fresh绿灯删除历史。

## schema4性能改善与实际规模否证

ownPID sample/EXPLAIN发现每200ms同步重算看板阻塞producer：schema4在insert事务维护scan/category counters，summary PK查询，partial-issues/topfolders index、dashboard展示不做祖先hydration；catalog/Planner仍完整身份。App receive轻量计数，single coalesced后台任务普通完成间隔≥1秒，代次/page/scope参数全校验，terminal强制fresh，取消不等query。各分项测试通过。

但Data真实长扫154473项触达250MiB预算而终态partial，规模路径FAIL。不能以性能改善或默认主盘入口代完整目标，不能丢普通叶子称完整。继续losslesscompact schema5/6、integerID/UUIDblob、basename+parent/fullEntry重建安全迁移及1Mmetadata实验；公共Entry/Plan身份和十进制64位不变。默认预算不改，若证据显示物理不可达可明确重开ADR10，不能quiet扩大。

当前无活跃扫描；B619已主动取消换版，10BE615D终态quotaFAIL。未来需新版本冻结再fresh验证，旧schema4制品与bench不继承。新存储实验不是原目标缩成报告或fixture。

schema4版本绑定：performance-source-hashes.json（Store d60346eb6670bf1960bfe7d854c93b2fbd444dc9eb70a00156bc0a9ac3e3fd08；App 2e7c42936bbb151b34c61738fbbd470ae5bc23724f1862a91863ceec1d7b4e2e；UITest 8c067bddfe1689009806ce8443828c8e3d6ed0fff945a33d4088f11efbd4d3c3）。未来源码正在改变，此为性能版历史hash，不当最终全目标完成revision。

## schema5紧凑存储冻结与异步准备新增工作

Lossless紧凑身份使用内部integer scan/rid/parent与UUID16B映射、basename重建、共享decision/volume、精确UInt64/ns/CRC和有界系统LZFSE；公共Entry/Plan与完整身份不变。独立fixedPlan hash/migration/preflight替换反例通过，关键安全源APPROVE仅对该冻结平台版。

1M typical278249472B与longRandom413855744B测量测试PASS而250MiB默认预算FAIL；两种shape/源版本差异保留，不按200k旧参考推相同压缩率，不把metadata存储实验冒充真实FS全盘成功。下一真实Data终态后才能以资源证据重开ADR10，不quiet提高默认或丢条目。

root发现App初始化主线程同步migration，正在改异步准备、中文提示/禁扫与old-v4 selfFixtureUI。新App源将改变，ba8ea6c中间构建未launch/未真实迁移/未扫描，不能继承为最新交付PASS。旧nativeUI7+race分别PASS而fullsuiteexit65保留。

冻结平台hash：Store5100bd7a77b3ced2913a77945e034f55505981ab060d97a67c687eea4c3429ac；Adapter756a364bfb392a8df18ffe038ce574da769c23d612cee59db3ed4038fb450124；Codeccd679a63e27b6eeb004805efd4a214bcc36947d29fd2c56324b8ae90c896f2ef；Tests7349a25e73ea9743828c9e27c74393913b5093d2a4864373609eebc861314dad。新App与后续变动待final完整源hash重新绑定，以上不是全目标完成revision。

## ADR-10-R1：依据主盘实测重开索引资源预算（2026-10-13）

这是原ADR-10允许的工程设计预算重开，**不改变执行、保护、身份、未知拒绝等安全条件**。原250MiB软设计预算的原始FAIL保持不变。

实际证据：旧schema4在154473项时预算停止；紧凑schema5真实Data一击扫描53CDA106/PID62689从05:54:44Z到06:54:01Z（59分17秒），981096processed/980896stored/17801缺口后因quota终止，DB262135808B。终态JSON compact-native-full-data-terminal.json只输出汇总，遍历仍不完整。均摊约267B/项，1M长随机名413.9MB也说明无损完整身份/名称保留并无任意规模250MB保证。不能删普通叶子/只留大文件，或称选小目录等于主盘完成。

选择：App与CLI/Store统一default索引硬上限1GiB；每批次写入与提交前检查本应用索引所在文件系统可用空间，至少留1GiB，未知/不足则明示partial/unknown并回滚新批次。预期约4M常见形状容量仅线性估算，不是全文件名分布保证；主盘真实覆盖仍待新版本到终态。当前观察可用14792458240B，max1GiB占约7.3%，不能称无成本。保护active/pending/receipt/staging及终态索引维护规则照旧；留存仅当前扫描明细、旧终态摘要，避免无限增长。

替代：继续分块packing可能节省更多，但需新的全局排序/UUID lookup/迁移体系；当前v5已把完整元数据成本降低数倍且RSS未见越500MiB，先有限扩大明示资源预算验证真实范围。不会默增到无限、自动删除任何用户数据、提权或解除M2 Gate。若1GiB仍截断，继续依据终态实测评估压缩/资源成本，不把范围收缩成完成。

新增检查：共享default常数、free space乘法溢出/查询失败拒绝、强制不足/提交前不足/计数与新rows rollback、tiny quota/SQLITE_FULL旧负例保留；新源码/Release/真实Data均待实际验证，旧测量不继承。
