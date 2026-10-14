# Local Mac Cleaner

一款**完全本地、只读优先、可解释**的 macOS 空间分析与 AI 时代清理助手。

项目源于对 CleanMyMac 5.7.1 的逆向研究（[研究档案](docs/research/README.md)）与对腾讯
[lemon-cleaner](https://github.com/Tencent/lemon-cleaner) 交互分析范式的清洁室借鉴，从第一行代码
开始就围绕一个问题设计：**在证明安全之前，绝不删除任何东西。**

- 扫描、规则、计划、执行严格分离；真实删除执行当前**默认禁用**（编译期执行门）。
- 所有分析只读：结果永远附带规则理由、计量状态与权限盲区，而不是"一键加速"。
- 完全本地运行：无遥测、无云上报、无后台常驻进程；索引与配置只存在你自己的用户目录。

## 功能一览

| 模块 | 能力 |
|---|---|
| 存储看板 | 卷容量、分类汇总、洞察卡片、顶层目录占用 |
| 空间地图 v2 | 全页 squarified 矩形树图：点击下钻、面包屑跳级、前进/后退、悬停详情、树图/列表切换 |
| 文件浏览 | 同层目录浏览、搜索、排序（分配/逻辑大小、修改时间）、分页、Finder 显示 |
| 大文件 / 整理建议 | 大文件清单与类型过滤（含 **AI 模型**类别 gguf/safetensors/onnx…）、规则候选与逐项理由 |
| 重复文件 | 尺寸分桶 → 头 64KB SHA-256 → 全量哈希三段漏斗；硬链接组标注；进度/取消/JSON 导出 |
| AI 体检中心 | ① AI Runtime 检测与默认设置（Codex CLI / OpenCode…），把脱敏扫描摘要交给本地 AI 只读分析并给出建议；② 调用本地 Guardian Skill 做磁盘审计与内存体检（见下） |
| 性能监控 | CPU / 内存 / 启动盘实时采样、进程排行、菜单栏概览（另一工作流，见 [性能文档包](docs/roadmap/performance-overview/README.md)） |
| CLI（`lmc`） | `lmc scan` 真实扫描、`lmc plan` 计划预览、`lmc inspect-receipt` 回执检查、`lmc air list/default/analyze` AI Runtime 操作 |

### AI 体检中心（AI 时代特性）

- **AI Runtime**：自动检测本机 `codex` / `opencode` / `droid` / `ollama` / `claude`（PATH 与常见安装位），
  显示版本，可设置默认 Runtime。分析以只读沙箱执行（如 `codex exec --sandbox read-only`），
  AI 输出仅为建议，**永远不会被转化为删除动作**。
- **Skill 体检**：集成 `mac-storage-guardian`（磁盘审计：迁移候选/待复查/权限盲区）与
  `mac-memory-guardian`（内存压力判定与闲置 Codex 进程受控终止）。Skill 的安全协议
  （45 秒预算、校准门、单发动作、fail-closed）被逐条编码为状态机，应用界面即其确认界面，
  绝不绕过协议新开删除通道。

## 安装与使用

快速开始（macOS 14+，Apple Silicon）：

```bash
git clone git@github.com:zhouchangju/clean-my-mac.git
cd clean-my-mac
./scripts/build-app.sh   # 构建 GUI 应用（需要 Xcode 16+）
open .local/build/Build/Products/Release/LocalMacCleaner.app
```

命令行方式与详细说明见 **[安装文档](docs/INSTALL.md)** 与 **[使用文档](docs/USAGE.md)**。

## 安全模型

删除能力被多层门禁约束，任何一层都可否决：

1. 规则加载器强制所有种子规则 `capability == previewOnly`（违反即拒绝启动）；
2. 规则引擎保护谓词（凭证、系统、应用包、Git 仓库、云盘、备份、AI 容器白名单…）；
3. 条目可选择性检查（符号链接/硬链接/保护项不可选）；
4. 计划构造与校验（规范哈希、10 分钟 TTL、修订绑定）；
5. 执行前预检（身份/属主/卷/云/规则新鲜度逐项复核）；
6. **编译期执行门 `ExecutionGate.enabled = false`**——不能被偏好设置、导入计划或启动参数打开；
7. CLI 没有执行子命令；界面确认按钮硬禁用。

详见 [契约与规则](docs/development/03-CONTRACTS-AND-RULES.md)。打开执行门的前置条件记录在
[执行探针文档](docs/implementation/execution-probe.md)。

## 隐私

- 全部处理在本地完成；无网络请求（AI 分析除外——由你主动触发、交给**你自己配置**的本地 AI CLI）。
- 扫描索引存放于 `~/Library/Application Support/LocalMacCleaner/`（目录 0700、文件 0600、
  拒绝符号链接、1 GiB 配额与磁盘保留水位）。
- 导出报告默认脱敏（用户名与敏感段打码）。

## 架构

```
App/LocalMacCleaner        SwiftUI 应用（页面：看板/地图v2/浏览/大文件/重复/建议/AI中心/性能/设置）
Sources/CleanerDomain      纯模型层（条目/决策/计划/回执/契约编码）
Sources/CleanerCore        规则引擎与计划构造（种子规则、保护表、脱敏导出）
Sources/CleanerMacPlatform FD 锚定扫描、紧凑 SQLite 索引（LZFSE+CRC32 元数据、v5 schema）
Sources/CleanerExecution   执行原型（仅测试夹具可用：隔离/恢复/日志、at-most-once）
Sources/CleanerCLI         lmc 命令行
Sources/CleanerViz         squarified treemap 布局（纯函数）
Sources/CleanerExtras      重复文件漏斗与文件类型分类
Packages/AIAdvisor         AI Runtime 检测/偏好/只读分析执行 + 面板 UI
Packages/SkillAdvisor      Guardian Skill 定位/运行/协议状态机 + 面板 UI
Packages/Performance       性能采样与会话（独立工作流）
```

## 开发

```bash
swift build && swift test          # 根包全部测试（含新模块）
./scripts/build-app.sh             # 应用 Release 构建
python3 scripts/cli-smoke.py       # CLI 冒烟
python3 scripts/mutation-check.py  # 变异护栏：三个故意错误实现必须被测试捕获
```

贡献指南见 [CONTRIBUTING.md](CONTRIBUTING.md)；版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 文档索引

- [安装文档](docs/INSTALL.md) · [使用文档](docs/USAGE.md)
- [开发文档包](docs/development/README.md)（PRD / 架构 / 契约 / 交互 / 验收 / 任务 / 决策）
- [实施索引](docs/implementation/README.md) · [性能概览路线](docs/roadmap/performance-overview/README.md)
- [AI 时代升级路线](docs/roadmap/ai-era-upgrade/README.md)（AI Runtime / Skill 体检 / 空间地图 v2 / 重复文件）
- [逆向研究档案](docs/research/README.md)（项目起源，含边界声明）

## 致谢与许可

- 交互分析范式（矩形树图、下钻导航）与部分垃圾路径知识受腾讯
  [lemon-cleaner](https://github.com/Tencent/lemon-cleaner) 启发；该项目为 GPL，
  本项目**未复制其任何代码或资源**，全部为清洁室实现。
- 算法参考：Bruls et al. *Squarified Treemaps*（2000）。

代码以 [MIT License](LICENSE) 开源。
