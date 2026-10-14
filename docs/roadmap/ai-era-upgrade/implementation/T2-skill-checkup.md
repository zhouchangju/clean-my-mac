# T2 实施记录：体检中心（SkillAdvisor — Guardian Skill 集成）

日期：2026-10-14。范围：`Packages/SkillAdvisor/**`（SkillAdvisorCore / SkillAdvisorUI / SkillAdvisorCoreTests）。
设计规格：`docs/roadmap/ai-era-upgrade/02-TECH-DESIGN.md` §2.2。未改动 App/、AIAdvisor、Sources/。

## 1. 真实 schema 记录（第一步实跑采样，2026-10-14 本机）

### 1.1 mac-storage-guardian `audit.py --output <file>`

**输出是标准 JSON**（同一份 JSON 同时写 `--output` 文件与 stdout；`--pretty` 才是人类可读文本）。
fixture：`Tests/SkillAdvisorCoreTests/Fixtures/storage-audit-sample.json`（真实采样，
`/Users/leozhou` → `/Users/sample` 脱敏；children 截取每 scope 前 3 条、超长 du 权限警告截断
并注明条数，schema 形状完整保留）。

```
{
  "schema_version": 1,
  "generated_at": "2026-10-14T00:41:00.875466+00:00",
  "mode": "read_only_audit",
  "home": "/Users/sample",
  "internal": {                          // statvfs 卷摘要
    "path", "total_bytes", "used_bytes", "available_bytes",
    "capacity_percent": 92.6, "device_id"
  },
  "external_volumes": [                  // /Volumes 下非隐藏、非内置、可写卷
    { "path", "total_bytes", ..., "volume_uuid", "filesystem": "APFS",
      "protocol": "USB", "solid_state", "writable", "internal": false,
      "device_identifier" }              // 或 {"path", "error"}（读取失败）
  ],
  "scopes": [                            // 默认 10 个 scope：git/Documents/Downloads/
                                         // Movies/Library/Caches/Library/Application Support/
                                         // Library/Containers/Library/pnpm/.cache/.npm
    { "path", "scope", "classification", "actual_bytes", "logical_bytes",
      "sparse_candidate": bool, "warning": str|null,
      "children": [ {同构，无 scope/classification} ] }   // 默认 top 12
  ],
  "notes": [str]
}
```

**classification 真实取值**（与 SKILL.md 散文中的 MIGRATE/KEEP_LOCAL/REVIEW 三分法不同，
以脚本输出为准）：`MIGRATION_CANDIDATE`、`REVIEW_REBUILDABLE`、`REVIEW_APP_DATA`、
`REVIEW_PROJECTS`、`REVIEW_ARCHIVE_SELECTED`。解码映射：MIGRATION_CANDIDATE/MIGRATE→迁移候选；
REVIEW_*→待复查；KEEP_LOCAL→保留本机（当前 audit.py 不产出，解码端预留）；未知值→待复查
（宁可误报不放过）。**KEEP_LOCAL 不在 audit 输出中出现**——SKILL.md 语义里它属于 plan 阶段
的判断，审计阶段只标 MIGRATE/REVIEW。

**权限盲区**：`scopes[].warning` 与 `children[].warning` 内为 du 的
`Operation not permitted` 汇总文本（本机 Containers 有数百条），解码为
`PermissionGap { path, detail }`。

### 1.2 mac-memory-guardian `guardian_inspect.py run --json`

fixture：`Fixtures/memory-inspect-sample.json`（真实采样全量，仅脱敏用户名）。

```
{ "plan_path": "/Users/sample/Library/Application Support/mac-memory-guardian/runs/<ts>-<uuid>.json",
  "plan": {                              // 脱敏公共摘要（无 run id/cwd/会话/可执行身份/命令 MAC）
    "policy_version": "mac-memory-guardian-v2-fast",
    "mode": "fast" | "deep",
    "pressure": { "pressured": bool, "reasons": ["critical"|"sustained-warning"|"swap-churn"|"saturated"] },
    "codex_candidates": [ { "candidate_id", "tier": "green"|"yellow"|"red"|"unsupported",
                            "reasons": [str], "rss_bytes": int } ],
    "app_candidates":    [ { "candidate_id", "tier": "yellow"(恒定), "reasons", "rss_bytes",
                             "display_name" } ] } }
```

注意：**pressure 是 `{pressured, reasons}` 对象，没有 "normal" 字符串**——"压力正常" =
`pressured == false`。失败时退出码 2、stderr 为 `{"error": ...}`。

### 1.3 mac-memory-guardian `apply.py`

子命令：`approve-calibration --plan`、`calibration-status --plan`、
`terminate-codex --plan --candidate --timeout-seconds`（1–60）、`quit-app --plan --candidate`。

- `calibration-status` stdout：`{"calibration_only": <bool>}`（**本机实测当前策略版本为
  `true`，即校准模式**）；协议要求"除恰好一个该布尔外任何输出都 fail-closed"，解码端
  按键数 == 1 且值为 Bool 严格校验。
