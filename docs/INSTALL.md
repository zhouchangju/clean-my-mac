# 安装文档

本项目提供两种形态：**原生 macOS 应用**（推荐）与 **`lmc` 命令行**。两者共享同一套
扫描/索引/规则核心。当前无分发包，请从源码构建。

## 环境要求

| 项 | 要求 |
|---|---|
| 系统 | macOS 14.0+（在 macOS 26 / arm64 实测） |
| 架构 | arm64（Apple Silicon） |
| GUI 构建 | Xcode 16+（含 Swift 6 工具链） |
| CLI 构建 | Swift 6 工具链（`swift --version` 确认） |
| 可选 | 本地 AI CLI（Codex CLI / OpenCode，用于 AI 分析）；`~/.agents/skills/` 下的 Guardian Skill（用于体检中心） |

## 方式一：构建 GUI 应用

```bash
git clone git@github.com:zhouchangju/clean-my-mac.git
cd clean-my-mac
./scripts/build-app.sh
open .local/build/Build/Products/Release/LocalMacCleaner.app
```

- 产物路径：`.local/build/Build/Products/Release/LocalMacCleaner.app`（未签名，
  首次打开如遇 Gatekeeper 拦截，在"系统设置 → 隐私与安全性"选择"仍要打开"，
  或对自建产物 `xattr -dr com.apple.quarantine` 后再打开）。
- 也可直接用 Xcode 打开 `App/LocalMacCleaner.xcodeproj`，选择 `LocalMacCleaner`
  scheme 直接 Run（Debug）。
- 指定派生数据目录：`LMC_DERIVED_DATA=<路径> ./scripts/build-app.sh`。

### 首次运行

1. 启动后默认进入"存储看板"，点「快速扫描」选择范围（内置磁盘 / 主目录 /
   下载 / 自选目录）。
2. 首次扫描会触发 macOS 文件夹访问授权（TCC）；未授权的目录会在结果中如实
   标注"不可读"，不会静默跳过。需要完整覆盖时，为应用开启
   "完全磁盘访问"（系统设置 → 隐私与安全性）后重扫。

## 方式二：构建 lmc 命令行

```bash
cd clean-my-mac
swift build -c release
# 二进制位于 .build/release/lmc，可软链到你的 PATH：
ln -sf "$(pwd)/.build/release/lmc" ~/.local/bin/lmc
```

SwiftPM 方式无需 Xcode GUI；`swift test` 可运行全部单元测试。

## 可选组件

### AI Runtime（AI 体检中心 → AI 分析）

应用会自动检测 PATH 与常见安装位中的 `codex` / `opencode` / `droid` /
`ollama` / `claude`。要实际执行分析：

```bash
# Codex CLI（示例）
codex --version          # 确认可用且已登录（codex login）
# OpenCode
opencode --version
```

### Guardian Skill（AI 体检中心 → 体检）

体检中心在 `~/.agents/skills/` 下定位以下 Skill，缺失时页面会显示"未找到"：

- `mac-storage-guardian` —— 磁盘审计（`audit.py`）
- `mac-memory-guardian` —— 内存体检（`guardian_inspect.py` / `apply.py`）

> 注意：两个 Skill 需要 **python3 ≥ 3.10**（应用会从 PATH 解析，不使用系统的
> 3.9）。Homebrew 安装即可：`brew install python@3.12`。

## 测试与护栏（开发者）

```bash
swift test                                   # 根包全部测试
(cd Packages/AIAdvisor && swift test)        # AI 模块
(cd Packages/SkillAdvisor && swift test)     # Skill 模块
(cd Packages/Performance && swift test)      # 性能模块
python3 scripts/cli-smoke.py                 # CLI 冒烟
python3 scripts/mutation-check.py            # 变异护栏
xcodebuild test -project App/LocalMacCleaner.xcodeproj -scheme LocalMacCleaner \
  -destination 'platform=macOS,arch=arm64'   # 原生 UI 测试
```

环境开关：`LMC_REAL_RUN=1`（真实运行 AI 分析/体检的 opt-in 测试）、
`LMC_BENCHMARK=1`（容量基准测试）。

## 数据位置与卸载

- 应用数据：`~/Library/Application Support/LocalMacCleaner/`（索引 `index.sqlite`
  与忽略列表；目录 0700 / 文件 0600；1 GiB 配额）。
- 卸载：删除 `LocalMacCleaner.app` 与上述数据目录即可，无守护进程、无
  LaunchAgent、无系统扩展残留。
