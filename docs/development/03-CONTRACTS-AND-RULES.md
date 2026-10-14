# 数据、规则与状态契约

版本 v0.1 / schemaVersion=1；PRD需求编号保持不变。以下是自研契约，不继承专有数据库的数字枚举或未验证优先级。

## 1. 共同编码规则

- ID采用UUID字符串；时间为UTC ISO8601，另保留文件系统原始纳秒时间供比较。
- 对外JSON的字节数、inode、device均为十进制字符串，避免其他AI生成的JS消费者丢失64位精度；内部使用带溢出检查的UInt64/Int64。不可用值用null及状态，不能用0代替。
- 所有schema拒绝未知必需枚举与非法路径；不支持的schemaVersion不能执行，只允许显示“需升级”。
- 界面日期本地化；路径以实际文件系统语义比较，不一律转小写，不假定Unicode字符串相等就等于同一文件。
- 导出报告默认相对扫描根并脱敏用户名；完整路径导出由用户选择，始终本地文件，不上传。

## 2. 核心对象

| 对象 | 必需字段 | 约束 |
|---|---|---|
| ScanScope | id, roots[], volumeIDs[], policyVersion, includeHidden, createdAt | roots含显示路径、规范定位、目录身份；v1执行限内置同卷 |
| ScanRun | id, scopeID, ruleSetVersion, state, processedCount, startedAt, finishedAt?, issueCounts | state和coverage分开；cancelled不等于complete |
| FileIdentity | volumeID, device, inode, kind, size, mtimeNs, ctimeNs, linkCount, ownerUID, parentChain | parentChain含受限根到父目录的身份，不只存路径字符串 |
| Entry | id, scanID, parentID?, relativePath, identity?, logicalBytes?, allocatedBytes?, measureState, entryState | Entry是发现记录，未必可选；directory聚合不作为执行叶子 |
| RuleDecision | ruleIDs[], category, disposition, actionCapability, reasonCodes[], owner, activity, rebuildCost | disposition与选择状态分离 |
| Candidate | id, entryID, decision, estimatedReclaimableBytes?, estimateQuality, executionEligibility | protect/unknown不可通过勾选变成可执行 |
| IgnoreEntry | id, scopeKind, matchValue, createdAt, enabled | scopeKind=exactPath/subtree/appID/ruleID；新增/撤销使旧计划失效 |
| Selection | scanID, explicitCandidateIDs[], revision | 初始为空；分组选择展开并固定叶子ID，去重 |
| CleanupPlan | id, schemaVersion, scanID, scopeID, ruleSetVersion, ignoreRevision, selectionRevision, action, items[], hash, createdAt, expiresAt | 单动作计划；最长10分钟为设计默认；只允许内存/可信私有存储所建计划 |
| PlanItem | candidateID, sourceRelativePath, rootID, identity, ruleIDs, approvedAction, estimate | 普通文件；树节点、symlink、nlink>1不进入执行 |
| Transaction | id, planID, planHash, state, items[], volumeSampleBefore, volumeSampleAfter? | 确认绑定planHash，不跨计划复用 |
| ItemReceipt | itemID, originalPath, stagedPath?, trashURL?, state, identityBefore, identityAfter?, bytesRemovedLogical?, error?, timestamps | 清理结果与字节估计分开；敏感明细本地0600 |

Plan hash对不可变Plan payload计算，明确排除`hash`字段本身和存储层的可变PlanStatus。对象键按UTF-8字节序排序，item按candidateID排序，UTF-8、无空白、UInt64十进制字符串；可选字段固定显式null。字符串按JSON转义引号/反斜线/控制字符，其余保持UTF-8，禁止依赖字典迭代顺序。再做SHA-256。测试向量固定UUID和Clock，保留人工可核对的规范JSON字节与独立计算的期望hash。hash是变更检测，**不是**导入任意外部计划的授权凭证；v1不接受外来执行计划。

## 3. 空间口径