- `approve-calibration` stdout：`{"status":"approved","record":path}`。
- `terminate-codex` stdout：`{"status","exited","survivor_pids","recovery_record","recovery_status"}`；
  退出码 0 = `exited`+`persisted` 的干净终态；3 = 拒绝/超时等**终态**（合法结果，交状态机报告）；
  2 = 证据错误。
- `quit-app` 在 v1 只做复检并返回 `needs-user`（本模块未接线：黄色候选一律
  "建议手动退出"文案，无自动路径）。

## 2. 模块结构

```
Packages/SkillAdvisor/Sources/SkillAdvisorCore/
  CommandRunning.swift     # CommandResult + CommandRunning 协议 + ProcessCommandRunner（超时/取消 → SIGTERM，绝不 SIGKILL）
  PythonResolver.swift     # python3 解释器解析（PATH→家酿→系统兜底；guardian 脚本需 ≥3.10）
  SkillLocator.swift       # SkillSpec/SkillDescriptor/SkillLocator（可注册更多 skill；SKILL.md+scripts 校验）
  LenientJSON.swift        # 容错 JSON 读取（未知字段忽略、字段缺失返回 nil）
  StorageAuditRunner.swift # 只读审计 + StorageAuditReport 解码 + 建议推导
  MemoryCheckRunner.swift  # inspect/calibration-status/approve-calibration/terminate-codex 命令构造与协议校验
  MemoryActionMachine.swift# 协议状态机（actor，注入 executor + 单调时钟）
Packages/SkillAdvisor/Sources/SkillAdvisorUI/
  SkillCheckupSection.swift# 公共契约 public struct SkillCheckupSection: View + public init()
```

依赖方向：SkillAdvisorCore 仅 Foundation；SkillAdvisorUI = SwiftUI + Core。
全部类型 Sendable；无 Timer/轮询/守护；无任何自动循环体检。

## 3. 状态机与 SKILL.md 协议条款映射表

状态：`idle / inspected / calibrationPending / approved / acting / reporting / failed`。
事件：`beginInspection / approveCalibration / terminate(candidateID)`（仅用户操作触发）。

| SKILL.md 条款 | 状态机落实 | 测试 |
|---|---|---|
| 45 秒单调预算在首条命令前起表；进入下一阶段前检查剩余预算 | `startRound()` 在每次 `executor.inspect()` 前设置 `budgetEnd = clock.now() + 45s`；动作前读取剩余 | insufficientBudgetSkipsAction / terminateTimeoutSecondsRespectsRemainingBudget |
| 用户回复结束当前预算；回复后新开一轮 45s fast run 取新证据 | `terminate()` 必先 `startRound()` 重新 inspect + calibration-status，只使用最新计划 | greenTerminateUsesFreshEvidenceAndSingleShot（命令序列 5 步断言） |
| 压力 normal → 报告判定并停，零清理 | `route()` pressured==false → `reporting`，候选全部 displayOnly | normalPressureStopsWithZeroActions / freshNormalPressureDuringTerminateStopsWithZeroActions |
| calibration_only=true → 全部标 would do 展示，零清理，绝不隐式批准 | → `calibrationPending`，proposals 全部 wouldDo | calibrationModeLabelsAllWouldDo / freshCalibrationModeDefersActionToApproval |
| 仅显式批准后 approve-calibration 该确切计划；**批准后立即停止** | `approveCalibration()` 仅在 calibrationPending 有效；成功 → `approved` 终态；此后 terminate 被拒绝 | approveCalibrationStopsRoundImmediately |
| 每次突变前要求最新一次新体检的独立校准状态为否；true/缺失/畸形/过期 → 停 | terminate 的新轮 inspect 后再查 calibration-status；异常 → `failed` | calibrationStatusFailureFailsClosed / freshCalibrationModeDefersActionToApproval |
| 绿色 Codex：每计划至多一个 terminate-codex；applier 自行活复检 | 动作后 `reporting` 终态（计划作废），同计划再试被拒绝；argv 原样透传给 apply.py | greenTerminate…SingleShot / rejectedOutcomeIsTerminalForPlan |
| timeout-seconds = min(15, 余量-12) 向下取整且 ≥1；fast 余量 <12s 不启动 | `boundedTimeout(remainingSeconds:)` 纯函数：`remaining<12→nil`，否则 `max(1, floor(min(15, remaining-12)))` | boundedTimeoutFormula / boundedTimeoutBoundary / terminateTimeoutSecondsRespectsRemainingBudget（新轮耗 25s → timeout=8 的 argv 断言） |
| 只使用最新 pressured 非校准计划的绿色候选；漂移 → 停 | 新计划中候选缺失 / tier 变化 / 变普通应用 → 不执行 + skipped 报告 | candidateDriftInFreshPlanSkipsAction / candidateMissingFromFreshPlanSkipsAction |
| 黄色候选：呈现一次、建议手动退出，无自动路径 | proposals `needsUser`；点名黄色候选 terminate → 不执行 | yellowCandidatesHaveNoAutomatedPath |
| 任何失败/超时/证据不完整/格式异常 → fail-closed；不重试旧计划 | `failed` 终态；报告已完成与已跳过项；同计划动作被拒 | inspectFailureFailsClosed / terminateFailureFailsClosedWithoutRetry |
| 存活辅助 PID → needs-user 报告，绝不追加信号 | outcome.survivorPIDs → skipped 明细 | survivorPIDsReportedAsNeedsUser |
| 校准状态查询任何非预期输出（多键/非布尔/非零退出）→ 停 | `MemoryCheckRunner.calibrationStatus` 严格协议校验抛错 → 状态机 failed | calibrationStatusStrictProtocol（runner 层）+ calibrationStatusFailureFailsClosed |
| 绝不建守护/定时器/后台循环；绝不 SIGKILL | 状态机仅事件驱动；ProcessCommandRunner 超时/取消只 `terminate()`（SIGTERM） | （编译结构保证 + 无 Timer 引用） |

