# 第二轮逆向：增量证据与剩余缺口

日期：2026-10-12。三份专题及关键证据已复核。本轮完成随包知识库解码，并进一步恢复默认选择、备份和模型计划的关键静态分支；整个产品的运行机制尚未完整还原，自研软件尚未实现。

## 本轮目标

继续回答首轮留下的三个问题：知识库怎样打开与匹配、不同扫描任务怎样决定初始选择、模型和备份怎样组织删除候选。产物继续服务于自用 Mac 清理工具的独立实现；没有执行真实清理。

当前聊天没有直接暴露 REA MCP 工具；本轮通过已安装 CLI 和独立 MCP stdio 会话取得了真实目标函数的静态反编译结果。这证明分析调用成功，不证明目标业务代码已经在本机执行。

按 Evidence ID 去重，本轮新增 **66 份非空函数反编译证据**：默认选择/备份 16、模型 45、知识库 framework 5。搜索和函数信息不计入此数；主 executable 的 Ghidra 超时也不计入成功。计数来源：[round2-operation-counts.json](../.local/evidence/round2-operation-counts.json)。知识库离线解码与独立验证另有证据，不冒称 Ghidra 恢复了原源码。

## 随包知识库已解码，规则引擎仍未完整恢复

两个随包 `.cmmkb` 共 **293 页（291 + 2）HMAC 全部通过**，SQLite 只读 `integrity_check=ok`，源 hash 未变。独立审查用另一套 cryptography AES 实现重新解码并逐字节匹配，还验证错误材料/源 hash 在 `python -O` 下被拒绝。最初 verifier 的 assert 校验缺陷已经修正并复验；见 [独立复核回执](../.local/evidence/round2-kb-review/review-evidence.json)。

现在确认 `ApplicationFiles=1,912`、`ApplicationInfo=990`、`ScanItems=1,509`、`RecordInfo=1,509`、`GroupType=26`、`General=1`；随包 `UserIgnore=0`。静态枚举映射恢复 7 个 ScanItemType、49 个 ScannerID。**表行数不是可删除规则数**：数据包括保护、忽略、深入扫描与应用关联，代码里还存在独立策略。

解析通过也不等于所有数据关联正确：`IsRegex` 实际均为字符串；外键声明引用不存在的 `GroupType.RecordId`，按真实 `Type` join 仍有 4 条 ApplicationFiles 分组无对应项。完整匹配优先级、`Int.max` 扫描器作用域、GroupType=22 fallback、用户实际运行库/在线更新仍未知。

库中 Arc、Native Instruments、美图等维护注释解释了缓存可能承载会话、授权或专业工作流数据。它们是随包维护说明；本轮没有通过实际删除复现这些后果。对自研的直接要求是把 protect/ignore/descend/appAssociation/cleanupCandidate 分开，不能把关联资源表作为清理白名单。完整说明见 [知识库深查](knowledgebase-deep-dive.md)。

## 已独立复核的窄结论

