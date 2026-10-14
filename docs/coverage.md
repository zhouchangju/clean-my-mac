# CleanMyMac 逆向调查覆盖台账

更新日期：2026-10-12。本文覆盖前两轮调查。第二轮新增 66 份不同非空函数反编译 Evidence，完成两个随包知识库的 293 页离线解码与独立复验。UI 已观察多个首页与扫描范围设置，但两轮均未跑通扫描，没有清理。

## 目标与边界

用户希望先安装 [REA](https://github.com/morluto/rea)，研究本机 CleanMyMac 的各种存储清理机制、规则及页面交互，为后续自研自用 Mac 清理软件提供依据。本机存储有限，因此研究产物应能转化为可解释、可选择的空间回收能力。

本轮目标为 CleanMyMac 5.7.1，build `50701.0.2609301754`，路径 `/Applications/CleanMyMac_5.app`；版本与安装信息汇总于 [README](../README.md)，实际包身份见 E01、E02。调查不等于实际清理授权；当前台账不声称已有安全可用的自研清理产品。

证据分三层：**观察**（包内容、反汇编/反编译、UI 实测）、**推断**（根据观察推测职责或流程）、**未知**（尚未恢复或验证）。静态方法名、字符串、文案和依赖只证明存在相应材料，不证明运行时执行、精确匹配规则或删除安全性。

## 覆盖矩阵

“确认”仅适用于本行明确写出的窄结论，不代表整个功能已还原。

| 问题 | 当前状态 | 已有证据与结论 | 下一份必要证据 |
|---|---|---|---|
| REA 安装与 Codex 注册 | 确认（配置及独立 MCP 启动） | E03/E04 配置落盘；E11 production-stdio 验证 REA 6.4.0、170 个工具与 binary_session 请求成功 | 已运行聊天的工具热加载能力不能由独立进程测试代替 |
| Native 分析引擎可用性 | 确认（真实目标静态调用） | 首轮 E12–E15 四函数；第二轮 E20–E23 共 66 份不同非空伪代码 Evidence | 主 executable 的一次 Ghidra 超时不计成功；不能推广为完整应用已还原 |
| 目标身份与架构 | 确认 | E01 包清单、E02 签名元数据、E06 主程序 Mach-O：x86_64 与 arm64 双架构 | 保留版本/构建号来源；不把签名元数据读取称为完整信任校验 |
| 模块与扫描组件 | 部分 | E07 留有 23 个目标身份；扫描专题提供函数地址和若干调用链 | 其余入口到结果的调用关系与数据流；详见扫描报告第 8 节 |
| System Junk 分类、具体规则 | 部分（缓存主链静态确认） | E12–E15 支持 ignore、KB 分流、子项细分与有条件提权计量；E07 支持若干硬编码缓存路径 | 完整扫描根、KB 路径/年龄/大小条件、模块默认勾选值 |
| 随包规则库格式、schema 与主要枚举 | 确认（静态数据） | E22/E24：两个库全 293 页 HMAC 通过、独立解码逐字节匹配、只读 integrity ok；7 个 ItemType、49 个 ScannerID 映射 | 业务字段更多枚举及语义；表行不是可删除规则数量 |
| 规则库加载与匹配行为 | 部分 | framework 兼容配置、主程序 FMEncryptedDatabase open/内置材料/setKey 静态链已恢复 | 匹配优先级、Int.max 作用域、GroupType=22 fallback、运行库版本与在线更新 |
| 规则数据关联一致性 | 部分（已知限制） | IsRegex 实存TEXT；FK声明mismatch；按真实Type join有4条AppFiles分组无对应项 | 原程序如何处理异常关联；禁止把integrity ok扩大为业务语义正确 |
| AI 工具缓存 | 部分 | E07 有 catalog 路径引用与活动版本保护类型 | catalog实际构造、当前版本解析失败处理及完整选择策略 |
| Ollama / LM Studio 模型计划 | 部分（关键静态算法） | E21 确认引用表失败关闭、blob双计数过滤、计划独立计量、GGUF分片集合/8字节头检查 | UI选择到rows输入及执行器、跨组联合回收、自定义路径/使用中检测、实际删除 |
| 默认选择与设备备份 | 部分（关键静态算法） | E20：缓存基类true、Gradle覆盖false；正常备份按日期降序首项不自动选；BrokenBackups分支自动选；取消可返回空结果 | 最终UI状态、日期缺失/同值、设备稳定身份与恢复能力；不可宣称按硬件UDID分组 |
| 损坏plist/应用语言保护 | 部分（静态谓词） | E20 恢复文件/锁/不可变/流/取消门槛、plist解析判定及rootless/restricted/KB排除 | 候选到最终删除链、错误恢复与签名兼容；谓词非删除授权 |
| Mail Attachments / Trash Bins | 部分 | E10 首页存在两类入口；E08 有相关文案 | 实际扫描根、账户/卷处理、过滤与保留条件 |
| 应用卸载与残留识别 | 部分（模型/声明） | 资源报告有 AppInfo/AppResource 分类与未用应用 6 个月文案；没有还原关联算法 | bundle ID 到容器/偏好/共享资源关系及误删防护 |
| 大旧文件、重复/相似内容 | 部分（声明/定位） | 资源报告有时间/类型筛选和全选重复组警告文案；扫描报告定位 ignore 维度 | 精确阈值、时间数据源、内容判等/相似算法、保留规则 |
| Space Lens 容量统计 | 部分 | E10 存在入口，E07 有 SpaceLensScanning 材料 | 逻辑/分配大小口径、硬链接/APFS/云占位符处理与重算 |
| Cloud Cleanup | 未知 | E10 仅证明入口存在 | 远端与本地作用域、账号权限、删除传播及恢复语义 |
| 扫描任务调度与取消 | 部分（关键静态分支） | 扫描报告定位 compound 顺序汇总、pause/cancel 与并发配置入口；E12/E13 交叉支持缓存任务取消分支 | 默认并发、超时、底层阻塞可中断性与实际性能 |
| 通用目录空间计量 | 部分（关键静态分支） | 扫描报告定位 getattrlistbulk、Spotlight 物理大小与 fts fallback；E15 确认不可读且已授权时提权计量 | hardlink/APFS clone/快照/占位符去重与本机误差验证 |
| 删除执行与权限边界 | 部分（关键静态分支） | 扫描报告定位直接移除、Trash 与 protected remover 拒绝分支；没有执行删除 | 全入口保护覆盖、保护集合、扫描后竞态、逐项失败/取消/恢复 |
| UI 导航及模块首页 | 确认（已见页面） | E10/E17 记录 Cleanup、Applications、My Clutter、Space Lens；可见类别及用户目录/卷选择入口 | 扫描结果页、实际选择器展开与范围变更效果 |
| UI 扫描范围设置 | 确认（本机现状） | E18 记录 Smart Care 五个模块选中、Cleanup 下四类独立配置；没有切换勾选 | 出厂默认值、范围设置到实际扫描任务的对应；当前状态不能代表默认策略 |
| UI 扫描与清理完整流程 | 未验证 | Scan 控件 offscreen；菜单/键盘等尝试后 E19 仍为 Cleanup 首页；未见扫描中/结果，无删除 | 解决可见控件/窗口布局后采集扫描中、结果及选择状态；删除另需确定范围 |
| 自研方案可行性与安全性 | 未知（尚未实现） | 用户目标已确定；逆向发现可用于候选设计 | 区分复现事实与自研选择；先构造样本验证扫描，再验证选中项执行 |

## 证据索引

本地证据放在 `.local/evidence/`。以下相对路径均从仓库根计算。大文件优先读取摘要，避免重复生成。

| ID | 文件 / REA Evidence ID | 能证明的范围 |
|---|---|---|
| E01 | `.local/evidence/artifact.json` · `ev_1ca94764359d2703e8a30d5ecf8204a9a14b5f7f3fde4f42aaf01c7ca3a8f440` | 包图与目录快照；包根 SHA-256 `c80196019ff293e7b147396e25ced911a55b503b5ee638adc92efeae05b47371` |
| E02 | `.local/evidence/signature.json` · `ev_cddda4ae9a56a7506fe5a5e07569d9293f8a57ffa875aa2d5f9b8f6455d06226` | 签名元数据、标识 `com.macpaw.CleanMyMac5`、team `S8EX82NJP6`、entitlements；未检查完整文件系统签名上下文/信任 |
| E03 | `.local/evidence/rea-setup.json` | Codex 与 Skill 配置应用结果，保留配置备份路径 |
| E04 | `.local/evidence/rea-provider-setup.json` | 后续 provider 环境注册应用结果 |
| E05 | `.local/evidence/ghidra-doctor.json` | 指定 Ghidra provider 的环境检查；其他未配置客户端/引擎不影响此窄结论 |
| E06 | `.local/evidence/macho.json` · `ev_52d8de724a01397c41cf6c3648f734ccec4f1a07f1a80fe238d268c19aa1586d` | 主程序静态结构，主程序 SHA-256 `dd91651f7e204dc79652dc2ef3b9f16a859235d324021f17806cc5fdc90528fd` |
| E07 | `.local/evidence/scanners/manifest.json` 及同目录静态提取文件 | 23 个目标的身份与静态调查输入；是否成功处理以各文件内容为准 |
| E08 | `.local/evidence/resources/resource-inventory.json`、`cleaning-localizations.json`、`module-localizations-full.json` | 资源及功能文案；不是完整可执行清理规则 |
| E09 | `.local/evidence/resources/cmmkb-format-probes.json` | 两个规则候选载体的摘要、熵与有限格式探测失败；不能排除其他封装 |
| E10 | `.local/evidence/ui/01-cleanup-intro.png`、`02-scan-state.txt` | 已采集 Cleanup 首页及其无障碍树；本轮复核读取文本，截图视觉由主线程复核 |
| E11 | `.local/evidence/mcp-startup-doctor.json` | 独立 production-stdio MCP 进程启动、6.4.0 身份、170 工具清单、binary_session 请求均通过 |
| E12 | `.local/evidence/cache-scan-decompile.json` · `ev_dafd2ce42752298b1634a93891d39f2bb6d1cea8aeb6a2901ff1584dac05a0b2` | `CMCacheScanTask.scan @ 0x672c` 的 Ghidra 伪代码 |
| E13 | `.local/evidence/native-0x69fc.json` · `ev_57e7cc261852ed648aacd010ac8d505672b98e5cd4ace0bb9f6d231ef1a993f3` | map 回调，暂停/取消/ignore/KB 分流/零大小和授权/结果建模 |
| E14 | `.local/evidence/native-0x6c2c.json` · `ev_d2a003336d5f384926b44d735a6a6af9f54dfd283237e06d0b742aeeb67afa9c` | deep-search 方法为当前目录子项分组，空组返回 nil；不证明无限递归 |
| E15 | `.local/evidence/native-0x6f34.json` · `ev_3dbae47dca3dc7ec78b0ebed70e112ea01362138e37bfda79c343b9bb4dc3d52` | 普通计量为零后，可读性与已授权条件控制 privileged size fallback |
| E16 | `.local/evidence/native-close.json`、`cache-session-snapshot.json` | 主线程 close 调用返回快照路径、34,455 字节与 4 条 evidence records；该回执未单独返回 closed 布尔字段 |
| E17 | `.local/evidence/ui/03-applications.png` / `.txt`、`04-space-lens.png` / `.txt`、`05-my-clutter.png` / `.txt` | 三个模块首页、类别、目录/卷选择入口；不是扫描结果 |
| E18 | `.local/evidence/ui/06-scanning-settings.png` / `.txt`、`07-cleanup-settings.png` / `.txt` | Smart Care 与 Cleanup 扫描范围的当前勾选状态与展开结构 |
| E19 | `.local/evidence/ui/08-final-cleanup.txt` | 结束时仍是 Cleanup 首页和 Scan 按钮；未观察到扫描启动 |
| E20 | `.local/evidence/round2-selection/index.json`、`shared-utils-identity.json` 及两次 snapshot/close | 16 份不同函数伪代码，SharedObjcUtils 汇编核对 block index；详情见默认选择专题 |
| E21 | `.local/evidence/round2-models/evidence-index.json`、`key-control-flow.asm.txt`、`53.json` | 48 个不同 Evidence，其中 45 份非空伪代码；49 条索引响应含重复，不能直接按文件数计函数 |
| E22 | `.local/evidence/round2-kb/evidence-index.json`、`database-verification-schema.json`、`schema-caveats.json` | framework 5 份函数伪代码、主程序 LLVM、随包数据库解码/schema/类型映射/关联缺口 |
| E23 | `.local/evidence/round2-operation-counts.json` | 按 Evidence ID 去重计数：16+45+5=66 非空函数反编译证据；失败和其他操作另列 |
| E24 | `.local/evidence/round2-kb-review/review-evidence.json` | 独立 cryptography 逐字节复现293页、HMAC/SQLite/hash与负例复验、872行源反汇编对齐 |

E13–E15 的 JSON 是 MCP RPC 封装，Evidence 位于 `result.structuredContent`，伪代码正文是 `normalized_result` 字符串。E12–E15 均为静态 Ghidra 输出，有 ObjC fixup/流程模型等限制，不是原始源码或动态调用轨迹。

## 已处理阻塞与保留限制

- `.local/evidence/legacy-getfileinfo.json` 是先前 universal Mach-O 的 `capability_unavailable / architecture_unsupported` 错误，保留作失败证据。主线程随后对独立 arm64 切片取得 E12–E15；这不表示该 legacy 函数已经由 REA 成功反编译，legacy 的相关结论仍来自专题中的反汇编。
- `.local/evidence/cache-scan-decompile.json` 已完成并是有效 Evidence JSON，初建时的不完整状态已解除。
- 早期 `scanners/*.objc.txt` 使用旧版 otool 误解 compact method lists；方法地址应采用专题指定的 `*.llvm-objc.txt` / `objc-method-index.json`，不要混用旧 imp、文件偏移与 VA。
- UI 尚未开始扫描，不能报告扫描结果、扫描性能、默认勾选实际状态或完整清理流程通过。
- 第二轮主 executable Ghidra 330 秒超时，有失败与关闭回执；其知识库读取器结论来自 LLVM 和离线解码校验，不能称该主程序已由 Ghidra 成功反编译。
- 解码 verifier 初版 assert 在 `python -O` 下可被禁用，已改显式异常，并由独立审查重跑正常/优化模式及错误材料/源hash负例；以修复后回执为准。

## 交付索引与只读复核

| 交付文档 | 用途 |
|---|---|
| [README](../README.md) | 安装、目标身份、首轮发现与限制的总入口 |
| [扫描与清理机制](scanning-mechanisms.md) | 关键静态调用链、计量、删除入口与规则路径 |
| [资源与规则模型](resource-rules.md) | 随包声明、KB 模型与规则未解部分 |
| [REA 原生实证](native-evidence.md) | 四个函数的 Evidence ID、伪代码重述与复现方式 |
| [界面观察](ui-observations.md) | 实际首页、范围设置、操作阻塞与最终状态 |
| [自研设计](self-cleaner-design.md) | 独立设计、分期、数据契约与未来验收要求 |
| [第二轮汇总](round2-summary.md) | 随包库解码、默认选择与模型计划的新增证据及剩余缺口 |
| [知识库深查](knowledgebase-deep-dive.md) | 格式、schema、数据质量、类型映射与少量保护例子 |
| [默认选择与备份](default-selection-and-backups.md) | 基类/子类默认值、备份排序/异常分支、plist和语言保护 |
| [模型清理深查](model-cleanup-deep-dive.md) | Ollama引用图/共享blob计划、LM Studio格式与分片边界 |

已读取 [资源与规则模型](resource-rules.md) 和 [扫描机制](scanning-mechanisms.md)。首轮复核未发现需要阻断结论的过度声称：资源文案、metadata、汇编控制流与新设计均有区分。首轮“知识库未解密”现为历史状态，由 E22/E24 更新；硬编码路径非删除白名单、保护不等于全局无误删的边界仍成立。

缓存主链的 ignore/KB 分流、深搜子项与条件提权描述与 E12–E15 一致。扫描报告其余函数本轮仅复核论证与限定语，未逐条重新反汇编，因此“未发现问题”不代表每个地址均获得第二次独立验证。标题“已确认”均须沿用报告明确的静态范围；其中“实际调用”指已解析的代码调用指令，不是本机运行日志。自研建议不得被后续汇总改写成原产品事实。

最终 README 与三份新增文档亦已只读复核：均保留“首轮/未完整还原/未实现软件/未执行清理”的边界，未发现实质事实夸大。UI 表格与 E17–E19 的无障碍树一致；General/Full Disk Access 和交互尝试引用主线程 CUA 观察，未把它们冒充留存截图。本次检查仓库 README 和 docs 中的本地 Markdown 链接，未发现缺失目标；未重复核验外部链接或重装/重跑工具。

第二轮三专题均已读取，直接抽查选择/备份关键伪代码、模型计数与GGUF检查，并核对知识库独立验证回执。未发现实质过度声称；未逐条重复反汇编全部66函数。最终计数与本地文档链接另行校验。静态计划安全条件、SQLite结构完整性和维护注释分别不能替代动态删除验证、业务关联正确性或故障复现。

## 下一次交接

前两轮专题、反编译、知识库离线解码、UI 页面证据和独立设计已归档。后续优先补足规则组合匹配/运行更新、扫描结果到最终选择再到执行器的调用链、模型跨组联合回收与动态恢复/收益。自研仍未实现；若开工，应从只读扫描和计划预览的合成夹具验收开始，不能把本调查的静态结论直接当安全清理白名单。
