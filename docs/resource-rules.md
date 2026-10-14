# CleanMyMac 5.7.1：随包资源与规则模型

> 历史阶段说明：本文保留首轮观察。第二轮已成功解码两个随包 `.cmmkb`，下文“尚未解出”描述的是首轮状态；最新结构、行数和校验见 [知识库深挖](knowledgebase-deep-dive.md)。产品文案与执行证据的区分仍适用。

调查日期：2026-10-12。目标 `/Applications/CleanMyMac_5.app`。本报告只读检查应用包，不读取用户运行数据库，不启动扫描或删除。没有复制完整应用或知识库；本地产物是资源清单、hash、格式探测结果和相关文案/metadata。

## 结论与完成边界

已确认其能力划分、若干保护交互，以及“按应用/路径/正则/扫描器分类”的知识库模型。**尚未解出 `.cmmkb` 数据库，因此不能宣称拿到了完整清理规则表、保护路径清单、默认勾选策略或执行算法。** 文案证明产品声明，metadata 证明模型存在；二者均不证明每条逻辑实际运行。

未来自研可直接借鉴的是：扫描结果必须携带类别、归属应用、风险与推荐理由；缓存、用户文件、备份、应用内部代码、远端文件应分别处理。下面“自研映射”均是独立设计建议，不是 CleanMyMac 已实测行为。

## 证据目录

这些是本地静态证据编号，不是 REA 服务生成的 Evidence ID。

| 编号 | 产物 | 内容 |
|---|---|---|
| RES-01 | `.local/evidence/resources/resource-inventory.json` | 349 个匹配数据扩展名的随包资源，精确相对路径、字节数、SHA-256；不是所有媒体资源清单 |
| RES-02 | `.local/evidence/resources/cmmkb-format-probes.json` | 两个知识库文件的头、长度、熵、只读 SQLite 及常见压缩探测 |
| RES-03 | `.local/evidence/resources/module-localizations-full.json` | 6 个相关模块英文 Localizable.strings 的完整解析，包含精确来源及 hash |
| RES-04 | `.local/evidence/resources/cleaning-localizations.json` | 去除 Versions/Current 重复后的相关英文资源筛选，共 557 条；40 个英文 strings 文件被检查 |
| RES-05 | `.local/evidence/resources/KnowledgeBaseService.strings.txt` | KnowledgeBaseService 的静态 printable strings |
| RES-06 | `.local/evidence/resources/knowledgebase-metadata-offsets.json` | 知识库关键 metadata 字符串的文件偏移、源文件 hash |

资源读取用 `plutil -convert json -o - <path>`；字符串用 `strings -a <binary>`；数据格式用 Python 标准库，SQLite 显式 `mode=ro`。没有安装解密依赖。

## 1. `.cmmkb` 格式

| 文件（Contents/Resources） | 字节 | SHA-256 |
|---|---:|---|
| info.cmmkb | 297,984 | `07d88f0ccfb730503b12dc0113bb5a56beb070f47d4bf065b01e0348c92ce7a0` |
| userInfo.cmmkb | 2,048 | `50def301e685ae2e3c06d9db67bfcf9e5e6bd22aad64ae95d89ad730f4e6e467` |

**观察（RES-01/02）**：文件没有 SQLite 明文头，均为 1024 字节整数倍。字节熵分别约 7.9994 和 7.8970 bits/byte。普通 SQLite 报 `file is not a database`；gzip/zlib/bzip2/xz-lzma 解码失败。Menu 与 HealthMonitor 各自 Resources 中的两个同名文件，与主应用逐字节 hash 一致。随包 `userInfo.cmmkb` 是发布时模板/初始数据候选，不能当作用户实际忽略配置。

**观察（RES-05/06）**：`Contents/Frameworks/KnowledgeBaseService.framework/Versions/A/KnowledgeBaseService` 含 `PRAGMA cipher_default_compatibility = 3`，以及 `initWithPath:`、`open`、`executeStatements:`、`close`。源 binary SHA-256 为 `f7eb96fe050f6ee598a3220316ac4418cb19043ff0a58aae93767dee6b51c178`。应用包另含 SQLCipher.framework。

**推断**：SQLCipher compatibility 3 是强候选；高熵和块对齐本身不能证明加密算法，也不能证明两个文件使用相同 key、page size、schema。当前没有密钥/连接调用路径验证与成功打开结果，不报告“已解密”。

## 2. 知识库模型：能看到哪些规则维度

以下来自 KnowledgeBaseService 的 Swift 反射 metadata/字符串（RES-05/06）。类型和字段名可观察，字段用途需与实际调用链核对。

