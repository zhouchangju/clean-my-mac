# 独立源码与证据审查

2026-10-12，交接 T23 工作中审查。审查者仅写本记录；未修改产品、测试或用户文件。源码仍由其他协作者修改，以下结论绑定审查时读到的实现，需要修正后重验。审查不是完整验收。

## 范围与依据

依据 `docs/development/03-CONTRACTS-AND-RULES.md`、`05-ACCEPTANCE.md`、`06-TASKS.md`，读取 Domain/Core/MacPlatform/Execution/CLI、App/UITests、TestSupport、全部当时存在的测试、构建和规则探针脚本，以及实施状态与原始日志。`git diff --staged`、`git diff` 无内容，因为全部开发文件未跟踪；`git status --short` 确认这一点；`git log --oneline -5` 返回仓库尚无 commit，不能声称已有已提交 revision。

## 已确认问题

### [HIGH] 仓库保护仅覆盖 .git，没有保护整个仓库

File: `Sources/CleanerCore/Rules.swift:63`、`:129`；关联 `ScanCoordinator.swift` 的目录遍历。

Issue: 禁止路径段包含 `.git`，但仓库目录本身及其兄弟源码没有仓库检测。含 `project/.git/config` 的目录，`project/large-source.bin` 只要为 512 MiB 普通单链接文件就得到 `review/trashEligible`，`Entry.selectable` 和 Planner 会接受它。UI同时声称“代码仓库”已排除。契约要求保护代码仓库，不只是 Git 内部状态。当前生产执行关闭，因此未发现生产实际删除路径，但候选/计划已突破约定保护。

Reproduction: 在持有的 Fixture 中创建 `project/.git/config` 和 `project/large-source.bin` 稀疏文件，扫描该根，断言源码不应可选；当前路径保护函数不会匹配源码路径，阈值分支会返回 trashEligible。这是源码可确定的反例，本审查未另行编写/运行该反例，不能当作独立运行 PASS/FAIL。

Fix: 枚举阶段识别仓库边界（至少 `.git` 目录及 worktree `.git` 普通文件），将仓库本身及后代统一保护；选择/计划层也检查保护来源。补固定反例并保持根为仓库及嵌套仓库均拒选。

### [HIGH] 测试执行原型没有验证调用根为本次持有的 Fixture

File: `Sources/CleanerExecution/AnchoredProbe.swift:34`、`PrototypeJournal.swift:20`。

Issue: `ownedTestRoot` 名称不是权限证据。初始化仅排除 Home 字符串和根目录 symlink；任一本人可写目录均可建立 staging/journal，继而 snapshot/stage/purge 普通叶子。`Fixture.verify()` 仅由现有测试调用，执行入口本身不要求 token、保存的 root identity 或不可伪造的本次持有资格。根祖先 symlink 也未逐段验证。契约明确要求非自建目录传入同一个入口时拒绝。

Reproduction: 用一个自建但未标记为 Fixture 的 0700 临时目录作为 `ownedTestRoot`，入口没有 marker/token 校验而会接受；不要使用用户现有目录验证。当前 `unsafeKindsAndScopeRejected` 仅测试 Home、链接和叶子类型，没有非 Fixture 根测试。本审查未运行任意用户目录变更。

Fix: 入口接收本次 Fixture 创建得到的资格（token+root device/inode+规范根）并在任何 mkdir/open lock/move 前验证；测试 target 隔离原型，生产不导出它。新增 marker 缺失/错值/root identity 改变/祖先链接反例。

### [HIGH] Trash 后验证失败丢失返回位置且 teardown 删除未完成 journal

File: `Sources/CleanerExecution/AnchoredProbe.swift:118`、`Tests/CleanerExecutionTests/PrototypeTrashTests.swift:9`、`:20`。

Issue: `trashItem` 已发生真实 Fixture 移动后，返回目录 open/身份核对失败会 throw；返回 URL 未先写 durable journal，也未在错误中保留。测试恢复 defer 在成功返回 receipt 后才注册，而外层 cleanup 无条件删除 Fixture（包括 journal）。这会留下无法按持久收据定位恢复的测试 Trash 对象，违反未知结果保留/对账要求。