| 字段 | 意义 | 禁止展示 |
|---|---|---|
| logicalBytes | 文件内容长度 | 不称“占用磁盘” |
| allocatedBytes | 文件系统报告分配大小 | 不称“必定可释放” |
| estimatedReclaimableBytes | 基于动作与已知共享情况的估计，允许unknown | 不用未知=0；不与purgeable直接相加 |
| volumeFreeDelta | 同一卷前后可用空间样本之差，可为负 | 不作为每个文件的精确删除归因 |

硬链接按卷+device+inode去重扫描统计；permanent动作拒绝linkCount>1。APFS clone/快照共享不可仅凭相同内容判断，独占量未知时显示“估计受共享块/快照影响”。目录聚合带knownBytes/unknownCount，不能因一个权限错误把父目录标成完整。

`measureState`: measured / partial / permissionDenied / cancelled / unsupported / unknown。`estimateQuality`: estimate / upperBound / unknown。符号链接可以计链接本身，但不计目标、不进入清理选择。

## 4. 规则结构与优先级

Rule字段：id、version、enabled（严格Boolean）、category、sourceRefs、roots、matcher、exclusions、ownerDetection、activityCheck、minAge?、disposition、capability、reason、rebuildCost、admissionEvidence。

roots为RootSpec数组，只支持`homeRelative`（逐路径段数组）或`selectedRoot`（已选rootID加逐路径段数组），不解释shell变量/命令。RootResolver在测试中注入fixture home，不能改系统HOME；生产始终再与用户所选scope求交集。祖先身份记录volume/device/inode及定位段，叶子另核对mtime/ctime/size；新子文件不会因此自动进入旧计划。用户选择的根若本身是symlink，拒绝并提示选择实际目录。

- disposition = protect / ignore / descend / review / candidate。
- capability = previewOnly / trashEligible / purgeEligible。
- v1 matcher仅支持 exactRelativePath、单层segmentGlob、extensionSet。禁止`..`、绝对Value覆盖root、`**`、任意脚本和未限时正则。后续加regex需另做复杂度/边界验收。
- priority固定：**硬保护 → 范围/卷/类型限制 → 用户忽略 → 规则排除 → 正向候选**；冲突取更保守结果。descend只影响遍历粒度，不授予删除。
- 手选不会绕过protect/ignore。撤销ignore后必须重新评估和生成计划。
- 规则集语法/语义校验整体失败时保留上一个已验证版本；无旧版时仅空间分析，执行禁用，不悄悄忽略坏规则。

上述优先级是独立设计，未宣称与CleanMyMac完全相同。其随包库不得整库导入产品；IsRegex文本、4条缺失分组、全局sentinel等只作为导入反例fixture。

### 硬保护与边界

1. 不为根目录、Home本身、挂载点、系统目录、应用bundle、用户资料库包、代码仓库、云同步域、备份、凭据建立自动清理候选。
2. `.ssh`、`.gnupg`、系统/用户Keychains、认证文件等子树不读内容、不进入执行；如范围包含它们，显示已保护/未深入。
3. `.codex`/`.claude`/类似工具根目录为**仅容器、禁止整体操作**；扫描器只能进入明确的缓存子路径，不能借规则展开其他兄弟目录。会话、记忆、配置、skills/plugins、凭据属于protected subtree。
4. 缓存类别下面仍逐项应用保护和排除；父目录被选中不能吞掉被保护子项。
5. LMC自身状态、staging、journal及未恢复事务保护；旧索引裁剪只能由专属维护逻辑处理，不复用清理规则。

### 初始规则候选与准入

以下是实现输入，不代表已证明对本机安全可删。所有规则初始`previewOnly`。T09要求至少两条规则完成准入并记录证据，才能完成M2；不能拿fixture示例路径冒充两条真实规则。

