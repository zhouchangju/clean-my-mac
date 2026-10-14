# T4 实施记录：重复文件漏斗 + 文件类型分类 + 种子规则扩充

日期：2026-10-14。对应设计：`02-TECH-DESIGN.md` §2.4/§2.5；任务拆解：`03-TASKS.md` T4.1–T4.4。

## 1. 交付物

| 文件 | 内容 |
|---|---|
| `Sources/CleanerExtras/DuplicateFinder.swift` | `actor DuplicateFinder`：三段漏斗 + 进度流 + 取消 + 硬链接标注（仅 Foundation + CryptoKit） |
| `Sources/CleanerExtras/FileTypeClassifier.swift` | 扩展名 → `Kind` OptionSet（音频/图片/视频/文档/压缩包/安装包/AI 模型）纯函数分类器 |
| `Tests/CleanerExtrasTests/DuplicateFinderTests.swift` | 真实临时夹具 9 用例（漏斗分层/权限跳过/硬链接/符号链接与仓库内部/进度流/取消/根校验/JSON 编解码/排序）+ opt-in 真机冒烟 |
| `Tests/CleanerExtrasTests/FileTypeClassifierTests.swift` | 分类器 5 用例（覆盖/大小写与多点/未知与隐藏/刻意排除项/中文标题） |
| `Sources/CleanerCore/Rules.swift` | seedData 扩充 9 条规则（4→13）；protectionReason 增加 MobileSync/Backup 保护段（加载/校验/decide 逻辑零改动） |
| `Resources/Rules/seed-v1.json` | 与 seedData 同步（脚本比对通过，逐字节等价） |
| `Tests/CleanerCoreTests/CoreTests.swift` | 仅两处最小改动：规则数量断言 4→13 并注明；新增 `t4SeedRulesDecideAndMobileSyncProtection` 用例 |
| `App/LocalMacCleaner/DuplicatesPage.swift` | 重复文件页：目录选择/进度/分组结果/ Finder 显示/JSON 导出（0600）/取消；无任何删除入口 |

GPL 清洁室自查：漏斗仅依据公开算法思想（尺寸分桶→部分哈希→全量哈希）清洁室实现；
规则为我方重新撰写的表达（字段名/结构均属本仓库 schema）；未复制 lemon 任何代码、
资源文件或字符串表。

## 2. 漏斗实现（DuplicateFinder）

**四段流程**（严格 fail-closed 于结论、fail-open 于分析完整性）：

1. **枚举**：`FileManager.enumerator` 起点为用户给定根 URL（`realpath(3)` 规范化，
   /var→/private/var 与 enumerator 产出口径一致）。`lstat` 逐条过滤：符号链接不收集、
   只收普通文件、`.git`/`.svn` 祖先内部不收集、`size ≥ minBytes`（默认 1 MiB 可参数化）。
   收集 `(path, size, dev, ino, nlink)`；每 256 项 `Task.yield()` 让出。
2. **尺寸分桶**：桶 key = 精确 size，单件桶淘汰。
3. **头部哈希**：桶内读头 64 KiB SHA-256 → `(size, headHash)` 分桶，单件淘汰。
4. **全量确认**：残组流式 SHA-256（1 MiB 块），同 `(size, fullHash)` = 真重复组。

**硬链接**：同 inode 多路径自然同哈希成组，但 `DuplicateFile` 携带 lstat 的
`device/inode/linkCount`；组级 `hardLinked`（任一 nlink>1）与 `distinctObjects`
（同 dev+ino 去重计数）供 UI 标注「删除其一不释放空间」。名义浪费仍为 `size×(n-1)`
（上界），不静默改写——避免把「标注」与「计费」混在一处产生第二种口径。

**失败语义**：读取失败/权限拒绝 → 记入 `skipped: [(path, reason)]`，该文件永不参与
判重；根不存在/非目录/不可读 → 首条 skipped + `incomplete=true`（空结果不伪装成
"没有重复"）；单项失败不置 incomplete。取消即停，返回已累计部分结果（incomplete=true），
进度流必正常 finish 不悬挂（单测断言）。

**进度**：`AsyncStream<DuplicateProgress>`（phase: enumerating/hashing/hashConfirming、
scannedBytes、phaseTotalBytes、currentPath、completedGroups），100ms 节流但阶段切换必发。
扫描在 `Task.detached(.utility)`，UI 只订阅结果。

**JSON 契约**：64 位数值（size/inode/device/linkCount/各项合计）一律十进制字符串承载
（与仓库 Decimal64 口径一致），数值型字段解码直接拒绝（fail-closed）；`wastedBytes/
hardLinked/wastedBytesTotal` 为导出用派生字段，解码忽略。