Observed: 独立运行 `swift test --skip Benchmark`，15:07:16，exit **1**，19 tests 中 18 通过；`systemTrashReturnedURLAndReceiptRestore()` 报 `interruptedUnknown: Trash返回父目录不可定位`。该失败发生在 `trashItem` 调用后的 guard。未查找、恢复或删除用户 Trash 中任何对象；本审查无法证明该次返回位置与最终对象身份，保持 UNKNOWN。

Fix: 在后置验证前持久记录平台实际返回位置（该记录仍为未知/待核验，不能直接当可信执行凭证）；错误也保留 returned URL 和 staged identity。未对账事务禁止 Fixture cleanup；恢复只针对经身份核实的本次对象，无覆盖。加入 post-Trash 验证失败故障注入，独立确认 journal 存续、未知不重删、最终恢复。

## 观察到的保守边界

- `ExecutionGate.enabled == false`，`requireEnabled()` 无条件抛错；App确认按钮禁用；生产 CLI 无 execute/delete/import-plan 命令。当前未见启动参数或 JSON 打开生产执行的方法。
- 所有缓存 seed 只允许 `previewOnly`；规则 JSON 严格 Bool/枚举，坏版本保留上一版；Activity恒 unknown。没有因“未见进程”放宽执行。
- MacFileReader以目录描述符和 `AT_SYMLINK_NOFOLLOW` 查询，不读内容；目录跨卷检查和身份检查存在。根本身 symlink 被拒绝。
- SQL参数绑定，字节值与根聚合做 Int64上限检查；未知测量保留缺口；批次失败 rollback；硬链接按 device/inode去重。尚未独立覆盖所有损坏DB/NULL/恶意父环/配额异常，不声明完整AC通过。
- staging/restore 用 `RENAME_EXCL`；错配对象保留；journal `intent` 不作为重试许可。未见生产永久动作调用这些实验入口。
- UI连接真实 ScanCoordinator、SQLite Store、Planner、Preflight；scan/query代次和计划选择版本校验存在。原生执行/历史恢复没有实现为真实生产链，不能视为AC-25。
- 规则探针只写自建0700根，没有 HOME覆盖；探针明确保留根供审查，未执行共享临时目录清空。Xcode/npm再生成日志 exit 0 仅证明受限可重建，活动证据仍 unknown，0/2准入正确。

## 验收限制与实际命令

实际独立命令：`git diff --staged --stat`、`git diff --stat`、`git status --short`、`git log --oneline -5`、源码/契约/日志读取、`swift test --skip Benchmark`（exit 1）。测试自动创建并操作 Fixture；没有运行用户真实清理、安装、权限提升、发布或 push。初始 `.local/verification/platform-tests-final.log` 两项索引失败在独立本次运行中已通过，历史失败应保留；新 Trash 失败必须保留。

本审查未执行 UI、Release独立启动、网络观测、50k三次性能、权限撤销/挂载/云占位、三项错误变体、外来计划负例、独立固定 canonical JSON/SHA256测试向量、逐 crashpoint 进程退出重启对账；这些保持 UNVERIFIED。现有 hash测试主要测自洽/篡改/TTL，不能证明契约要求的独立规范字节向量。原型 stage race 单测不证明最终永久处理窗口或系统 Trash 的安全性。M2维持 BLOCKED，不能宣称 v1完成；T23目前仅完成一次独立工作中审查，修正后仍需复验。

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 3 | warn |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: WARNING — 3 HIGH 问题需修正并复验；依据产品验收条件，M2继续 BLOCKED。

## 修后复核（15:17工作中快照）

以上初审问题和失败原样保留。复核读取新增 `ProbeAuthorization.swift`、修后 Probe/Journal/Trash tests、仓库扫描保护和 metadata-only ancestor查询、`scripts/mutation-check.py`、独立计划向量、最小窗口/深浅色UI tests及最新日志。未修改源码。

### 原问题复核

