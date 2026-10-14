# 02 技术方案：AI 时代升级

日期：2026-10-14。基线：现有架构（见 `docs/development/02-ARCHITECTURE.md`）
+ 扩展边界模式（见 `docs/roadmap/performance-overview/implementation/EXTENSION-PROOF.md`）。

## 1. 总体架构

新增能力全部落在**新 SwiftPM 模块**，App 侧只做薄胶水；既有四个 Cleaner*
目标、Performance 包、执行链路的源码哈希不受影响（除 `Rules.swift` 种子
数据扩充与 `Package.swift`/`CleanerCLI` 的增量修改）。

```
┌─ App/LocalMacCleaner（Xcode 工程，薄胶水）──────────────────┐
│ LocalMacCleanerApp.swift  (+CleanerPage.aiCheckup/.duplicates) │
│ AICenterPage.swift        ← 组合 AIAdvisorUI + SkillAdvisorUI  │
│ SpaceMapPage.swift        ← 组合 CleanerViz + 既有 store 查询  │
│ DuplicatesPage.swift      ← 组合 CleanerExtras                 │
└──────────────────────────────────────────────────────────────┘
        │                    │                    │
┌─ Packages/AIAdvisor ─┐ ┌─ Packages/SkillAdvisor ─┐ ┌─ 根包新增 ──────────┐
│ AIAdvisorCore        │ │ SkillAdvisorCore       │ │ CleanerViz          │
│  RuntimeRegistry     │ │  SkillLocator          │ │  SquarifiedLayout   │
│  RuntimePreferences  │ │  StorageAuditRunner    │ │  TreemapNode        │
│  AIAnalysisRunner    │ │  MemoryCheckRunner     │ │ CleanerExtras       │
│ AIAdvisorUI          │ │  MemoryActionMachine   │ │  DuplicateFinder    │
│  RuntimePanel        │ │ SkillAdvisorUI         │ │  FileTypeClassifier │
│  AnalysisPanel       │ │  CheckupPanel          │ │ （Tests 各自配套）  │
└──────────────────────┘ └────────────────────────┘ └─────────────────────┘
```

模块依赖方向（单向，无环）：
- `AIAdvisorCore`：仅 Foundation（Process/FileManager/UserDefaults）。
- `AIAdvisorUI`：SwiftUI + AIAdvisorCore。
- `SkillAdvisorCore`：仅 Foundation。
- `SkillAdvisorUI`：SwiftUI + SkillAdvisorCore。
- `CleanerViz`：仅 Foundation + CoreGraphics（布局纯函数，可测）。
- `CleanerExtras`：仅 Foundation + CryptoKit（重复文件 + 分类）。
- App：链接上述全部 + 既有 Cleaner* 产品。

## 2. 模块设计

### 2.1 AIAdvisorCore — Runtime 检测与分析执行

```swift
public struct AIRuntime: Sendable, Identifiable, Codable {
  public enum Kind: String, Codable { case cliAgent, localServer }
  public let id: String            // "codex" / "opencode" / "droid" / "ollama" / "claude"
  public let kind: Kind
  public let displayName: String   // "Codex CLI"
  public let executablePath: String?  // nil = 未检测到
  public let version: String?      // 短版本号，带 5s 探测超时
  public var isInstalled: Bool { executablePath != nil }
  public var canRunAnalysis: Bool  // codex/opencode=true; 其余检测到但暂不可执行分析
}

public protocol RuntimeDetecting: Sendable {
  func detectAll() async -> [AIRuntime]          // PATH + 常见目录 + --version
}
public protocol AnalysisRunning: Sendable {
  func run(runtimeID: String, prompt: String, workDir: URL?) async throws -> AIAnalysisResult
}
public struct AIAnalysisResult: Sendable {
  public let runtimeID: String
  public let stdoutText: String     // 展示用回答正文
  public let exitCode: Int32
  public let duration: TimeInterval
  public let timedOut: Bool
}
```

- 检测：`/usr/bin/which` 不可靠（zsh env），实现为直接在 `PATH` 分量 +
  已知安装位（`~/.local/bin`、`~/.opencode/bin`、`/opt/homebrew/bin`、
  `/usr/local/bin`）做可执行文件探测，然后 `cmd --version`（5s 超时，缓存
  60s）。
