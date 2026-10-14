# CleanMyMac 扫描、空间计量与清理机制：静态证据

> 续查：本文保留首轮范围。第二轮补充了 [默认选择与备份](default-selection-and-backups.md)、[模型清理算法](model-cleanup-deep-dive.md) 和 [规则库解码](knowledgebase-deep-dive.md)；下文相应“未知”应结合续查阅读，不能据此忽略新证据。

调查日：2026-10-12。目标：`/Applications/CleanMyMac_5.app`。用途：为个人 Mac 清理软件提供机制参考。

本报告只使用应用包内二进制、元数据和系统 SDK 头文件；未启动目标，未扫描用户目录，未执行清理。完整机制仍有未解部分，不能把已发现路径直接当作安全删除白名单。

## 证据坐标

所有地址是指定 framework 的 **arm64 映像虚拟地址 VA**，不是加载后的 ASLR 地址或通用文件偏移。`strings -t x` 文件内标号为工具输出偏移，不能和 VA 混用。

- 完整目标身份：[manifest.json](../.local/evidence/scanners/manifest.json)，23 个模块包含 canonical path、文件长度和 SHA-256。
- Objective-C 方法映射：[objc-method-index.json](../.local/evidence/scanners/objc-method-index.json)，1,476 个方法地址。只用于定位，不把 setter/类名等同于业务行为。
- 原始 `*.llvm-objc.txt`、`*.llvm-disasm.txt`、`*.stubs.txt`；`*.annotated.txt` 在汇编直接分支处添加按 `__objc_stubs` 解析的 selector 注释。
- [literal-cross-references.json](../.local/evidence/scanners/literal-cross-references.json) 含 442 个文字/路径汇编引用，重点模块 SystemJunkScanning、AIToolScanning、LocalModelScanning。
- `*.strings.txt` 与 `*.deps.txt` 是线索与依赖证据；单独出现的方法名不能证明被执行。

本机旧版 `otool -ov` 错解 compact ObjC method lists，产生无效 imp 拼接值；**不要使用早期 `*.objc.txt` 的 imp 地址**。本报告方法地址以 Xcode `llvm-objdump --macho --objc-meta-data --arch=arm64` 为准。

| 模块 | SHA-256 |
|---|---|
| SystemJunkScanning | `408f7c54625e60473755bde876ee15da64a261bab3b5334d81abf6926a286295` |
| LegacyScanningCore | `8d42c2a499a1f6700319061139e9b10eee54b6af02ba8d26a428bb55fee3f3c3` |
| FileManagerService | `1a83e1cd20100267928208f4a64b8191e1df5393071ab818ac6a1ed39b8acd86` |
| ScanningCore | `ff25a8d0c1d8f9ceeb0657287ef09c56af0a7075c27daeaad355343f85f45de7` |
| CleaningCore | `5ee529fee8529b2761f06a03e74fe0ea8eb325f90c1af2660c5a247e3af579bb` |
| AIToolScanning | `33b39ab22632824db1789c2ad366c81822e7243e99a073177847b9e6af6648b9` |
| LocalModelScanning | `a00802be223e5db1bdbbb75425982370e70bd16c61bd28d379912a31ce9cac7b` |

## 1. 已确认：缓存扫描有规则分流，不是全盘找“大文件”

`SystemJunkScanning / CMCacheScanTask.scan @ 0x672c`：

1. 在 `0x6764–0x67e8` 组合 `dsStoreFileNamePredicate` 与由 knowledgeBase 初始化的 `CMFileIgnorePredicate`，使用 OR 谓词。
2. `contentOfCachesDirectoryURL` 获得候选，登记待处理个数。开始时已取消则返回 empty result。
3. map 回调 `0x6a00–0x6c24` 对每项等待暂停解除、检查取消、更新扫描进度/当前路径，再调用 `shouldIgnoreObject:`；命中忽略的项不生成结果。
4. 对剩余项，用 `lastPathComponent` 查询 KB 的 `shouldPerformDeepSearchForItem:`（`0x6b24–0x6b64`）。真时进入细分；假时对整个 URL 计量。
5. 未获 helper 授权且计量为零时，该回调跳过项目；有授权时可以保留零大小项目。结果包含 `isResultAutoselectable` 提供的自动勾选状态。