1. 仓库保护：Scanner现检测 `.git`目录和worktree普通文件，不读其内容；仓库根/嵌套仓库不深入。第一次修正仍遗漏直接选仓库子目录，已反馈并看到新 `MacFileReader.repositoryAncestor`逐绝对祖先 metadata-only检查、权限错误拒绝和root identity核验。独立 `swift test --filter selectingRepositoryDescendantCannotBypassProtection`（15:16:59，exit 0，**1 test PASS**）覆盖 repo/src与worktree/src为扫描根、只保留protected根行且候选为空。扫描反例现已修复。Preflight读取时仍只检查scope内parentChain，尚未调用repositoryAncestor：已反馈需要同样防旧扫描及scope外新增 `.git`，当前Activity unknown/Gate关闭仍阻止实际生产操作。

2. Fixture资格：Probe/Journal改为接受 `ProbeAuthorization`，在任何staging/journal创建前校验保存的creation-time dev/inode、0700本人目录、UUID token、单链接普通marker及token字节。错误token/inode、非持有根、根替换测试已通过。资格仅内部类型，无生产API/CLI路径。原“任意可写目录即接受”问题已修正。祖先链接、完整对抗竞态与测试root持有协议的全部验收仍不能由这组测试代替。

3. Trash未知结果：现在先只读检查系统Trash可验证能力，权限失败发生在trashItem之前；fixture staged内容核对后无覆盖restore。系统returnedURL先以 `trashReturnedUnknown`刷盘记录再后置身份验证，未知不重试；失败不teardown未完成fixture。该代码改善原问题，但没有完成成功Trash→验证→journal→重启→恢复实机证据。`.local/verification/execution-authorized-tests.log` 10 tests通过，其中Trash用例明确打印 **BLOCKED errno=1；动作未开始；fixture stage restored**，不算系统Trash成功。

独立审查15:07旧run没有输出returnedURL，只输出“Trash返回父目录不可定位”；无法提供该次位置，未扫描Trash。`trash-probe-orphans.json`已记录早期一次未知及第二次已知URL，但本审查旧run可能是额外未知项，不能由这两行推出完整对象数量。需保留unknown记录，不能以新测试安全拒绝将旧副作用抹除。

### 本次实际证据

- 独立 `swift test --skip Benchmark --skip systemTrash`，15:14:33，exit **0**，**21 tests PASS**（包括严格codec、保护、TTL、独立canonical向量、真实scan/统计/配额/取消、Fixture资格和原型stage/journal）。当时后续repo子目录新case还未包含，已另跑1项通过。
- `swift test --filter selectedRepositorySubdirectory`是一次错误filter，exit 0但 **0 tests**，不计证据；随后正确filter实际1项通过，如上。
- `shasum -a 256 TestSupport/plan-vector-v1.json`：`97d78f6e8f5f77c8b327a2d18c4f88d873c8194b97421ea848c38c6aef3057e8`，与固定 `.sha256`一致；Swift测试比较canonical字节与固定文件。仍未覆盖全部Unicode键/多item顺序/外来计划边界。
- 三项独立副本错误变体原始日志核对：protect-priority exit 1，保护断言4处失败；identity-bypass exit 1，替换文件错误移动导致独立原路径内容读取ENOENT；trash-is-release exit 1，Trash estimate为4096而非null断言失败。`mutations/results.json`三项均detected，不能将这些局部变体检测视为全部AC-07/15/18 PASS。脚本只复制source/tests到私有工作目录，未将错误实现合入生产、无共享目录teardown。
- `.local/verification/ui-final.log`（15:15:01）显示 **2 tests、4 failures、TEST FAILED**；读扫→选择→禁用计划用例通过；最小窗口dark用例失败。未独立运行或浏览截图，不替UI负责人诊断失败原因，AC-21保持未完成。

### 剩余阻塞

完整逐crashpoint进程中断/重启对账、无journal无变更、最终永久处理竞态、系统Trash成功恢复全链及原生AC-25仍未满足。Activity覆盖unknown、真实规则0/2准入、生产Gate=false继续适用。无完整生产Transaction/Executor/History/Recovery闭环，原型测试通过不构成M2 PASS。旧Trash未知对象与身份缺口仍须明确披露。