**确定性**：桶间按最小路径排序、组内按路径排序、组列表按浪费字节降序（并列按首路径）
——同一目录两次扫描报告逐字节等价。

## 3. 文件类型分类器（FileTypeClassifier）

- `Kind: OptionSet`（audio/picture/video/document/archive/installer/aiModel），
  中文标题按位序组合；空集 = "其他"。
- **AI 模型**（AI 时代新增）：gguf/safetensors/onnx/mlmodel/ckpt/pt；**刻意不收 `.bin`**
  ——泛指任意二进制（固件、游戏资源、LFS 指针），误报率过高。
- 其余刻意取舍（表内注释均写明）：`.ts` 不收（TypeScript 远多于 MPEG 传输流）；
  `.key` 不收（TLS 私钥同名，凭据不得标成"文档"）；psd/ai 归图片（用户直觉）；
  iso 归压缩包（光盘镜像≈打包容器而非安装包）。
- 多点扩展名只看最后一段（`a.tar.gz`→gz→压缩包）；隐藏文件（`.gitignore`）与末尾点
  （`name.`）视为无扩展名。纯函数无 I/O，不得用于推断"可删除"。

## 4. 种子规则扩充（4 → 13 条）

全部 `capability: previewOnly`（加载器强制校验，违反即启动失败）；matcher 严格用既有
三种语义；roots 为相对 home 的路径段数组（`exactRelativePath` 走前缀匹配，
`normalizeMacDataPath` 剥 Data 卷前缀后归一）。

| 规则 | 路径（相对 home） | matcher | disposition | 本机验证（2026-10-14） |
|---|---|---|---|---|
| RULE-DEV-03 | Library/Developer/Xcode/iOS DeviceSupport | exactRelativePath | candidate | 不存在 |
| RULE-DEV-04 | Library/Developer/Xcode/Archives | exactRelativePath | **review** | 不存在 |
| RULE-DEV-05 | Library/Developer/CoreSimulator/Caches | exactRelativePath | candidate | 存在（0 B 空目录） |
| RULE-DEV-06 | Library/Caches/com.bohemiancoding.sketch3 | exactRelativePath | candidate | 不存在（未装 Sketch） |
| RULE-MOB-01 | Pictures/iPod Photo Cache | exactRelativePath | candidate | 不存在 |
| RULE-MOB-02 | Library/iTunes/{iPhone,iPad,iPod} Software Updates/*.ipsw | extensionSet | candidate | ~/Library/iTunes 不存在 |
| RULE-NET-01 | Library/Caches/com.apple.Safari | exactRelativePath | candidate | 目录存在，`ls` 报 Operation not permitted（TCC） |
| RULE-NET-02 | Library/Caches/Google/Chrome/*/Cache | segmentGlob | candidate | 存在（Chrome 缓存 384 MB；仅 Default 档，Default/Cache 存在） |
| RULE-MAIL-01 | Library/Containers/com.apple.mail/Data/Library/Mail Downloads | exactRelativePath | candidate | 目录存在，`ls` 报 Operation not permitted（TCC） |

- 本机不存在的路径照写（其他机器可能有），存在性结果如上入档。
- RULE-DEV-04 为用户工作产物，disposition 用 **review** 而非 candidate；且该路径当前
  被硬保护表 `Archives` 段整体覆盖，decide 落 **protect**（预期休眠，单测固化）。
- **备份保护增强**：`protectionReason` 新增相邻段对匹配（任意深度）——路径含
  `MobileSync/Backup` 相邻段即返回"iOS 设备备份已保护"；仅 `MobileSync` 单独段不触发
  （单测三种形态固化）。本机 `~/Library/Application Support/MobileSync/Backup` 不存在，
  保护段照写。
- RULE-DEV-02 的 `minAge: 604800`（7 天）语义不变；新增 9 条均 `minAge: null`（待准入阶段
  再收紧）。

## 5. DuplicatesPage（App 侧）

- 默认扫描根 `model.scope?.rootPath`（首次进入采纳，用户手动选择后不再覆盖），否则 home；
  NSOpenPanel 目录选择（面板文案声明只读）。
- 「开始扫描/取消」+ 进度（阶段标题、已处理字节/阶段总量确定性进度条、当前路径单行截断）；
  完成统计（组数/名义浪费/扫描规模/未读取项数/部分结果标记）。
- 结果按浪费字节降序；DisclosureGroup 展开组内路径，每行「在 Finder 中显示」
  （`NSWorkspace.activateFileViewerSelecting`）；硬链接组橙色标注（distinctObjects 与提示文案）。