`_performDeepSearchForURL:withFilterPredicate: @ 0x6c2c` 构建 `CMFileURLSequenceModel`，枚举子项，逐项检查取消、ignore、计算大小并追加 `CMFileModel` children。无 children 时不保留空组。**这里确认的是一次子项细分，不能据名字声称无限递归深搜。**

`_fileSizeAtURL:cancellationFlag: @ 0x6f34`：先调 fileSizer；如果返回 0，检查可读性，只有不可读且 privileged performer 已授权时，才调用 privileged `fileSizeAtURL:`。这是普通扫描与提权能力的明确分界。

**已知不足**：KB 哪些项进入 deep search、默认 auto-select 如何按模块取值、所有根目录组成尚未全部还原；见资源/KB 调查。

## 2. 已确认：ignore 可以匹配完整路径和末段名称

`LegacyScanningCore / CMFileIgnorePredicate.shouldIgnoreObject: @ 0x1550–0x1718`：

- NSString 分支：先以原字符串查 `knowledgeBase.isIgnoreItem:`，未命中再查 `lastPathComponent`。
- NSURL 分支：先取 path，再查 path 和 lastPathComponent。
- CMFTSEntity 分支：查 path 和 name。
- 未识别的对象类型返回 false。

因此，不能把一个没有限定范围的 basename 规则直接作为自研全局规则：它可能遮蔽不同目录的同名项。原产品的 KB 分类、模块入口与判定组合共同决定适用范围。

`CMFileSizePredicate.shouldIgnoreObject: @ 0x1c74` 的 NSString/URL 分支调用 `CMByteSizer`，然后 `cmp size, limit; cset hi`（`0x1cfc–0x1d00`），即 **size > limit 时忽略**；不是从名字猜测的“仅保留大文件”。具体使用者与 limit 值未追完。

## 3. 已确认：暂停、取消、部分结果与层次聚合

`LegacyScanningCore / CMCompoundScanTask.scan @ 0x4c4c` 顺序枚举 task；每次先 `sleepThreadWhilePaused`（`0x4dd4`）、再 `isCancelled`（`0x4df4`），未取消才调用子 task `scan`（`0x4e0c`）。汇总 children items；若子结果为 compound result，额外汇总 enclosedScanResultErrors（`0x4e40–0x4e7c`），最终创建 compound result。

`CMURLIterator.enumerate:withHandler: @ 0x5484` 也在每项循环中先 pause/cancel，再 filter；filter 通过后计量大小、增加进度、记录 path 并调用 handler。取消会退出当前循环。这说明 UI 的停止不必等待整个文件树扫描结束，但不能证明每个底层阻塞调用都可即时打断。

`ScanningCore @ 0x1d7ac–0x1d800` 对底层对象调用 `maxConcurrentOperationCount` 和 setter；同模块有 NSOperationQueue 引用。这确认存在可配置并发入口，**实际默认值/调度策略未知**。不能把 legacy compound 的顺序循环推广为整个产品单线程。

`ProcessingQueueDependenciesResolver`、`TaskInstanceRegistry`、`ProcessingQueueWatcher`、`TaskWatcher`、`PrioritizableTask` 是静态元数据；timeout/cancel 日志是线索。尚未验证 watcher 的真实超时阈值及恢复策略。

## 4. 已确认：空间计量使用物理尺寸，有取消和缓存路径

### 小目录批量属性

`LegacyScanningCore / _CMGetFileInfoBulk @ 0x5254–0x5480`：

- `open` 目录后使用 `getattrlistbulk`（`0x52e8`），每次缓冲为 `0x400` 字节，循环直到结束。
- attrlist 包含 name/type 和 file total/allocated size 位；依据返回 mask 读取记录。
- 构建 `CMFileInfo(path,size,isDirectory)`，目录初始 size=0。该函数提供一次目录内容的快速属性采集，不代表整个目录树已递归扫描。

### 通用物理计量

`FileManagerService / CMByteSizer._originalItemSizeAtPath:withCancellationFlag: @ 0x28ac–0x2cb8`：