| 类型 | 随包可见字段/枚举 | 可支持的机制推断 |
|---|---|---|
| AppResource | path、value、isRegex、groupType | 资源不只靠目录大小判断，允许模式匹配与分组 |
| AppInfo | bundleID、bundleURL、name、items | 以应用身份组织关联资源 |
| CustomIgnoreItem | value、categoryType、valueType、scannerID、title | 忽略项存在类型和扫描器作用域 |
| CustomIgnoreItemsSnapshot / CustomIgnoreItemsSnapshotsStorage | 类型名；userIgnoreListUpdatedNotificationName | 忽略列表有快照/变更传播机制候选 |
| KnowledgeBaseConfig | workingURL、backupURL、writeScanners、readScanners | 工作/备份知识库与读写扫描器分工候选 |

GroupType 包括 `appSupport`、`userAppSupport`、`homeDirHiddenFiles`、`launchAgents`、`userLaunchAgents`、`launchDaemons`、`userLaunchDaemons`、`library`、`userLibrary`、`userLibrary2`、`preferences`、`userPreferences`、`userCaches`、`systemLogs`、`userLogs`、`tempFiles`、`package`、`packageRegex`、`extensions`、`systemExtensions`、`sandboxContainers`、`groupContainers`、`privilegedHelperTools`，以及 app 自身日志类别。这是分类词表，不是允许删除这些目录的授权。

忽略值相关枚举有 `language`、`applicationLanguage`、`application`、`leftover`、`mail`、`mailAttachment`、`malware`、`applicationAccount`、`backupDevice`、`brokenStartupItem`、`simulator`、`other`。确切归属及序列化值尚未追踪。

ScannerID 列举 `systemCaches`、`userCaches`、`systemLogs`、`userLogs`、`brokenPrefs`、`brokenStartupItems`、`appLanguages`、`universalBinaries`、`iOSBackups`、`iOSSoftwareUpdates`、`mailAttachments`、`mailTrashes`、`derivedData`、`xcodeCaches`、`fileVersions`、`deletedUsers`、`leftoversApps`、`unusedDiskImages`、`downloads`、`largeAndOldFiles`、`duplicates`、`similarImages`、`aiJunkFiles`、`aiLocalModels` 等。类型存在不等于每个平台/许可证/配置下都启用。

**自研映射**：可定义 Rule(id, scannerKind, roots, appIdentity, predicate, exclusions, risk, recoverability, enabledByDefault, reason)。IgnoreEntry 应有精确路径/应用/类别作用域，而不是简单 basename 黑名单；落盘 schema 和规则版本独立。不要复制知识库中未验证的未知二进制内容作为自研规则源。

## 3. 可恢复的产品规则与安全交互

来源均为 RES-03，对应 `Contents/Frameworks/<模块>.framework/Versions/A/Resources/en.lproj/Localizable.strings` 的精确 key。下表“观察”是随包声明，算法仍需代码/运行证据。

| 范围 | 观察与精确 key | 自研映射 |
|---|---|---|
| 用户/系统缓存、日志 | JunkCleanupModule：`system_junk_user_cache_group_title`、`system_junk_system_cache_group_title`、`system_junk_user_logs_group_title`、`system_junk_system_logs_group_title` | 分开统计归属、权限、可重建性；扫描候选不等于全目录递归删除 |
| Xcode | `system_junk_xcode_junk_group_description`、`system_junk_xcode_caches_title`、`system_junk_xcode_device_logs_title`；文案提及 intermediate build information / project index / Derived Data | DerivedData、缓存、设备日志单独规则；告知重建索引/重新编译代价；保留源码/archives，不从“开发垃圾”笼统推断 |
| AI 工具 | `ai_clutter_agents_junk_group_description`：Claude、Codex、Gemini、Cursor 的 caches/logs/temp；`ai_clutter_local_models_group_description`：Ollama、LM Studio 模型 | 清理会话/配置与缓存必须分离；模型列精确位置/大小/用途，再由用户选择 |
| 模型删除 | `ai_clutter_local_model_alert_message`：模型可能仍被项目使用，删除后需重新下载，否则可能报错 | 模型默认未选，单独确认，不宣称“垃圾” |
| iOS 备份 | `system_junk_ios_backup_latest_badge_label`、`system_junk_ios_backup_latest_alert_message`：选择包含设备最新备份会警告无法恢复到当前状态 | 按 device 分组，识别每组 latest，显式二次确认；保留恢复价值说明 |
| 邮件附件 | `mail_attachments_category_description`：移除 recoverable attachments，保留已修改附件；`custom_flow_mailAttachments_description` 同样表达 modified protection | 只有验证远端可恢复、未修改的副本才可候选；当前没有附件校验算法，MVP 不自动执行 |
| 已删除用户目录 | `system_junk_deleted_users_group_description`：可能不是 waste，值得 review | 默认未选，逐路径检查；不得因所属账户不存在就删除 home |
| Trash | `trash_bins_mounted_trash_group_description`、`trash_bins_mail_trash_group_description`、`trash_bins_root_volume_trash_group_description`：挂载卷、Mail、主卷分别处理 | Trash 清空是永久动作，单独显示；外置盘空间不得计入内置盘实际收益 |
| 文档历史 | `system_junk_document_versions_group_description`：过时 revisions | 数据恢复价值高，MVP 仅发现/解释，不自动清除 |
| 本地化/Universal Binary | `system_junk_language_files_group_description`、`system_junk_universal_binaries_group_description` | 会改动已签名 app 内容，自研初版不做；不能把节省空间文案当作签名/升级兼容证明 |
| 残留 | ApplicationsModule：`leftovers_group_description`、`leftovers_category_description`：应用已不在但偏好/配置等关联资源仍在 | bundleID、receipt、container 等多信号归属，处理多 app 共享资源；匹配不确定时只报告 |
| 未用应用 | `uninstaller_filter_toolTip_unused`、`uninstaller_category_description_unused_apps`：超过 6 个月未打开 | 报告 last-used 来源和缺失值；6 个月可作候选筛选，不能成为自动删除条件 |
| 系统应用/插件 | `protected_system_application_info`、`protected_plugin_info`：系统 app 不可移除，受保护路径插件不可移除 | 保护规则优先于清理规则，系统 app 无删除入口；“reset app”另设危险操作，不并入缓存 |
| 云端独占文件 | SpaceLensModule：`spacelens_cloud_evicted_protection_reason`：cloud-only 项应转 Cloud Cleanup | local allocated bytes 与 logical size 分开；云文件删除可能同步到远端，MVP 拒绝自动删除 |
| 忽略 | ModuleCore：`Ignore_Action_Tile_Format`、`data_manager_ignored_items_title`、`data_manager_ignored_items_undo_action_title` | 可持久忽略并撤销，之后扫描隐藏/标记原因，明确是撤销忽略而非恢复已删除文件 |

