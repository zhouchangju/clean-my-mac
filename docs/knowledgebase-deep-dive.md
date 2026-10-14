# CleanMyMac 随包知识库：第二轮深查

2026-10-12，目标 `/Applications/CleanMyMac_5.app` 5.7.1。上一轮未知的两个 `.cmmkb` 已完成离线解码：**291 + 2 页全部 HMAC 校验通过，SQLite 只读 integrity_check 都为 ok，源文件 hash 未变。** 这是随安装包规则库，不是用户运行后可能已更新的数据库；也不是对实际清理行为的验收。

本专题的静态分析没有启动/注入 CleanMyMac，没有读取用户运行库、Keychain、授权账户或个人文件，没有运行清理；主线程另做的界面观察未取得扫描结果。这里只使用现有 Python/Crypto/cryptography（独立复核）、LLVM 和 REA/Ghidra。解码副本、派生材料与源证据仅留 `.local`；解码库和内置派生材料设为 0600，不进入文档或版本化产物。

## 一、结果与边界

| 问题 | 结果 |
|---|---|
| 文件格式 | 已证实为与 SQLCipher 3 默认参数兼容的逐页加密 SQLite：1024 字节页、48 字节保留区、PBKDF2-HMAC-SHA1 64000 次、AES-256-CBC、逐页 HMAC-SHA1 |
| 来源绑定 | 两个源资源 SHA-256 与首轮完全相同；前后重新取 hash 一致 |
| schema / 数量 | 已直接查询真实表结构与行数，见下表 |
| 规则含义 | 通过 Swift 枚举 metadata 与 rawValue 查表恢复 7 个 ScanItemType、49 个 ScannerID |
| 有代表的保护规则 | 已读取少量随包记录与维护注释，可解释为何某些缓存不能清理 |
| 完整匹配优先级 | 未完成：同路径多规则命中时顺序、全局作用域 sentinel 的执行语义、正则边界与缓存失效尚待调用链追踪 |
| 全部有效清理规则 | 未宣称恢复：表行包括忽略、保护、深搜、资源关系，不等于可删除项数量；不少扫描策略在代码中 |

## 二、入口与证据链

### 1. framework 的兼容配置是真正执行逻辑

KnowledgeBaseService arm64 SHA-256：`a57ee544295b3719449e3a76c60994c4ae7e63aa5a111151d90a70ded327ec46`。

REA/Ghidra 的 `KnowledgeBaseCipherCompatibility.apply` @ `0x4770` 对应：`FMDatabase initWithPath:nil` → `open` → 成功时执行 `PRAGMA cipher_default_compatibility = 3` → `close`。LLVM 汇编补齐 Objective-C selector，避免把 Ghidra 未识别的 stub 名称误当算法。

- 伪代码：`.local/evidence/round2-kb/04-procedure_pseudo_code.json`
- Evidence：`ev_d49779b247bd60b59dac0bb8494293dd477a324b0a0f3dc932747572157d3088`
- 反汇编：`kb.disasm.txt`，`0x4770..0x47e4`

`KnowledgeBaseServiceInstance.configure` @ `0x7af0` 调用注入的配置 closure；`KnowledgeBaseScannerService.isPathIgnored` @ `0x4d6c`、`additionalFiles` @ `0x5358` 调用协议 witness slot。这解释为何只读 framework 字符串无法得到数据库的实际查询实现。

- configure Evidence：`ev_6ad40e85c196401a3a6be3d1c1a56094b06bda93da315fc9b3e55babaecd5f58`
- 对应完整返回：`07/08/09-procedure_pseudo_code.json`

### 2. 实际读取器位于主 executable

主 executable 的 arm64 SHA-256：`5c843764f23d240317fe253a85a3d4d39d666947bd6627533ecd068e5ff830bc`。

LLVM Objective-C 元数据定位 `FMEncryptedDatabase : FMDatabase`。其 `open` @ `0x100196c9c`：

1. 调用父类 open，失败返回 false。
2. 成功后调用 `0x100196fa0`，得到内置 Data。
3. 将 Data 转为 NSData，调用 `setKeyWithData:`，返回该调用状态。

`setKeyWithData:` 的 stub 位于 `0x100392980`。Data 路径经由动态解析出的 `FMTextStrings` 方法；方法主体 `0x10019769c`。本轮对这段随包编码做了确定性离线重构，不进行口令猜测或枚举，也不执行目标应用。具体内置材料不在此复述。

源证据：`main.objc.txt`、`main-target-disasm.txt`、受限本地 `*derive*.local.txt`；源 binary 与切片身份见 `main-artifact.json`。

主 executable 的 REA/Ghidra 伪代码请求因默认分析超过 330 秒返回 `provider_timeout`，并已关闭；**不能说主 executable 已经由 Ghidra 成功反编译**。该部分结论来自 LLVM 静态控制流，以及独立数据校验。framework 的 REA 会话成功并已关闭，快照 `kb-snapshot.json`；主会话关闭记录 `14-close_binary.json`。

### 3. 解析与验证