1. 先 `MDItemCreate`、`MDItemCopyAttribute(kMDItemPhysicalSize)`（`0x2924–0x293c`）；获得有效非零数值时直接使用。
2. 未取得有效值时 `fts_open`（`0x29fc`），参数 `0x14`。本机 SDK `fts.h` 确认这是 `FTS_PHYSICAL | FTS_NOCHDIR`，即物理遍历、不改变 cwd，避免跟随符号链接目标。
3. 循环按 `fts_info` 处理条目与错误，读取 `stat` 的 size/blocks 字段。使用 block 计数及 512-byte 换算；存在大尺寸分支，不能等同于直接求 `st_size` 和。
4. 每项对 cancellation flag 做 acquire load；为 1 时关闭 fts 并返回 0（`0x2a2c–0x2a3c → 0x2be0–0x2be8`）。
5. 错误日志经过 `_hideUserNameForPath:`，静态确认了一处路径脱敏。

`logicalByteSizeAtPath:` 与物理尺寸 API 同时存在。`itemSizeWithFTSEntry: @ 0x27b8` 对 link-count 等字段有额外分支，但其调用上下文未完全追踪，**尚不能声称全局 hardlink 去重、APFS clone 去重已经实现**。

**实现启示**：扫描物理尺寸不是“删除后一定释放的字节”。缓存的 Spotlight 值、快照、共享块、权限失败、取消为 0、远程占位符都要求独立状态。自研应报告 `logicalBytes / allocatedBytes / estimatedReclaimableBytes / measurementStatus`，清理后用卷可用空间实测净变化。

## 5. 已确认：有直接删除、废纸篓和受保护删除入口

- `CleaningCore @ 0x9c78` 实际调用 `removeFileAndHandleLockAtPath:error:`。
- `CleaningCore @ 0xa410` 实际调用 `trashItemAtURL:resultingItemURL:error:`，并检查返回值。不能说所有清理都可从废纸篓恢复。
- `FileManagerService / ProtectedFileRemover.removeItemAt: @ 0x121a4` 桥接至 `0x12044`：先调用保护协议判定（`0x120bc`），命中时分配并抛出错误，未命中才到 `removeItemAtURL:error:`（`0x12120`）。
- `ProtectedFileRemover.removeFileAndHandleLockAtPath: @ 0x12418` 桥接至 `0x122bc`；同样先判定保护（`0x12328`），再执行 underlying remover（`0x12394`）。
- 模块静态错误文案：`Refused to remove protected folder at path:`，并有 `isProtectedAtPath:` 对应同一 protocol 查询。

**未确认**：所有入口是否强制通过受保护 remover、protect folder 集合完整内容、rootless 判定的底层实现、删除前是否再次核验 inode/mtime、符号链接竞态是否防护、所有删除路径能否取消/回滚。存在保护类型不等于已证明全局无误删。

## 6. 系统垃圾：已定位的独立策略与风险差异

以下是 **ObjC method metadata 确认存在** 的 task，非逐项完成算法还原。地址均为 SystemJunkScanning 的 `scan` 或所列入口。

| 策略 | VA | 下一步应验证 |
|---|---:|---|
| 应用语言 | `0x2154` | `_shouldScanApplication: 0x2474`、`_shouldIgnoreLanguage: 0x25c4`；当前用户语言/签名保护 |
| 损坏 preferences | `0x4244` | `_isPreferenceFileBrokenWithPlistPath: 0x4840`；解析失败不应直接等同垃圾 |
| 失效 launchd agents | `0x4fbc` | `_isAgentInPathOwnedByAnyApp: 0x56d8`；应用归属与可执行文件存在性 |
| 失效 login items | `0x5b20` | 注册项检查与系统版本分支 |
| App Store downloads | `0x8f4c` | manifest `purgeablePaths 0x9780` |
| Dropbox cache | `0x9f2c` | 正在同步/本地仅存文件保护 |
| Electron cache | `0xad58` / `_scan 0xae18` | 具体 cache 子目录与应用版本 |
| 硬编码应用缓存 | `0xb834` | 见下文已确认控制流 |
| 已删除用户目录 | `0xd310` | 默认勾选与确认边界 |
| 文档历史版本 | `0xdd58` | 版本语义、保留策略 |
| 各类日志 | `0xfc78` | 日志 age、运行中应用 |
| iOS backups | `0x13684` | latest/date 字段和保留最新策略 |
| Universal binaries | `0x1564c` | 签名、可兼容架构；自研初版不实施二进制瘦身 |
| Xcode Archives | `0x17064` | 发布归档与符号文件价值 |
| CoreSimulator caches | `0x181b8` | 在用 runtime/device |
| DerivedData | `0x188d0` | 活跃构建/工程依赖 |
| Device logs | `0x193d8` | age/访问权限 |
| DeviceSupport | `0x19b70` | 当前调试设备、平台/版本 |
| Documentation cache | `0x1a800` | 子路径范围 |
| Downloaded runtimes | `0x1b274` | 真实 installed runtime 区别 |
| ModuleCaches | `0x1c5b4` | 活跃编译 |
| Simulators | `0x1d09c` | availability/state/UDID，不能按目录年代猜测 |