| ID | 范围/候选 | 默认策略与准入重点 |
|---|---|---|
| RULE-DEV-01 | 标准Xcode DerivedData下单个工程的 `Build/Intermediates.noindex` 普通后代 | 不碰Archives/源码/dSYM；fixture工程重建验证；Xcode及相关构建任务活动时拒绝执行 |
| RULE-DEV-02 | npm默认cache下 `_cacache/tmp` 的过期普通文件 | 配置变更只支持用户显式选定根；年龄阈值初始7天；活动npm/node或状态未知拒绝；先核验官方缓存格式与受控再生成 |
| RULE-AI-01 | `.codex/cache/codex_apps_tools` | 仅此精确根；文件/目录形态按实测匹配，不能推断认证内容可删；活动/再生成未证实维持previewOnly |
| RULE-AI-02 | `.codex/cache/codex_apps_server_info` | 同上，不扫描整个`.codex` |
| RULE-AI-03 | `.claude/telemetry`、明确日志/临时子路径 | 逐根规则，不使用“.claude全部”；排除会话/配置/凭据；未完成准入维持previewOnly |
| RULE-USER-01 | 用户所选范围内的大普通文件，默认筛选≥512MiB | review，永不purgeEligible；明确勾选后只允许trash；阈值为产品默认，可改且边界有测试 |

准入证据必须包括：适用app/工具版本与根解析、用途/可重建说明、受控样例清理后再生成/可正常使用、保护反例、活动检查的覆盖和未知处理、允许动作、失败恢复。不得只以“名字有cache”或“数据库有该路径”准入。

对活动状态，NSWorkspace/已知进程只能提供部分证据。枚举失败、存在无法识别的相关worker、版本未知则`unknown`；不能由“没看到前台窗口”推成inactive。v1不终止其他app/进程。

## 5. 状态机

```text
Scan: idle -> preparing -> running -> completed | partial | cancelled | failed
Plan: draft -> preflight -> ready | rejected -> expired | invalidated
Transaction: prepared -> executing -> completed | partial | cancelled | needsRecovery
Item: pending -> prechecked -> staged -> trashed | purged
                         \-> rejected
                  staged -> restored | restoreConflict | interruptedUnknown
```

ready不是授权；用户明确确认当前hash和动作后才进入executing。进程重启后丢弃内存授权。10分钟过期、文件/祖先身份/规则/忽略变化、权限或卷变化均使计划需重新评估。过期检查使用注入Clock，测试不能依赖真实等待。

双击执行或同计划重复调用必须得到同一transactionID或明确alreadyRunning；已完成事务不能再次执行。取消/部分失败后“重试”必须重扫/重新预检未完成项并形成新计划，不能继续用旧确认。

恢复要求：记录原始位置；Trash来自staging时，Finder“放回”的位置可能是staging，不能声称系统会自动恢复原位置。应用“恢复到原位置”必须根据收据和对象身份做无覆盖移动；存在同名文件、Trash项目已被用户处理、跨卷/权限变化则拒绝覆盖并给人工指引。永久删除没有恢复入口。

## 6. 执行不变量（INV）

- INV-01：scan/plan路径不调用任何target mutation；仅允许写LMC自己的索引/报告。
- INV-02：执行集合是已确认计划的子集，不能加入新出现文件，不能扩大根或动作。
- INV-03：任一永久移除必须有准入规则、普通单链接叶子、身份校验、私有staging对象、可持久journal和当前确认。
- INV-04：路径/规则/活动状态不确定则拒绝；不能以缺失值当安全默认值。
- INV-05：一次动作前后都有可对账记录；未知结果不得自动重复执行。
- INV-06：不覆盖恢复目的地、不自动清空系统Trash、不自动清理staging。
- INV-07：移动不等于释放，测试结果不等于真实用户收益，估计不等于精确计量。
- INV-08：拒绝的行必须有reason code；“已完成”仍明确列出失败/跳过/未知。

## 7. CLI 边界

生产CLI仅提供 `scan --root ... --json`、`plan --scan ... --selection ... --action ... --json`、`inspect-receipt ...`，不暴露静默真实删除命令。任何缺少root的scan报参数错误，不默认扫Home。

测试target提供独立fixture执行入口，必须由测试创建私有临时根、保存不可混淆marker与root identity；同一个参数指向Home/软链接/非自建目录时拒绝。fixture模式不能成为生产绕过入口。
