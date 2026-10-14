# 第二轮：默认选择、设备备份与保护谓词

2026-10-12，CleanMyMac 5.7.1 / build 50701.0.2609301754。目标包身份与上一轮一致。本轮对 SystemJunkScanning arm64 切片新增 **16 个 REA/Ghidra 函数查询**，并以原始 arm64 汇编校验关键布尔值与回调参数。没有运行扫描或删除用户备份。

原 framework SHA-256：`408f7c54625e60473755bde876ee15da64a261bab3b5334d81abf6926a286295`；分析切片 SHA-256：`e8394daa5f50555ded0b003575ce0563102cafd2bd2572f07e7112d4d88f3f63`。证据在 `.local/evidence/round2-selection/`，RPC 文件的 `result.structuredContent` 是 REA Evidence；`index.json` 列出查询、Evidence ID 和限制，`*.pseudo.c` 为方便阅读而导出的伪代码，不是源码。

## 1. 默认选择有类别例外

| 位置 | 反编译与汇编一致的结果 | 边界 |
|---|---|---|
| `CMCacheScanTask.isResultAutoselectable @0x7130` | 返回 true；汇编 `mov w0,#1; ret` | 缓存扫描基类的结果初始策略 |
| `CMGradleCacheScanTask.isResultAutoselectable @0xb6a0` | 返回 false；汇编 `mov w0,#0; ret` | Gradle 子类明确覆盖基类策略 |
| `CMGradleCacheScanTask.taskWith… @0xb5e0` | 通过 `CMPaths.gradleCaches` 构造扫描任务 | 此函数未展开 CMPaths，不能仅由名字报告全部真实路径 |

与第一轮 `0x69fc` 和 `0x6c2c` 对照，这个值确实传给结果模型的 `autoselected` 字段，已经超出“有一个同名属性”的证据强度。它仍不等于界面最终勾选：后续用户忽略、模型转换或 UI 状态可能覆盖，尚未追完。

自研启示：`可扫描`、`可重建`、`默认选中`需要独立建模；不能因为同属缓存就一键全部选中。Gradle 例外的设计动机没有从代码得到证明，不把猜测写成原产品原因。

## 2. 设备备份的选择链已恢复

### 发现与过滤

`CMMobileBackupsTask.backupURLs @0x1362c` 对配置的 `backupsBaseURL` 枚举子项。主 `scan @0x13684` 先检查取消，按每个 URL 的 `lastPathComponent` 查询 KB ignore（回调 `0x13df4`），再处理各备份的 `Info.plist`。

读取的字段包括 `Device Name` 和 `Product Type`。有设备名的项创建 `CMMobileBackupDevice`，并受 `isIgnoreItem(device.uniqueID)`、`shouldIgnoreDeviceID` 两层检查，再按设备对象组织候选。缺少有效设备名的项走独立的 BrokenBackups 分支：须同时不命中 `isIgnoreItem("BrokenBackups")` 与 `shouldIgnoreBrokenBackups`，才进入候选集合。

这里的“Broken”分类依据是这段代码的元数据结果，不能推广成已验证备份整体不可恢复。

### 时间来源与最新项

`0x1403c` 先读 `Status.plist` 的 `Date`，并检查能否转为 NSDate；不可用时回退到先前 `Info.plist` 的 `Last Backup Date`。`scan` 构造 `NSSortDescriptor(key:"date", ascending:false)`；`0x13e78` 按该描述符排序，再 map 结果。

`0x14194` 明确传参：

```text
autoselected = index != 0
latest       = index == 0
```

因此，在这条正常元数据分支中，**每个排序后分组的首项标为 latest 且不自动选中，其他项自动选中**。不能说最新备份完全不可删除：第一轮资源文案有额外确认，用户仍可能显式选择。

为避免把反编译器的 `param_3` 猜成 index，本轮另外检查 SharedObjcUtils：`-[NSArray cmm_map:] @0x2354` 调用 `enumerateObjectsUsingBlock:`（stub `0x21360`，selector 注释 `0x21364`）；中转 block `0x2448–0x2460` 转发元素、index 与 stop 参数给传入 block。相关 ObjC 元数据、汇编、stub 与文件 hash 在 `SharedObjcUtils.*.txt` / `shared-utils-identity.json`。

### 异常分支与取消