### 硬编码应用缓存已追踪的控制流

`_groupForURLS...` 所在 `0xbb70–0xbf00` 与文件分组 `0xbf00–0xc280`：遍历路径→等待/取消→存在性 `fileExistsAtPath:`→限制 `isFileRestrictedAtPath:`→KB `isIgnoreItem:`→计量（传 cancellationFlag）→再次取消检查→model+group children。

`_groups @ 0xc2ec–0xc46c` 实际依次调用 Telegram / Telegram Lite MAS / Telegram Lite Site / WeChat / 腾讯视频 / QQ Music / Youku / Adobe / SystemMigration / Photos Desktop 专用入口。

- Telegram：组目录 `~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram`（`0xc4c4`），代码检查 `account-` 前缀、枚举 level，追加 `postbox/media`（`0xc590–0xc62c`）。
- Telegram Lite：`tdata/user_data` 下的 `cache`、`media_cache`（`0xc740–0xc884`）。
- 微信：旧版容器 `.../com.tencent.xinWeChat/2.0b4.0.9` 内构造 `Message/MessageTemp`（`0xc8e4–0xcaf4`），不是删整个聊天目录。
- 腾讯视频：`.../com.tencent.tenvideo/.../Download/video`（`0xcb60`）；QQ Music：`.../QQMusicMac/iMusic`（`0xcb78`）；优酷：`.../YTCORE_PLAYER_CACHE`（`0xcb90`）。这些可能是用户主动离线下载，不能因名为缓存就自动移除。
- Adobe：`~/Library/Application Support/Adobe/Common/Media Cache Files`（`0xcba8`）。
- Photos Desktop：该入口按 last-access 比较并从集合移除一个候选，再把余项交给文件分组（`0xce58–0xcf6c`）；具体比较方向未在本轮确认，不声称一定保留“最新”。

## 7. AI 工具与本地模型：对本机目标最有价值的新线索

### AI 工具硬编码 catalog

下面是 **汇编中确有路径文字引用**，不是仅从 UI 猜测；catalog 最终构造和每条选择默认值尚未全面反编译。

| 工具 | 已发现路径/分组 | 关键 VA |
|---|---|---|
| Claude | `.claude/telemetry`、`stats-cache.json`、`mcp-needs-auth-cache.json`、`plugins/install-counts-cache.json`、`shell-snapshots` | `0x7180–0x7214` |
| Claude 旧版本 | `.local/share/claude/versions` 与 `.local/bin/claude` 成对引用 | `0x7240–0x7254` |
| Codex | `.codex/cache/codex_apps_tools`、`.codex/cache/codex_apps_server_info` | `0x73c0–0x73e8` |
| Gemini/Antigravity | browser-profile 的 Cache、Code Cache、GPUCache、DawnGraphiteCache、DawnWebGPUCache、Service Worker/CacheStorage、crx caches | `0x74cc–0x7608` |
| Cursor Agent | `.local/share/cursor-agent` | `0x76f4` |
| OpenCode | `.local/share/opencode/log` | `0x77b0` |
| Chrome DevTools MCP | chrome-profile 的浏览器缓存子目录 | `0x78ac–0x7a0c` |

`AIToolScanning` 元数据另有 `ActiveVersionResolver`、`StaleVersionGuard`、`activeVersionSymlink`、`caches/logs/temporary/staleVersions`。**推断**：旧版本清理可能先解析当前启动链接并保留活动版本；**未确认**：解析失败时是否 fail-closed、版本目录边界、防链接越界行为。

不要把 `.local/share/cursor-agent` 根目录或任何 `.codex` / `.claude` 根目录直接纳入删除白名单。需要还原 catalog target 枚举（node/children/glob/activeVersionSymlink）并测试；尤其会话、认证、skills、plugins 配置与缓存必须分开。