格式参数参照 [SQLCipher 官方 API 的 3.x 兼容示例](https://www.zetetic.net/sqlcipher/sqlcipher-api/#sqlcipher_export) 和 [SQLCipher 设计说明](https://www.zetetic.net/sqlcipher/design/)。固定应用内派生材料后，仅尝试与其 compatibility=3 配置一致的参数；全部页校验通过后才解析 SQLite。没有安装 SQLCipher、复制库到版本化目录或修改源文件。

- info.cmmkb：源 `07d88f0ccfb730503b12dc0113bb5a56beb070f47d4bf065b01e0348c92ce7a0`，291 页全部 HMAC 通过；解码 hash `ec3f8526f017ba800d91faf8501bab91a80959d2f3185a4f18cbb0ba39312b08`。
- userInfo.cmmkb：源 `50def301e685ae2e3c06d9db67bfcf9e5e6bd22aad64ae95d89ad730f4e6e467`，2 页全部 HMAC 通过；解码 hash `d974ce6be70583ef0ace548d35127eb7ef8e2ebadcea5f948783bd6cfa552f3b`。

查询采用 `mode=ro&immutable=1`，后续统一设置 `PRAGMA query_only=1`。verification 脚本重新解码全部页面，并在查询之前显式验证 freshly decoded bytes 与待查询副本逐字节相同；错误必须抛异常。

初次验证以普通 Python 正常运行通过。独立审查发现首版 verifier 用 assert，在 `python -O` 下会关闭校验；已全部改成显式异常，并正常/优化模式重新通过。审查者进一步以独立 cryptography AES 实现逐页验证、确认错误页号端序失败，以及 `-O` 错误源 hash/错误材料都被拒绝。原始成功证据与修复后复验分开保存：`database-verification-schema.json`、`verification-rerun.json`、`verification-optimized-rerun.json`；独立复核输出在 `.local/evidence/round2-kb-review/`。

## 三、真实 schema 和原表行数

随包 General 中版本为 `1.1.52.202605201253`。不能用它代替用户 runtime 已更新规则库版本。

| 表 | 原表行数 | 字段/作用 |
|---|---:|---|
| General | 1 | Key, Value；Version |
| GroupType | 26 | Type 主键, PrefixPath, Description；路径前缀分类 |
| ApplicationInfo | 990 | RecordID, Name, BundleID, Type；应用身份 |
| ApplicationFiles | 1,912 | RecordID, Value, FileType, GroupType, Owner, IsRegex；应用关联资源 |
| ScanItems | 1,509 | RecordID, Value, ItemType, ScannerID, GroupType, IsRegex；保护/忽略/深搜等控制数据 |
| RecordInfo | 1,509 | RecordID, Value；维护注释 |
| UserIgnore（userInfo） | 0 | Value, CategoryType, ValueType, ScannerID, Title；随包空用户忽略模板 |

还有 SQLite 内部 sqlite_sequence 的 3 行，不计为产品规则。这些是表行数，**不可将 1,912 与 1,509 相加称为“恢复了 3,421 条可用清理规则”**。它们可能有重复匹配、多扫描器作用域、兼容旧数据、无效引用，也不是所有扫描模块策略的完整总量。

### 导入陷阱已实证

1. `IsRegex BOOLEAN` 的实际存储类型全部为 TEXT：ApplicationFiles 的 `false=1739/true=173`；ScanItems 的 `false=1282/true=227`。自研导入必须显式解析字符串；`bool("false")` 为 true，不能使用这种转换。
2. 外键声明引用 `GroupType(RecordId)`，但真实主键叫 `Type`。`PRAGMA foreign_key_check` 报 foreign key mismatch。`integrity_check=ok` 只证明 SQLite 结构一致性，不能扩大成所有引用与业务语义正确。
3. 按实际 `GroupType.Type` 做只读 join：ScanItems 无找不到分组的行；ApplicationFiles 有 4 行 GroupType=22，在 GroupType 表不存在；Owner→ApplicationInfo.RecordID 无孤儿。不得推断运行时一定错误，代码可能有兜底；也不得盲目导入。

详见 `schema-caveats.json`、`typed-rule-samples.json`。

## 四、枚举数值与规则分类

主 binary 的 `ScanItemType` type descriptor @ file offset `0x434ca0`、field descriptor @ `0x4594ac`，字段顺序与 `0x1001a86c0` rawValue lookup、表 `0x1003b6128` 结合，恢复以下映射。对应 metadata accessor @ `0x1001a8848`；此为静态类型映射，非扫描执行观测；证据 `scan-item-type-mapping.json`、`scan-item-type.disasm.txt`。

| ItemType | case 名 | 原表行数 | 已证实的分类含义 |
|---:|---|---:|---|
| 2 | protectedBundleID | 259 | 保护应用 Bundle ID |
| 3 | ignored | 931 | 忽略项 |
| 5 | deepScan | 7 | 需要深入扫描的项 |
| 6 | system | 262 | 系统项分类/保护依据 |
| 9 | excludeTop | 22 | 顶层排除类别；是否仅排除父节点而仍遍历子项尚待调用链核对 |
| 13 | aggressorAppBundleID | 26 | aggressor 应用匹配类别；不能解释成恶意软件名单 |
| 14 | aggressorAppIgnoredBundleID | 2 | aggressor 的忽略应用类别 |

KnowledgeBaseService 的 ScannerID.rawValue @ `0x813c` 对单字节 ordinal 查表 `0xa698`，结合 `__swift5_fieldmd` 恢复 49 个 case。相关值：allApplications=2、leftoversApps=3、systemCaches=9、userCaches=10、largeAndOldFiles=24、systemLogs=26、userLogs=27、derivedData=61、fileVersions=73、fileManager=80、xcodeCaches=83、aggressorApps=84、duplicates=101、aiJunkFiles=102、aiLocalModels=103。完整表在 `scanner-id-mapping.json`。

数据库还有 ScannerID=`9223372036854775807`，该值不是上述 ScannerID 枚举 case；看起来是跨扫描器 sentinel，但当前未完整追到组合过滤函数，保留“作用域语义待确认”，不擅自等同所有扫描器。

## 五、少量代表规则：保护比删除清单更关键

下面是随包记录，不能直接转成删除命令。维护注释仅反映库内说明，本轮没有通过删除重现其中的崩溃、会话或授权后果。路径只表达规则数据中 GroupType 前缀与 Value 的关系；实际规范化、符号链接、正则匹配范围还要核对。

| RecordID | 类型/作用域 | 数据与维护理由 |
|---:|---|---|
| 1507 | ignored / userCaches(10)，GroupType=10，regex=true | `^company\.thebrowser\.Browser(?:/.*)?$`，前缀 `~/Library/Caches/`；注释说明移除 Arc 缓存可能破坏运行中的网页会话与 DRM 状态 |
| 1508 | 同上 | `^SentryCrash/Arc(?:/.*)?$`，同样保护 Arc 相关缓存 |
| 1509 | ignored / userCaches(10)，GroupType=10 | `com.meitu.yunxiupro7`；注释说明包含预处理图像数据，删除可能导致崩溃与专业摄影流程中断 |
| 1455 | ignored / userCaches(10)，GroupType=0，regex=true | Native Instruments 在 `/private/var/folders/` 中的匹配路径；注释说明删除会导致授权信息丢失；没有读取任何用户授权内容 |
| 1481 | system / leftoversApps(3)，GroupType=13 | `Contacts` 对应 `~/Library/Contacts`；注释说明保存通讯录数据 |
| 1480 | system / leftoversApps(3)，GroupType=18 | `Calendars`；注释说明系统管理的 Calendar 数据，不能因应用归属识别不出就当残留 |
| 258 | protectedBundleID / allApplications(2) | `com.apple.Photos` |
| 893 | deepScan / userCaches(10) | `com.spotify.client`；资源名需要继续深入，不足以宣称整目录应删除 |
| 891 | deepScan / userCaches(10)，regex=true | `^Google$`；说明缓存扫描可能根据知识库控制遍历深度 |
| 1167 | excludeTop / allApplications(2)，GroupType=7 | `Audio/Plug-Ins/VST3`；精确 traversal 效果仍待确认 |

ApplicationFiles 示例中，Chrome 的 bundleID 关联到 cache、preferences、LaunchAgents 等不同 GroupType；Xcode 关联 Developer/Xcode 与 Developer/CoreSimulator。**卸载资源关联不等于缓存清理授权**，不可把此表全部作为日常垃圾清单。

## 六、对自研软件的直接价值

- 第一版规则模型需要 actionKind：protect、ignore、descend、appAssociation、cleanupCandidate 各有语义，禁止一个“路径命中即可删”的规则列表。
- 将缓存视为可疑占用而非天然垃圾。可重建性、运行应用状态、用户工作流与保护例外都需要证据；Arc、音乐插件与专业图像软件是可做回归 fixture 的真实反例。
- 规则携带版本、来源、理由、scanner scope、匹配方式、路径前缀；导入严格校验类型和外键，未知字段/分组保持禁用。
- 可直接设计只读扫描结果解释：“为什么发现 / 为什么保护 / 为什么需展开 / 属于哪个应用”，再做用户选择与执行阶段复查。
- 不把随包专有库作为自研产品可直接发布的规则资产；用于理解机制、构造独立规则与测试样例。当前未完成规则分发、版本签名、冲突优先级、执行前竞态与恢复验证。

## 七、尚未回答的问题

1. `ignored/system/protectedBundleID/excludeTop` 同时命中时，实际先后与短路策略。
2. literal 规则做绝对路径相等、前缀匹配还是目录包含；正则是否自动拼接/转义 prefix、大小写与 Unicode normalization 的设置。
3. `ScannerID=Int.max` 与单个/多个 scanner group 的匹配集合；GroupType=22 的 fallback。
4. working/backup 知识库升级、校验签名、出错回滚的完整控制流。
5. appFiles 的 FileType=0/1、ApplicationInfo.Type=0/2/5 的精确枚举含义，本轮保持原始值。
6. 用户实际运行库版本与忽略配置；未读取是本轮明确边界。

因此，**本轮完成了随包知识库格式、真实数据结构、行数与主要类型映射，尚未完成整个规则引擎的行为复现。**