- `0x14370` 对 **BrokenBackups 集合** 构造 `autoselected=true, latest=false`。这是特定异常元数据分支，不是全部备份的默认值。
- 首轮候选循环逐项 pause/cancel。主函数结束时如果已取消，返回 empty compound result；该任务没有保证保留已发现的部分结果。
- 两个日期字段都不存在、日期相同、损坏元数据与部分取消的最终界面表现尚未验证。

### 分组身份的限制

`CMMobileBackupDevice.uniqueID @0x149a0` 使用设备名；productType 非空时按 `"%@, %@"` 拼接。`isEqual: @0x14a70` 比较 `deviceFullName`。

所以这里不能声称已经证明“按硬件 UDID 唯一分组”。同名设备是否在这条路径被合组及实际影响，需要覆盖 `deviceFullName/hash` 全链并用受控样本确认。本报告不据此宣称已发现运行时缺陷。自研设计应优先使用备份元数据中的稳定设备标识，把显示名留作展示。

## 3. 损坏 plist 的判断包含读取保护

`CMBrokenPreferencesScanTask._isPreferenceFileBrokenWithPlistPath: @0x4840` 的入口条件包括：文件存在、文件名不以 `.` 开头、扩展名大小写归一后为 `plist`、路径不含 `.lockfile`、尺寸非零、没有 NSFileImmutable 标记，且任务未取消。

之后尝试打开 CFReadStream，再解析与验证 property list：

- 流未打开，或解析前已取消：返回 false。
- 已打开流但 plist 创建失败：返回 true。
- plist 创建成功：用 `CFPropertyListIsValid` 的结果取反。

Ghidra 在这段 CF 调用上出现寄存器/返回值变量恢复混乱，因此这些条件同时用汇编复核：`0x4a94` 的 open 失败跳向 false，`0x4ac8` 置 0，`0x4b08/0x4b30` 的 null 解析结果置 1，`0x4b24–0x4b28` 对验证结果取反。依据为第一轮 `scanners/SystemJunkScanning.annotated.txt` 的原始指令注释。

结论限于“是否损坏”的谓词；最终候选默认勾选、备份/还原与删除执行尚未串联。自研不应将权限失败统称为损坏，更不应把解析失败直接视为删除授权。

## 4. 语言资源扫描的保护入口

`CMApplicationLanguagesScanTask._shouldScanApplication: @0x2474` 按顺序检查：

1. `isFileProtectedByRootlessAtPath`；
2. app `isRestricted`；
3. KB `isBundleIdIgnored`；
4. KB `isPathIgnored`。

任一保护命中就不扫描。`_shouldIgnoreLanguage: @0x25c4` 直接委托 KB `isLanguageIgnored`。这证明应用与语言两层保护入口存在；尚未证明当前用户语言规则的完整集合，也没有验证资源删除后代码签名与更新兼容性。自研初版继续不实施应用包瘦身。

## 关键 Evidence ID

| 文件 | Evidence ID |
|---|---|
| `0x7130.json` | `ev_402b0351702475d9f17691be51f2ab55204d96a36d581cd8660356d77539605d` |
| `0xb6a0.json` | `ev_8ab10e002c00155a13fb110f9f75d14a7f4e28a19e2920e494c60feeb9718ca0` |
| `0x13684.json` | `ev_8a062be315134d3ab9dbf9f4d52d2e645d77a86914a98e224fff6ecb3c859294` |
| `0x1403c.json` | `ev_7d7f3963a7b8b1b7ac51fe014c9a810327f1a15d3993de27db1f667610902ade` |
| `0x14194.json` | `ev_3fcc751cbc27dfb5df785992573b65159228a82f8809f82c16941949cccb5475` |
| `0x00014370.json` | `ev_0edcea0324c2107744b8a5b7a75ec05e0d3f046aee8a4d4b5798ccafc70327ef` |
| `0x4840.json` | `ev_fd9b318d11aef5390f4f51ca8775ecfb375a49fea24f14e71979bf21796ee952` |
| `0x2474.json` | `ev_4bf5c025433460b12f8f59112c55b819afe111307b7c13744c4fd19cd01a9599` |
| `0x25c4.json` | `ev_5bb32e857539edbda6676535f16fbc3d1a92e489e282cd7e2132dc73c7a834ff` |

两个 REA session 均完成 `close_binary`，分别保留 `snapshot.json` 与 `snapshot2.json` 及 close 回执。本轮结论是静态实现证据；没有证明真实机器上的备份恢复能力、最终 UI 选择或实际清理结果。