### 本地模型

`LocalModelScanning` 静态元数据确认 LMStudioStoreScanner、OllamaStoreScanner、LocalModelRemovalPlan、GGUFCandidate、ShardFileName；字段包括 partNumber/partCount、shardURLs、manifestURL/blobURLs、blobReferences、exclusiveBytes、unresolved。`0x19840` 实际引用 `models/manifests`。

**推断**：设计考虑 GGUF 分片模型和 Ollama manifest 引用共享 blobs，删除计划按模型聚合，区分独占可回收字节。**未知**：引用计数实现、损坏 manifest 是否阻止清理、选择多个模型后联合回收量、模型根目录环境变量支持。未据此扫描或删除本机任何模型。

## 8. 其他扫描模块覆盖边界

23 模块的身份、字符串和依赖均已留存。下列仅完成定位，算法需要后续分层追踪：

- `OrganizeScanning`：存在 accepted content kind、文件名正则、路径前缀、hidden URL、minimum file size ignore rule；实际 threshold 未确认。不能从 Gemini Duplicates 文案认定相似度算法。
- `SpaceLensScanning`：存在 customIgnorePaths、threshold、totalScannedSize、cloudStorageHelper、volumeBackupSizeCacher；空间树裁剪阈值未知。
- `DownloadsScanning`、`UnusedDiskImagesScanning`：下载/镜像筛选的年龄与安装完成判定未还原。
- `UninstallerScanning`：应用关联残留的 KB/schema/签名/安装收据归属待追；不能用 bundle name glob 替代。
- `CloudStorageScanning`、`MailJunkScanning`、`PrivacyScanning`、`TrashJunkScanning`：需要区分本地缓存移除与云端/邮件内容删除。
- `MalwareScanning`、`PerformanceScanning`、`UpdaterScanning`：与磁盘清理相关度较低；已有身份清单，本轮未证明安全检测/优化/更新算法。

## 9. 自用软件实施建议（新设计，不是原程序事实）

第一版聚焦本机空间：只读占用图、明确缓存候选、开发工具派生产物、AI 工具缓存；保留每项来源/规则/影响说明。模型管理后续独立做；云端、邮件、语言包、fat binary 瘦身、系统级性能修复不进入默认一键动作。

建议核心流程：

`限定根目录 → 路径标准化 + 不跟随 symlink → 规则判定 → 元数据/尺寸 → exclusions + 当前使用状态 → 可审查候选 → 用户选定 → 删除前重新核验 → Trash 或明确永久删除 → 回执 + 卷空间复测`

每条规则至少有 id/version/category、根目录、匹配方式、排除规则、适用 app/版本、是否可重建、推荐选择、前置条件、操作类型、证据来源。每个候选保存 canonical path、volume/device+inode、mtime、类型、logical/allocated/estimated bytes、measurement status、owner app、选中状态和失效原因。

必须在实现验收中覆盖的真实风险：

1. 计量失败或取消不显示“0 字节无需清理”；继续显示 partial/cancelled/permission-denied。
2. 符号链接越界、路径被替换、父目录与子目录同时选中、同 inode 重复计量、活动文件应有确定行为。
3. Trash 的恢复语义与永久释放空间分开：移到同一卷废纸篓不等于磁盘已回收。
4. 模型共享 blob 至少两个 manifest 引用；只选一个模型时不能移除共有 blob。分片模型不能仅移除首片。
5. 活动版本 symlink 解析失败时跳过旧版本清理。
6. 同步目录先识别 provider/占位符，本机 eviction 与云端删除分开呈现。
7. 扫描可暂停/取消，I/O 限流；异常项逐项记录，禁止一个权限错误吞掉整份扫描。
8. 删除回执记录逐项成功/失败及最终可用空间净变化；不宣称估算值就是实收。

## 10. 本轮完成状态

- 扫描管线、暂停/取消、大小计算、忽略谓词、有限提权 fallback、两种删除调用与保护分支：**部分关键函数静态已确认**。
- 系统/AI 路径规则及广泛功能：**有明确候选与地址，非全部规则还原**。
- 并发默认值、KB 完整规则、模型共享引用算法、全局安全边界、真实扫描性能/结果：**未验证**。
- UI 状态/交互由主调查另行记录；本报告无运行时证据。