| 结论 | 静态证据 | 适用边界 |
|---|---|---|
| 基础缓存任务 `CMCacheScanTask.isResultAutoselectable` 返回 true | `round2-selection/0x7130.json`，`ev_402b0351702475d9f17691be51f2ab55204d96a36d581cd8660356d77539605d` | 只确认此实现；子类可覆盖，不能推广为所有缓存默认安全/选中 |
| Gradle 缓存任务覆盖该方法并返回 false | `round2-selection/0xb6a0.json`，`ev_8ab10e002c00155a13fb110f9f75d14a7f4e28a19e2920e494c60feeb9718ca0` | 确认存在任务级差异；最终 UI 选择状态尚未观察 |
| Gradle 任务工厂从 CMPaths.gradleCaches 取得根，再构造任务 | `round2-selection/0xb5e0.json`，`ev_9629e9ac3643d6c801b78bdec85209924e7a7a8c945691fb2ba3d4ed8e3c4963` | 没有从此函数恢复路径值或可删范围 |
| 正常备份分组按日期降序；首项 latest=true、autoselected=false，其余项自动选择 | `round2-selection/0x13684.json`、`0x1403c.json`、`0x14194.json`；SharedObjcUtils 汇编确认回调参数为 index | 日期先取 Status.plist Date，回退 Info.plist Last Backup Date；最终 UI、日期缺失/相同仍未验证 |
| BrokenBackups 分支传入 autoselected=true、latest=false | `round2-selection/0x00014370.json`，`ev_0edcea0324c2107744b8a5b7a75ec05e0d3f046aee8a4d4b5798ccafc70327ef` | 这是缺少有效设备名的元数据分支；不证明备份整体无法恢复 |
| Ollama 全局引用表缺失，或存在候选却引用表为空时，不生成该分支计划 | `round2-models/7.json`，`ev_c4f535492e278a816d92eb0358bd08f4d9888e17facd8b7ddd06931f602023d2` | 静态计划计算；UI 输入集合及最终 executor 尚未跟通 |
| Ollama blob 需满足跨组计数≤1 且全局引用数≤组内去重 manifests 数，才进入删除计划 | `round2-models/26.json`，`ev_61a199f4c16d6cdc0d6b838753c6b69df3206064f3095b3cd831aaed16085ed8` | 跨组共享可能保守保留；不证明多选组会联合优化释放空间 |
| GGUF 分片检查序号集合等于1..N，逐片检查8字节头与版本≥2 | `round2-models/14.json`、`34.json`、`37.json`、`52.json` | 头部识别不是全模型可加载/完整性验证；不将不完整模型自动当垃圾 |

表中路径相对 `.local/evidence/`。Evidence 的 `normalized_result` 是反编译伪代码，保留其 ObjC fixup、类型和控制流恢复限制。

## 专题与复核边界

| 专题 | 状态 | 保留的边界 |
|---|---|---|
| [知识库加载与匹配](knowledgebase-deep-dive.md) | 已交付，解码经独立复验 | 随包数据格式与主要类型已恢复；完整规则语义、运行版本与更新链未知 |
| [模型清理计划](model-cleanup-deep-dive.md) | 已交付并复核 | manifests、共享 blob、分片的关键静态分支；仍无实际删除证明 |
| [默认选择与备份](default-selection-and-backups.md) | 已交付并复核 | 基类/子类差异、正常/异常备份分支、latest 判定、损坏 plist 与语言保护入口 |

本次汇总直接抽查了默认选择、备份日期与布尔构造、模型计数过滤/集合比较/头部检查的伪代码，并阅读三份专题及知识库独立验证回执；没有把全部 66 份函数逐条再次反汇编。全部原始 Evidence、hash 和操作限制保留在本地证据目录。

设备备份还有两点需要保留：设备对象 equality 比较 `deviceFullName`，不能宣称已经按硬件 UDID 唯一分组；该任务取消时可以返回空结果，不能把其他任务保留部分结果的行为推广到它。损坏 plist 谓词有存在性、类型、锁文件、不可变标记、可读流和取消检查；解析失败仍不等于删除授权。

## 运行观察

本轮 UI Scan 尝试仍未成功，未观察到扫描结果、执行计划或清理完成。静态函数数量增加不能消除这一缺口。没有测得本机可回收量，也没有验证删除后空间收益。

## 下一步依据

1. 首个自研交付仍应为只读空间地图、候选与保护原因、计划预览；为每条独立规则建立合成目录样例，先证明不会越界和误判。
2. 模型计划先验证共享引用、损坏 manifest、分片缺失和计划后新增引用，再考虑执行器；UI size 不能直接当释放量。
3. 继续研究时优先接通结果转换/最终选择/执行器的调用链，以及知识库组合匹配与运行更新；不要用更多函数数量替代缺口收敛。

当前整体状态见 [覆盖台账](coverage.md)。所有自研建议均是后续设计与验收要求，本轮没有实现或运行这些测试。