## 4. 大文件、旧文件、重复文件

OrganizeModule 的 `laof_filter_group_by_size`、`laof_filter_group_by_kind`、`laof_filter_group_by_access_date` 提供尺寸/类型/访问时间三种视角。`laof_filter_by_access_date_*` 明确包含不足一周、一周前、一月前、六个月前、一年前。`tile_laof_data_manager_description` 引导查看一年未打开的大文件。尺寸文案只有 megabytes / hundreds of megabytes to a gigabyte / gigabytes；**不能据此给出精确字节阈值或区间开闭关系**。也无法只凭 “last opened” 判断实际用了 POSIX atime、Spotlight kMDItemLastUsedDate 还是应用自有时间。

重复文件类别文案称 identical copies，类型筛选含图片、音频、视频、文档、应用、归档等。`selection_alerter_informative_text` 表明“全选一组”会移除所有实例，配合确认按钮；这说明 UI 考虑“连最后一份也删除”的风险。当前资源无法证明 hash 算法、是否比较内容、hardlink/APFS clone 去重、原件保留算法。

自研建议：先按大小分桶，再 hash/逐字节确认；对 inode/hardlink/clone 单独核算，不将多路径逻辑总大小称为可回收物理空间；默认至少保留一份，允许用户明确选择后再永久清除。旧文件只是 review 信号，不是垃圾判据。原始扫描候选与当前选择集合分开计算。

## 5. Purgeable 与 Time Machine

PerformanceModule 的 `free_up_purgeable_space_description` 声明 purgeable 可包含缓存、临时数据、可下载/可重建内容；`thin_local_snapshots_description` / `custom_flow_timeMachineSnapshot_description` 声明 thinning local snapshots。SpaceLensModule 的 `spacelens_results_purgeable_space_tooltip_text` 把该类别导向 Performance。

当前未验证其命令、目标容量、优先级、失败回退。自研必须把 purgeable 标为 macOS 的可回收估计，不与普通候选大小直接相加；快照 thinning 独立功能，保留前后空间实测与操作记录。资源中关于“无数据损失”等营销措辞不构成本机恢复可用性的验证。

## 6. 下一阶段必须补齐的证据

1. 知识库实际打开与 schema：表、有效规则数量、匹配顺序、白名单/排除路径、规则更新与签名校验。当前部分回答。
2. “安全清理”默认选择算法：类别风险、修改时间阈值、运行中 app 排除、文件锁、共享容器、系统保护。当前仅保护文案/metadata。
3. 删除执行链：Trash 还是 unlink、递归/符号链接防越界、扫描后替换的竞态、权限 helper、每项失败回执。资源无法回答。
4. 邮件 modified/recoverable、iOS 最新备份判定、重复文件判等、大旧文件 last-used 的实际数据源。当前仅产品声明。
5. 空间收益：logical/allocated、hardlink/clone、压缩、快照与外置盘如何避免重复计算。资源无法回答。

上述缺口不阻止先做只读扫描 MVP，但阻止声称已经独立复现 CleanMyMac 全部清理安全机制。