## Review Summary（修后工作中）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 1 | warn |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: WARNING — 原仓库保护问题的Preflight外祖先检查尚待补齐；Fixture资格已修，Trash未知信息保留已修但全链BLOCKED。UI失败和M2关键验收缺口仍阻止v1完成。

## 最终定向复核（15:29）

读到 `Preflight.swift` 在任何item评估前新增 `reader.repositoryAncestor(scope: run.scope)`；scope外 `.git` 后出现时整体拒绝旧计划。读取 `PreflightTests.swift/newAncestorRepositoryInvalidatesOldPlan`，独立运行 `swift test --filter newAncestorRepositoryInvalidatesOldPlan`（15:28:50，exit **0**，**1 test PASS**）：自建src根扫描/选择/计划后父目录新增worktree `.git`，预检抛错且文件保留。连同之前已独立通过的仓库根与子目录保护，原仓库保护HIGH结案；未将此一项扩成全部身份失效验收。

最终新增代码/脚本未发现>80%置信度的新增CRITICAL/HIGH问题：`ProbeAuthorization`仍为内部资格，productionGate关闭；App颜色/尺寸参数仅在 `-lmcUITest`启用且没有执行权限路径；UITest两例 `app.activate()`后再验证AX控制，最小尺寸断言仍为1000–1020没有删掉。`scripts/build-app.sh`使用可选LMC_DERIVED_DATA本地构建无安装/发布；mutation脚本仍仅复制错误实现到私有独立测试目录；cli-smoke创建新临时Fixture、保留before/after并拒生产purge命令，未递归清理未知根。此审查没有运行上述脚本新增用户范围变更。

最终日志复核（构建者运行，非本审查重跑）：

- `swift-test-final.log`：**25 tests通过**；`fixed50kBenchmark()`明确 **skipped**；Trash用例仍明确 **BLOCKED permissionDenied，动作未开始，stage已恢复**，不能计Trash成功恢复。
- `ui-activate.log` / `ui-activate.xcresult`：**2 UI tests、0失败、TEST SUCCEEDED**；覆盖浅色真实扫描/选择/计划禁用及1000×680深色窗口/搜索输入。旧 `ui-final.log`失败保留。未覆盖VoiceOver、全键盘导航、三次页面生命周期或执行恢复UI，AC-21/25仍不能整体PASS。
- `clean-release-build.log`：**BUILD SUCCEEDED**，干净单独DerivedData路径。CLI results记录缺root exit2、Fixture scan exit0、purge未知命令exit2、before==after。未由CLI日志推断完整扫描访问spy或全部读权限覆盖。
- 本审查独立运行 `codesign --verify --deep --strict --verbose=2 .local/dist/LocalMacCleaner.app`：exit **0**，valid on disk / designated requirement满足。独立 `file`确认arm64 Mach-O；`shasum -a 256`确认binary为 `bc2928e205cb2586a926bcd08373583e7f4a9ea71ae54ad7502aeabf6554331c`。这证明制品一致性和ad-hoc签名，不证明macOS14/Intel兼容或公证。
- 构建者提供CUA独立dist目录首次启动已看到未选root与禁用scan的观察；本审查未直接操作CUA或看该截图，因此将其视为构建者host证据，不冒充审查者独立GUI接受。
- `trash-probe-orphans.json`现追加独立审查15:07旧run未知项并声明inventory不完整；既有明确位置未被自动恢复/删除，未扫描Trash，历史副作用仍未解决。

原3项源码问题的防护修正已完成并有定向复核，当前源码审查可批准为**执行关闭的开发交付**。Trash成功链/逐crashpoint恢复/永久动作竞态/活动覆盖/规则准入/性能与完整M2验收仍BLOCKED或UNVERIFIED；源码Approve不授予开启Gate、安装、用户清理或发布权限，也不表示v1完成。

## Review Summary（最终源码复核）

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | info |
| LOW | 0 | note |

Verdict: APPROVE — 本次已报告源码问题修正后无残余CRITICAL/HIGH；仅适用于当前生产执行关闭的实现。产品M2仍BLOCKED，完整v1未完成，历史Trash未知项仍待安全对账。
