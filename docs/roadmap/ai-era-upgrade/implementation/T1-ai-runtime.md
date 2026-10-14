# T1 实施记录：AI Runtime 中心

日期：2026-10-14。状态：**已完成**（build / test / 本机实跑全绿）。

## 做了什么

| 文件 | 内容 |
| --- | --- |
| `Packages/AIAdvisor/Sources/AIAdvisorCore/RuntimeInfo.swift` | `AIRuntime` 模型（id/kind/displayName/executablePath/version/canRunAnalysis）、`AIRuntimeCatalog` 受支持清单、`RuntimePreferences`（UserDefaults 键 `com.localmaccleaner.air.defaultRuntime`，fail-closed） |
| `Packages/AIAdvisor/Sources/AIAdvisorCore/ProcessRunning.swift` | `ProcessRunning` 协议 + `FoundationProcessRunner` 默认实现（terminationHandler 等退出、无 Timer/轮询；超时与 Task 取消 → SIGTERM，3s 宽限后 SIGKILL 兜底；stdin 管道异步写入避免 64KB 缓冲死锁） |
| `Packages/AIAdvisor/Sources/AIAdvisorCore/RuntimeDetector.swift` | `RuntimeDetecting` 协议 + 默认实现：解析 PATH 分量 + 已知安装位（~ 按 HOME 展开）做 `isExecutableFile` 探测（排除目录），再 `--version`（5s 超时，版本失败不算检测失败），结果实例级缓存 60s，`forceRefresh` 绕过 |
| `Packages/AIAdvisor/Sources/AIAdvisorCore/AIAnalysisRunner.swift` | `AnalysisRunning` 协议 + `AIAnalysisRunner`：codex/opencode 命令构造、180s 默认超时、中文错误信息含可复制完整命令行、opencode 超长 prompt 字节截断并在结果注明 |
| `Packages/AIAdvisor/Sources/AIAdvisorUI/AIRuntimeSection.swift` | 完整 `AIRuntimeSection`（替换占位）：runtime 列表卡 + 默认 Picker 持久化 + AI 空间分析面板（上下文可用性提示、TimelineView 惰性计时、取消、Markdown 结果展示与复制、醒目声明文案）；`@MainActor @Observable` 视图模型 |
| `Sources/CleanerCLI/main.swift` | `air list` / `air default [<id>]` / `air analyze --runtime <id> [--context-file <path>] [--timeout <秒>]`（仅新增，既有命令零改动；沿用 stderr+exit 2 与 Codec JSON 风格） |
| `Packages/AIAdvisor/Tests/AIAdvisorCoreTests/` | Swift Testing 27 个单测 + 2 个 LMC_REAL_RUN 门控真跑测试 |

## 命令构造最终形态（以 2026-10-14 `--help` 实测固化）

### codex（`codex exec --help` 核对：`-o/--output-last-message`、`-s/--sandbox`、`--skip-git-repo-check`、`--color never`、`-C/--cd`、`-` 读 stdin 均存在）

```
<codex> exec --sandbox read-only --skip-git-repo-check --color never \
        --output-last-message <tmpfile> [-C <workDir>] -
# prompt 经 stdin 管道传入（`-` 参数语义）
# 答案以 <tmpfile> 内容为准（stdout 噪声丢弃）；文件缺失/为空时回退 stdout
```

实测（本机 codex 0.162.1）：`echo "用一句话回答：1+1=?" | lmc air analyze --runtime codex` → `1+1=2。`（干净答案，无会话噪声），约 21s。

### opencode（`opencode run --help` 核对：位置参数 message，无 stdin `-` 通道）

```
<opencode> run --format default <prompt>   # argv 直传，无 shell 拼接
```

- 无 stdin 支持（help 无 `-` 语义），超长上下文按字节截断到 100,000（macOS 单参数 256KB 安全预算，UTF-8 边界修整），结果文本首行注明截断。
- 设计稿中的 `--print-logs=false` 未采用：实测 help 显示日志默认不打且走 stderr，无需该 flag。

## 测试结果

- `swift build`（根包 + AIAdvisor 包）全绿；`scripts/build-app.sh`（Xcode App 含 AICenterPage 集成）BUILD SUCCEEDED。
- `swift test --filter AIAdvisor`（Packages/AIAdvisor）：**27 tests in 4 suites 全绿**（命令构造 argv/stdin、检测探测与版本解析/截断/告警行跳过/目录排除/缓存 60s、prefs 读写与非法值、错误路径含命令行、UTF-8 截断）。
- `LMC_REAL_RUN=1 swift test --filter RealRunTests`：2 tests 全绿（检测本机 ≥3 runtime 且 codex 版本 0.162.x；真跑 codex analyze 得到 "1+1=2。"）。
- 回归：根包 `swift test` 82 tests 全绿；`scripts/cli-smoke.py` exit 0。

## 本机 `lmc air list` 实况（2026-10-14）

```
codex    | codex-cli 0.162.1                | /Users/leozhou/.local/bin/codex
opencode | 1.18.35                          | /Users/leozhou/.opencode/bin/opencode
droid    | 0.159.1                          | /Users/leozhou/.local/bin/droid
ollama   | Warning: client version is 0.32.15 | /opt/homebrew/bin/ollama
claude   | （未检测到）                      | —
```

## 设计偏离与说明

- 版本字符串未严格取"首行"：ollama 在服务未启动时 stderr 首行是连接告警、版本在后续行，故解析取**首个含数字的行**（无则首个非空行）。codex/opencode/droid 行为不受影响。
- `AIRuntime.canRunAnalysis` 为存储属性（由目录 `analyzable && 已检测到` 决定），随 JSON 输出，便于 CLI/UI 直接消费。
- UI 复制按钮用 `NSPasteboard`（AppKit）：macOS SwiftUI 14 无纯 SwiftUI 剪贴板 API，模块依赖仍仅 SwiftUI + AIAdvisorCore。
- 错误态的经时显示用 `TimelineView(.periodic)` 惰性驱动，无常驻 Timer。

## 遗留问题

1. **droid/ollama/claude 分析适配**：`canRunAnalysis=false`，UI 标注"已检测，分析适配待续"；命令形态待各自非交互模式调研（ollama 需先选模型，droid/claude 需核对 exec 语义）。
2. **ollama 版本串**：显示为 "Warning: client version is 0.32.15"（上游如此打印），未做 Warning 前缀剥离（避免过度拟合单一工具）。
3. **CLI analyze 的 prompt 即上下文原文**：不附加顾问系统提示（UI 侧才有完整提示词模板）；若 CLI 也需模板，后续加 `--prompt-template` 开关。
4. **App 内真实 AI 分析体验**：xcodebuild 仅验证编译，AI 分析面板的交互（运行/取消/结果滚动）未做 UI 自动化验收（设计稿 §6 将其列为手工验收项）。
5. **codex 超时强杀**：SIGTERM 3s 宽限后 SIGKILL 仅针对本模块自行启动的子进程；与 SkillAdvisor 的"不 SIGKILL"红线（针对系统/宿主进程）不冲突，评审时如需统一可改为纯 SIGTERM。