- 执行命令构造（集中一处，便于漂移维护）：
  - codex：`codex exec --sandbox read-only --skip-git-repo-check --color never
    -C <workDir> -` ，prompt 走 stdin；若支持 `--output-last-message <file>`
    则优先读取该文件作为干净答案（实施时用 `codex exec --help` 确认）。
  - opencode：`opencode run --format default --print-logs=false <prompt>`
    （argv 直传，无 shell 拼接）。
  - 其余 runtime：`canRunAnalysis=false`，UI 显示"已检测，分析适配待续"。
- 默认 Runtime：`UserDefaults` 键 `com.localmaccleaner.air.defaultRuntime`。
- 超时默认 180s，可配置；进程取消用 Task cancellation → SIGTERM。
- CLI：`lmc air list`（JSON）、`lmc air default [<id>]`（读/写默认）、
  `lmc air analyze --runtime <id> [--context-file <path>]`（stdin/文件读上下文）。

### 2.2 SkillAdvisorCore — Guardian Skill 集成

```swift
public struct SkillDescriptor: Sendable, Identifiable {
  public let id: String                 // "mac-storage-guardian"
  public let skillDir: URL?             // nil = 未找到
  public let requiredScripts: [String]  // 相对 scripts/ 的文件名
  public var isReady: Bool
}
public protocol SkillLocating: Sendable { func locate() -> [SkillDescriptor] }
```

- 定位顺序：`~/.agents/skills/<id>`（存在 SKILL.md + scripts 校验）。
- **StorageAuditRunner**：`python3 <dir>/scripts/audit.py --output <tmp>.json`
  （stderr/stdout 合并留档）；解码容错（字段可选），产出：
  `StorageAuditReport { volumes[], candidates[MIGRATE|KEEP_LOCAL|REVIEW],
  permissionGaps[], rawText }`；解析失败 → `rawText` 兜底展示。
  实施第一步必须实跑采样真实 schema 并固化为 test fixture。
- **MemoryCheckRunner**：`guardian_inspect.py run --json` →
  `MemoryInspection { planPath, pressure, candidates[(id,tier,reasons,rss,appName)] }`；
  `apply.py calibration-status --plan <path>` → `calibrationOnly: Bool`
  （任何非预期输出 = fail-closed true 语义处理为"停止"）。
- **MemoryActionMachine**（协议状态机，逐条对应 SKILL.md）：
  1. `inspect()` → 45s 单调预算起点；预算内才允许进入下一阶段；
  2. 压力正常 → 报告并停（零动作）；
  3. `calibrationOnly == true` → 全部标注"would do"；仅当用户点"批准校准"
     → `approve-calibration` → **立即停止**（同轮不做任何清理）；
  4. green Codex 候选：每 plan 至多一个动作
     `terminate-codex --plan --candidate --timeout-seconds <min(15, 余量-12)>`；
     fast 模式余量 <12s 不启动；动作后作废旧 plan，重新 inspect；
  5. yellow 候选：呈现 + "建议手动退出"（needs-user），不可自动化；
  6. 任何失败/超时/证据不完整 → fail-closed 报告已完成与跳过项。
  状态机为纯逻辑 + 注入式执行器，单元测试覆盖每条协议条款。
- 安全红线（编译进类型系统之外，还写进 UI 文案）：不建守护/定时器/后台
  循环；不 SIGKILL；不碰系统进程；不持久化敏感字段。

### 2.3 CleanerViz — squarified treemap

- 算法：Bruls/Huizing/van Wijk 的 squarify（公开学术算法，清洁室实现）：
  沿短边建行，贪心接受使最差纵横比改善的项，锁定行后对剩余矩形递归。
- 输入：`[(id, weight)]` + 容器 rect；输出：`[(id, CGRect)]`。
- 权重预处理（对齐 lemon 的可读性经验，参数可调）：
  `compressed = pow(log2(1 + bytes), exponent)`，默认 `exponent = 4`
  （lemon 为 log^12 过激，取 4 折中；实施时以真实 home 扫描目测校准）；
  top-N 截断（默认 30）+ 小于首项 2% 的丢弃，剩余并入"其他"角块。
- 纯函数 + Swift Testing 单测（黄金矩形、退化输入、权重和为 0 等）。
- 渲染：App 侧 `SpaceMapPage` 用 SwiftUI Canvas/自定义 layout 绘制瓦片，
  数据源 = 既有 `SQLiteScanStore.children/mapWeights`（当前层按需查询，
  绝不整树加载——吸取 lemon 27GB→2.7GB 的内存教训）。
- 导航：`SpaceMapModel`（@MainActor @Observable，独立文件）持有
  `[TreeLevel]` 栈（rid + 名称），前进/后退 = 索引移动；面包屑 = 栈前缀。