## 4. UI 要点（`SkillCheckupSection`）

- 公共契约保持：`public struct SkillCheckupSection: View` + `public init()`（App 侧
  AICenterPage 无改动）。
- 两卡片：磁盘体检 / 内存体检，各含运行按钮、运行中状态、结果渲染；运行逻辑在
  `Task.detached(.utility)`，UI（@MainActor @Observable model）只订阅结果。
- 磁盘卡片：卷容量表 + 三色分类表（迁移候选橙 / 保留本机蓝 / 待复查黄）或 rawText
  滚动兜底；建议列表；权限盲区折叠；常驻提示"审计只读，不迁移任何文件"。
- 内存卡片：压力徽章、状态徽章、剩余预算；候选行（tier 色点、原因、RSS、应用名）；
  绿色候选行内「终止（受控）」按钮 → confirmationDialog 引用协议事实（候选 ID、RSS、
  原因、SIGTERM 单发语义）→ 确认后走状态机；校准模式"批准校准"按钮（确认后显示
  "已批准，本轮不做任何清理"）；黄色行只显示"建议手动退出"。
- 底部常驻声明："以上动作由 Skill 安全协议执行；本应用不新增任何删除路径。"

## 5. 测试结果

- `Packages/SkillAdvisor` 内 `swift build` 零警告；`swift test` **38 用例 / 7 套件全绿**
  （磁盘解码与容错 5 + 磁盘 argv 3 + 内存解码 2 + 内存 argv 5 + 状态机条款 21 +
  真跑 1[LMC_REAL_RUN 门控] + PythonResolver 1）。
- 真跑（`LMC_REAL_RUN=1 swift test --filter SkillRealRunTests`，仅只读命令）：
  `inspect` 5.7s 通过（pressured=true [sustained-warning, saturated]，codex=3 red，app=5
  yellow），`calibration-status` 返回 `calibration_only=true`。**未真跑 terminate/approve。**
- 仓库根 `swift build` 通过、`swift test` 82 用例全绿（无回归）；根 `swift test --filter
  SkillAdvisor` 0 匹配退出码 0（SkillAdvisor 测试在子包内运行）。

## 6. 遗留问题与边界备注

1. **磁盘审计 60s 超时 vs 实际耗时**：本机全量 home 审计实测约 2–4 分钟（du 两遍 +
   Library/Containers 大量权限拒绝路径）。60s 预算按任务规格保留为默认值；LMC_REAL_RUN
   真跑断言因此不含磁盘审计（超时会走 runError 展示路径，功能正确但真跑必超时）。
   建议：后续给 `StorageAuditRunner` 加 `--scope` 注入（聚焦目录）或允许 UI 层传入更大
   超时。
2. **Python 解释器版本**：guardian_inspect.py 使用 `tuple[...] | None` 运行时求值语法，
   系统 `/usr/bin/python3`（3.9.6）直接 TypeError；已实现 `PythonResolver`（PATH 顺序 →
   家酿 → 系统兜底），默认取 PATH 中的 python3（本机 anaconda 3.12.4 实测通过）。
   audit.py 自带 `from __future__ import annotations`，3.9 也能跑，但统一走同一解析器。
3. **KEEP_LOCAL 当前不可达**：audit.py 现版本不输出该分类（属 plan 阶段语义），UI 三色
   表中该分组会显示 0 项；解码端已预留映射。
4. **quit-app 未接线**：黄色候选按协议仅"建议手动退出"文案展示；`apply.py quit-app`
   （v1 本身只复检返回 needs-user）如需接入应作为后续独立项，且同样走确认对话框。
5. **校准模式常态**：当前策略版本 `calibration_only=true`，真实使用中内存卡片会先呈现
   全部 would do；批准后策略版本七天内有效，后续体检 calibration-status 才可能为否。
6. **浏览器标签（browser-observe）与 deep 模式未接入**：按协议 deep 仅用户显式要求、
   浏览器阶段需 Chrome 控制面 stdin 流式观测，均超出 T2 范围。