- 「导出 JSON」：桌面优先、临时目录兜底，`createFile(attributes: [.posixPermissions: 0o600])`
  创建即套权限（避免"先写再 chmod"的可读窗口）。
- **只读红线：本页无任何删除/移动入口**，结果不写入计划；底部固定声明
  「分析只读；清理能力将在受控执行开放后提供」。
- 扫描在 `Task.detached(.utility)`；`DuplicatesModel` 为 `@MainActor @Observable`，
  后台仅经进度流回传，启动时在主线程读 scope。

## 6. 测试与验证结果

- `swift build` 全绿。
- `swift test --filter CleanerExtrasTests`：**15 用例全绿**（9 漏斗夹具 + 5 分类器 +
  1 opt-in 冒烟）。夹具关键覆盖：同尺寸同头不同尾（第 600 字节差异）必须被全量哈希分开；
  同尺寸头不同第三段淘汰；`<minBytes` 不扫；权限拒绝（chmod 000）→ skipped 且
  内容相同也不得成组；硬链接组标注（distinctObjects=2、nlink=2）；符号链接与
  .git/.svn 内部不收集（含符号链接目录环）；进度阶段序 `[枚举, 头哈希, 全量确认]` 与
  收尾事件组数；立即取消返回 incomplete 且流正常收尾；根缺失/非目录 incomplete；
  64 位字段字符串编码 + 篡改为数值型解码拒绝；浪费降序确定性排序。
- `swift test --filter CleanerCoreTests`：**11 用例全绿**，含：
  - `seedRulesAreStrictAndBadRevisionKeepsPrevious`：数量断言更新为 13（原 4）并注明
    T4 扩充构成；坏 schema/坏 matcher/坏 roots 仍严格拒绝且保留旧规则集。
  - `t4SeedRulesDecideAndMobileSyncProtection`：9 条新规则加载即严格校验、全
    previewOnly；decide 对 6 条 exactRelativePath 代表路径给出 candidate+规则 ID；
    DEV-04 落 protect（硬保护覆盖）；NET-02/MOB-02 休眠回落 review（segmentGlob/
    extensionSet 引擎语义未实现，fail-closed 不产生候选）；MobileSync/Backup 保护
    在普通前缀与 `/System/Volumes/Data` 前缀下均生效、单独 MobileSync 段不触发。
- App 编译：`xcodebuild -scheme LocalMacCleaner -configuration Debug` **BUILD SUCCEEDED**。
- **真机冒烟**（`LMC_DUP_REAL_ROOT=~/Downloads`，默认 1 MiB 阈值）：379 个文件 /
  3.06 GB / **44 组重复 / 名义浪费 139.9 MB / 0 skipped / 0.82 s**；不变量断言
  （每组 ≥2 文件、组内尺寸一致、浪费合计可对账）全过。

## 7. 遗留问题与已知取舍

1. **segmentGlob/extensionSet 匹配语义未进 decide**：RULE-NET-02/RULE-MOB-02 已登记
   （matcher 字段合法、加载通过）但引擎只做 exactRelativePath 前缀匹配，二者休眠回落
   noRule=review（规则 reason 与测试均已注明）。语义实现留给后续准入阶段，本任务不扩
   decide 逻辑（边界约束）。
2. **TCC 目录只能登记不能枚举**：Safari 缓存与 Mail Downloads 在无完全磁盘访问时
   `ls` 即 Operation not permitted；规则照写（规则 reason 已注明），实际清理动作开放前
   需用户授权 FDA，分析阶段不绕过。
3. **硬链接组名义浪费是上界**：真实可释放取决于 distinctObjects；UI 以橙色标注而不是
   改写合计口径，避免与全库"名义浪费"总计失去可对账性。
4. **同名不同 inode 的克隆文件（APFS clonefile）**：字节相同会正常判重；clone 的共享
   块使真实释放小于名义值，当前无法在不深挖 APFS 元数据的前提下区分，导出字段已保留
   dev/ino/nlink 供后续增强。
5. App 侧无独立单元测试（App target 不在 SwiftPM 测试图内）；`DuplicatesModel` 逻辑
   以冒烟 + 手工验收覆盖：选目录→扫描→取消→重扫→展开组→Finder 显示→导出后核对
   `ls -l` 为 0600。
6. 枚举 `options: []` 不跳隐藏文件与包内容（dup 分析需要看包内大文件）；依赖 lstat
   过滤符号链接与非常规文件，已在夹具中用符号链接目录环验证不死循环。
7. `RULE-DEV-04` 与硬保护表 `Archives` 段当前重叠：规则登记为 review 供未来"保护表
   收窄 + 规则接管"的迁移路径，现阶段不产生候选即不构成冲突。
