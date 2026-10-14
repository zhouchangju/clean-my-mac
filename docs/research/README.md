# 逆向研究档案：CleanMyMac 5.7.1

研究日期：2026-10-12。目的：理解扫描、规则、空间计量、误删保护与界面流程，为后续独立实现个人 Mac 清理软件提供依据。本目录为研究入口，保留原始记录以供溯源。

**已完成两轮研究，并开始实现 Local Mac Cleaner；当前有真实扫描与计划预览的原型应用，受控清理 v1 尚未完成验收。** 已安装并实际验证 REA 原生分析能力，获得可复用的机制证据与设计方案。没有执行真实清理。

现已形成 [原生 macOS 开发文档包](../development/README.md)，包含 PRD、技术方案、数据/规则契约、交互、验收、24个任务和 [AI开发交接Prompt](../development/07-AI-HANDOFF.md)。后续实施以该文档包为设计基线，以下逆向资料为来源参考。

## 阅读入口

| 文档 | 内容 |
|---|---|
| [第二轮进展](../round2-summary.md) | 随包规则库解析、默认选择/备份保护与模型共享文件机制 |
| [知识库深挖](../knowledgebase-deep-dive.md) | 加载链、解码验证、真实表结构/行数和样本 |
| [默认选择与备份](../default-selection-and-backups.md) | 缓存类别例外、最新备份判定、损坏 plist 与语言保护谓词 |
| [模型清理深挖](../model-cleanup-deep-dive.md) | Ollama 全局引用图、共享 blob 条件、GGUF 分片检查与删除计划 |
| [扫描与清理机制](../scanning-mechanisms.md) | 23 模块调查、关键汇编、规则路径、计量和删除边界 |
| [REA 反编译实证](../native-evidence.md) | 四个缓存扫描函数、Evidence ID、重现方法与限制 |
| [随包规则与保护模型](../resource-rules.md) | 知识库模型、557 条筛选资源文案、分类保护与未解部分 |
| [界面观察](../ui-observations.md) | 实际页面、扫描范围设置、截图与交互阻塞 |
| [自研设计](../self-cleaner-design.md) | 第一版范围、数据契约、规则准入、执行流程和验收案例 |
| [覆盖台账](../coverage.md) | 已回答/部分回答/未验证及下一证据 |

## 最重要的发现

- 缓存扫描有 ignore 谓词与知识库分流；部分目录整体计量，部分细分 children。结果携带自动选择状态。
- 文件扫描、规则匹配、层次结果、空间计量和删除执行是分离的机制。暂停/取消检查位于多个循环中。
- 空间计量有 Spotlight 物理尺寸与 FTS 回退路径；不能把逻辑文件大小直接当作可释放量。
- 清理存在直接删除和移入废纸篓两类入口；已经找到保护拒绝分支，但没有证明每条删除都经过它。
- AI 工具有精确缓存子路径；本地模型有 manifest/blob 与分片模型相关结构。会话、模型和用户主动下载内容不能因占空间大而自动归类为垃圾。
- 随包两个 `.cmmkb` 已成功解码，分别通过 291/2 页 HMAC 和只读 SQLite integrity_check。`ScanItems` 有 1,509 行、`ApplicationFiles` 有 1,912 行、`ApplicationInfo` 有 990 行；这些是不同原表的行数，不能相加称为有效清理规则总数。
- 已恢复 ScanItemType 与 ScannerID 的数值映射；其中有 931 行 `ignored`、259 行 `protectedBundleID`、7 行 `deepScan`。库中包含明确的缓存保护维护说明，不能把所有缓存当作可无损删除内容。
- 缓存基类允许自动选择，Gradle 子类明确关闭；正常备份分支按日期降序，分组首项标 latest 且不自动选中。Ollama 删除计划依赖完整 manifest 引用信息，筛选共享 blobs；GGUF 分片检查完整编号集合及头部。
- 随包库完整解码不等于全部运行规则已还原：各类型的完整执行语义与优先级、在线更新后的库、选择到执行全链、全局保护及真实扫描性能仍有缺口。

## 已安装并验证

| 项目 | 当前结果 |
|---|---|
| REA | `6.4.0`，`/Users/leozhou/.local/bin/rea`；从 npm 固定版本安装，使用 `--ignore-scripts` |
| Codex MCP | `~/.codex/config.toml` 的 `mcp_servers.rea`；原配置备份 `config.toml.rea.backup` |
| REA Skill | `~/.agents/skills/reverse-engineer-anything` |
| 原生引擎 | Ghidra `12.1.4`，`/opt/homebrew/opt/ghidra/libexec` |
| Java | Homebrew OpenJDK `21.0.12.1`，仅为 REA 配置对应 JAVA_HOME；未修改 shell 全局 Java 选择 |
| 启动验证 | 独立 MCP stdio 握手成功，170/170 工具，`binary_session` 请求成功 |
| 目标分析 | 首轮四个缓存函数、第二轮更多系统垃圾/备份/模型/知识库函数已取得真实证据；主程序一次分析超时，相关数据库加载部分由定向汇编补足 |

原生分析安装了 Ghidra 与 OpenJDK 21，也由 Homebrew 安装/升级了其依赖。测得这两者分别约 **767 MiB、331 MiB**，合计约 **1.1 GiB**，不含 npm、其他依赖与下载缓存。研究原始证据保持本地（`.local/evidence/`，不入库），未复制整个 app。

## 目标与证据

- `/Applications/CleanMyMac_5.app`，版本 `5.7.1`，build `50701.0.2609301754`。
- bundle ID `com.macpaw.CleanMyMac5`；签名元数据显示 MacPaw Way Ltd、Team `S8EX82NJP6`。仅签名元数据检查，不声称完整信任校验。
- 原始数据位于 `.local/evidence/`（已 gitignore），包含可复核 hash、函数地址、REA Evidence ID、截图、错误回执。

## 边界声明

在数据项匹配语义、真实扫描结果、最终勾选和恢复语义未验证前，不把已解出的表或本报告中的候选路径直接变成批量删除脚本。本研究仅用于理解机制与自研设计，不分发任何原厂代码或资源。

## 上游资料

- [REA 官方仓库与安装](https://github.com/morluto/rea)
- [REA CLI 与 Evidence](https://github.com/morluto/rea/blob/main/docs/cli.md)
- [Apple 应用分析](https://github.com/morluto/rea/blob/main/docs/apple-application-analysis.md)

本项目事实以本机 5.7.1 的证据为准，外部文档只用于工具接入。