### 2.4 CleanerExtras — 重复文件与分类

- `DuplicateFinder`（漏斗，actor，支持取消与进度回调）：
  1. 枚举（FileManager enumerator，跳过符号链接目录与 `.git` 内部），
     普通文件且 size ≥ minBytes（默认 1 MiB）；
  2. 桶 key = 精确 size；单件桶淘汰；
  3. 桶内读头 64 KiB 做 SHA-256 → (size, headHash) 桶；单件淘汰；
  4. 残组逐文件全量 SHA-256（流式 1 MiB 块）；相同 (size, fullHash) =
     真重复组；浪费 = size × (n-1)。
  - 读取失败/权限拒绝 → 记入 skipped（fail-open 于分析完整性、fail-closed
    于结论：未读到哈希的文件永不判重）。
- `FileTypeClassifier`：扩展名集合表（音频/图片/视频/文档/压缩包/安装包/
  AI 模型[gguf|safetensors|onnx|mlmodel|ckpt|pt|bin?→ bin 不归类，避免误报]），
  返回 bitmask，供大文件页过滤。
- App 侧 `DuplicatesPage`：范围（默认 home，可换目录）、进度条（已扫
  字节/已知总量、当前路径）、取消、结果分组列表、导出 JSON（0600）。

### 2.5 规则扩充（`Sources/CleanerCore/Rules.swift`）

- 仅新增 `seedData` JSON 条目，全部 `capability: previewOnly`（加载器
  已强制，违反即启动失败——这是既有安全门，不是新发明）。
- 路径事实来源：lemon `garbage1_zh.xml` 的**路径知识**（非代码表达），
  逐条在我们机器上验证存在性后再写入；matcher 严格用既有三种语义。
- `MobileSync/Backup`、`Backups.backupdb` 维持 protectionReason 保护。
- 同步更新 `Resources/Rules/seed-v1.json`（保持文档一致性习惯）。

## 3. 数据流与接口契约

- AI 分析上下文（App → AIAdvisorCore）：字符串，由 App 用既有
  `Export.report` 的脱敏规则生成（用户名/秘密段打码），内容 = 卷摘要 +
  分类汇总 + top 目录 + 候选规则 + 大文件样本。AIAdvisorCore 不 import
  Cleaner*，保持通用（输入就是 prompt 字符串）。
- 体检结果模型全部 Codable + 容错解码（未知字段忽略，关键字段缺失 →
  降级 rawText）。
- 重复扫描进度：`AsyncStream<DuplicateProgress>`（ scannedBytes,
  currentPath, phase ）。
- 所有新 UserDefaults 键集中定义常量，避免魔法字符串。

## 4. 兼容性与不回归

- pbxproj：一次性预接线新增 App 源文件与 6 个产品依赖（CleanerViz/
  CleanerExtras/AIAdvisorCore/AIAdvisorUI/SkillAdvisorCore/SkillAdvisorUI）。
- `swift test`：新增测试目标 4 个（Viz/Extras/AIAdvisor/SkillAdvisor），
  既有测试零修改（除 Rules 扩充引起的种子规则数量断言，如存在则更新数值
  并说明）。
- 性能：新页面全部 on-demand；无 Timer/轮询/常驻进程；AI 分析与体检运行
  时在独立 `Task.detached(.utility)`，UI 仅订阅结果。
- CLI：新增子命令不改变既有子命令语义；`cli-smoke.py` 保持通过。

## 5. GPL 清洁室边界（评审清单）

- 允许：公开算法思想（squarify、哈希漏斗、时间桶）；事实性路径知识；
  交互模式（下钻/面包屑/悬停）。
- 禁止：复制 Objective-C/Swift 代码、资源文件、XML 规则文件本体、字符串
  表；逐行翻译式改写。
- 执行：每个模块 PR 自查 + 评审对照本清单；规则 JSON 为我方重新撰写的
  表达（字段名/结构均属我方 schema）。

## 6. 测试策略

- 单元：treemap 黄金用例；漏斗命中/漏报/假阳性边界；Runtime 命令构造
  （注入假 ProcessRunner 断言 argv）；Skill 状态机协议条款逐条覆盖
  （注入假执行器）；JSON fixture 解码（真实采样固化）。
- 集成（opt-in 环境开关，沿用 LMC_BENCHMARK 模式）：`LMC_REAL_RUN=1`
  时真跑 codex analyze / guardian inspect 各一次。
- UI：既有 UITest 不动；新增页面手工验收清单（03-TASKS 附）。
