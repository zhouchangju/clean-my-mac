# 验收设计与证据要求

contract revision：LMC-v0.1；design version：2（Markdown契约，不声称已运行JSON结构校验器）；subject version：尚无软件实现。

**全部AC结果均为 UNVERIFIED。** 需求可用于实施，不等于已经测试通过。文档检查与软件验收分开。本设计按 Eval First/software 的行为、生命周期、权限和独立判据组织。

## 1. 来源、决策与覆盖

- S-U1：用户希望为存储有限的Mac开发自用清理工具，先研究机制/规则与UI。
- S-U2：本轮用户要求PRD、方案、任务和交接Prompt，未要求本轮实现。
- S-U3：本轮用户选择原生macOS（Swift/SwiftUI、中文、本地）。
- S-D1：[PRD](01-PRD.md) v0.1；S-D2：[契约](03-CONTRACTS-AND-RULES.md) v0.1。其中性能预算、默认阈值/保留期、工程分层是本次设计选择，不冒充用户逐项确认。
- S-R1：[第二轮研究](../round2-summary.md)，只支持原产品静态发现；**不作为LMC的测试PASS证据**。

范围/目标由用户拥有；在既定范围内的实现与测试判据由开发负责人维护；真实文件操作由最终用户确认；实验可行性由实际测试决定。原生方案问题已解决，无需再次问技术栈。执行器是否满足竞态要求属于必须做实验的工程问题，不由用户猜答案。

| 覆盖维度 | 状态 | 判据/范围 |
|---|---|---|
| goal_scope、inputs、behavior | applicable | AC-01–18，显式范围、计划、执行 |
| permissions_and_consumers、lifecycle | applicable | AC-02/04/12/15–17/24，拒绝/取消/重启/版本 |
| quality、delivery | applicable | AC-21–23/25，实际原生路径与制品 |
| data_semantics、reconciliation | applicable | AC-05/06/18/26，口径及journal对账 |
| 隐私与资源 | applicable | AC-19/20/23 |
| 云端/支付/多租户 | not_applicable | 产品没有这些能力 |
| 最低系统实机覆盖 | unknown，非当前宿主交付阻塞 | 未有macOS14测试机时只声明宿主验证，不宣传全版本兼容 |
| M3模型/完整卸载 | not_applicable to v1 | 不进入默认DONE范围；未来另立契约 |

## 2. 公共规则

每项AC以下行定义一个具体case，case ID为 `TC-` 加相同数字。每项绑定所列FR和INV。除单列说明，均为对应阶段的阻塞条件，判据可信度HIGH指判据可操作，不是实现通过概率。性能预算AC-23可信度MEDIUM，需固定环境实测。

fixture builder创建独占临时根、marker、root identity，生成文件布局并保留**独立expected manifest**。expected不能由被测RuleEngine/Planner自己生成。文件结果用独立lstat/hash/目录快照验证；失败注入用测试adapter与真实临时目录相结合。不能为了PASS删改expected或缩小攻击样例。

50k基准固定为100个子目录各500个1KiB普通文件，额外边界样例单独运行。生成前检查可用空间至少2GiB，fixture实际占用上限512MiB，超限停止并记录BLOCKED；不创建巨量真实大文件来凑逻辑大小。稀疏文件用有限物理占用生成。teardown只删除本次持有marker和身份的fixture根，不清空共享临时目录。冷/温缓存条件据实记录，不能运行系统purge或清理用户缓存来制造“冷启动”。

## 3. 验收案例

| AC / 来源 / 阶段 | 输入、操作与正反例 | 独立判据及PASS条件 | 所需证据 |
|---|---|---|---|
| AC-01 / FR-01 / M0 | 首次开App不选根；CLI不传root；然后选择fixture根 | 未选择时无target枚举；缺root报错；选择后只读指定根，home/临时根外sentinel访问计数为0 | unit+real_host，读取spy与root快照 |
| AC-02 / FR-01/INV-02 / M0 | 根含指向外部secret sentinel的symlink、挂载边界、权限拒绝目录；扫描 | 不读链接目标/跨卷后代；拒绝目录显示缺口，scan状态partial；外部sentinel hash不变且未读内容 | isolated+real_host，审计spy/元数据清单 |
| AC-03 / FR-02/INV-01 / M0 | 50k树扫描，记录目标mtime/文件hash与写调用；仅写自身index | 不改目标；分页可查询增量；累计processed正确，未知总量无伪百分比 | isolated+rendered，expected计数与前后manifest |
| AC-04 / FR-02 / M0 | 扫描一半取消，再立即启动新根；故意晚送旧回调 | 保留旧partial/cancelled；新结果不被旧run覆盖；正常本地fixture2秒内停止新I/O调度 | unit+real_host，代次事件日志/时序 |
| AC-05 / FR-03/INV-07 / M0 | 4096B文件、sparse大逻辑文件、同inode两hardlink、含子目录 | logical正确；allocated与独立stat blocks口径一致；同inode/父子不重复加总；未知保留未知 | unit+real_host，原生stat expected |
| AC-06 / FR-03 / M0 | 子目录权限失败；可选APFS clone fixture；切换逻辑/占用排序 | 父目录partial含unknownCount；clone独占不假定等于逻辑量；排序方向与独立固定值一致 | unit+rendered；clone实际无法创建则该host分项UNVERIFIED |
| AC-07 / FR-04/INV-04 / M0 | 一个保护项同时命中候选；用户ignore命中；保护目录中有看似cache文件 | 更保守策略胜出，所有行可解释，选择接口和UI均拒绝保护项 | unit+rendered，预先人工定义decision表 |
| AC-08 / FR-04/05 / M0 | 规则缺字段、未知schema、越界root、`..`、未支持regex；夹杂合法规则 | 整体拒绝新规则集，保留旧合法版；无旧版仅占用预览；执行未启用 | unit，固定合法/非法rule fixtures |
| AC-09 / FR-05 / M2 | ≥2条真实规则准入；控制profile/fixture工程生成产物后清理再生成；busy/unknown对照 | 每条有格式/再生成/排除/活动证据；previewOnly不能执行；新扫描选择为空 | isolated+real_host，规则准入记录；不得使用真实用户profile做破坏试验 |
| AC-10 / FR-06 / M1 | 过滤列表后选组，含隐藏/保护/重复后代；新增ignore并重开 | 只选当前可操作项；隐藏已选明确提示；去重；ignore持久且旧计划失效 | unit+rendered，明确ID集合expected |
| AC-11 / FR-07 / M1 | 同输入不同字典迭代顺序生成计划；篡改一个item/hash/schema；外来plan文件 | 固定规范化hash一致；篡改/未知版本/外来执行计划被拒绝；预览不触发target写入 | unit+isolated，独立hash测试向量 |
| AC-12 / FR-07/INV-03 / M1/M2 | 文件mtime/inode/size、祖先目录身份、规则/忽略版本、卷任一变化；Clock推进到过期边界 | 过期时刻及以后拒绝；变化项不得继续用旧确认；无法读取身份拒绝 | unit+real_host，注入clock+文件替换 |
| AC-13 / FR-08 / M2 | 用户文件trash计划；同文件尝试purge；准入缓存purge计划 | 普通文件purge拒绝；Trash和Purge确认独立；未确认/旧确认不得执行 | unit+rendered，动作枚举/确认事件 |
| AC-14 / FR-08/INV-03 / M2 | nlink>1、symlink、cloud placeholder、active/unknown、跨卷、整个目录作为执行项 | 每项准确拒绝，target无修改；目录组展开仅固定合格叶子，不删目录 | isolated+real_host，外部sentinel/身份快照 |
| AC-15 / FR-09/INV-03 / M2 | 在precheck与move之间替换叶子/父目录；移动后对象错配；新建未计划子文件 | 绝不永久删错配对象/外部sentinel；新文件保留；错配进入恢复/人工处理且日志可对账 | isolated+real_host，确定性同步钩子+对抗fixture；失败则M2阻塞 |
| AC-16 / FR-09/INV-05 / M2 | 并发双击、同plan重复请求；处理第2项前取消 | 单transaction；每项最多一次；已完成项保持，后续不调度；不声称永久动作已撤销 | unit+isolated+rendered，调用计数/manifest |
| AC-17 / FR-09/INV-05/06 / M2 | journal写前、stage后、删除后commit前分别中断；恢复位置已占用 | 无journal不变更；重启对账；不确定不重删；恢复不覆盖，保留可见stage | isolated+real_host，逐crashpoint启动/退出/重启证据 |
| AC-18 / FR-10/INV-07/08 / M2 | 3项分别成功/拒绝/失败；free space采样不变或负数；Trash成功 | 显示对应真实计数；不把Trash算释放；如实显示净变化和未知，不按估计伪造结果 | unit+rendered，独立注入volume samples+文件结果 |
| AC-19 / FR-11 / M0/M2 | index达到软上限、空间不足、过期history及pending transaction并存 | 扫描停止且partial；不会裁剪待恢复事务；journal不足不变更；历史策略可验证 | unit+isolated，quota/fault adapter与目录核对 |
| AC-20 / FR-11 / M0 | 路径含用户名/标记secret名称；导出默认/显式完整模式；断网启动扫描 | 默认导出脱敏；无目标文件内容/凭据读取；无网络请求；离线可用 | unit+real_host，mock network拒绝、宿主进程网络观察与导出检查 |
| AC-21 / FR-12 / M0/M2 | 1000×680/1180×780、深浅色、长路径、键盘/VoiceOver；进入离开重复3次 | 主动作可见可达；标识唯一；颜色外还有状态；无多次事件/残留订阅 | rendered+real_host，截图+UI动作回执 |
| AC-22 / FR-12 / M0/M2 | clean checkout构建package/app/test；Release `.app`复制到另一测试目录启动 | 真实scan驱动UI；无REA/原app/开发机绝对路径运行依赖；包≤100MiB；版本与制品hash留档 | static+real_host，命令退出码、启动/UI证据 |
| AC-23 / PRD质量目标 / M0/M2 | 固定50k APFS fixture，在记录环境中测3次冷/温条件 | 每次记录wall/RSS/主线程忙段；达到PRD预算；异常需保留并修复/记录决策，不挑最快一次 | METRIC real_host，原始测量与方法 |
| AC-24 / FR-01/07 / M1/M2 | 扫描后移除权限或卸载卷；重启应用；改变scope | 旧计划和确认失效；不自动再次申请/扩权限；用户可重扫可用根 | isolated+real_host，状态/访问spy |
| AC-25 / FR-01–12 / M2 | 从原生App首次启动，用fixture完成扫描→选择→两类计划各一次→执行→历史恢复 | 同一真实业务链，不是UI mock；Trash对象能无覆盖恢复到原路径；purge不可恢复状态正确 | real_host+rendered，fixture before/after、journal、操作录屏或截图序列 |
| AC-26 / FR-05/07/10 / M1/M2 | `enabled:"false"`、引用缺失rootID、溢出字节数、parent/child重复、512MiB阈值前一字节/等于/后一字节 | 严格类型与范围校验；异常隔离/拒绝，不卡死；边界筛选符合>=；父子只计一次 | unit，人工expected原始JSON/字节值；从原库类型/坏关联问题提炼反例，不要求导入原库 |

AC-09真实规则准入、AC-15竞态探针、AC-17恢复、AC-25原生全链是M2关键条件，不能用纯mock替代。权限/云占位等不具备环境的host分项保持UNVERIFIED，v1对相应对象能力禁用，而不是把测试改成通过。

M1只要求T09对至少两条真实候选形成可复核的准入调查记录，可以全部保留previewOnly；AC-09的“至少两条通过”仅阻塞M2。M1的Planner/Preflight必须正常处理previewOnly并返回拒绝原因，可预览合法Trash候选，不需要提前开放Purge。

同一AC列出多个阶段时，证据记录必须含phase；M0仅评价只读/索引/界面适用断言，M2必须补齐执行/恢复断言。例如AC-19的M0验证索引配额，待恢复事务保护在M2验证。低阶段PASS不能继承为高阶段PASS。

## 4. 反例必须被检测

至少做三项定向错误替换（测试用变体，不合入产品）：忽略protect优先级、令identityChanged仍执行、将trash估计计入已释放。对应AC-07/15/18必须失败。验证器不能由执行器自己返回“成功”作为唯一判断。

目录竞态若无法在限定方法中可靠阻止，记录BLOCKED并保留M1。平台无法确定进程在用情况时必须走unknown，不能为了AC-09数量要求放宽。

## 5. 证据与状态

每份验证记录字段：AC/TC、phase、任务、软件revision或文件hash、规则/fixture版本、系统/架构/文件系统、命令、退出码、required scopes、observed results、原始产物路径、限制、状态。截图不证明文件安全；单测不证明原生UI；代码评审不证明运行。

软件状态只使用PASS/FAIL/BLOCKED/UNVERIFIED/HUMAN_REVIEW。任务未做完用TODO/DOING/BLOCKED/DONE；DONE必须链接证据。M0/M1/M2分别判断，不能以低阶段DONE代替整个v1。

独立复核者应收到用户目标、这些标准和实际产物，不依赖builder自评。允许两轮针对性修正；同一错误重复两次无进展时停相关任务并保留原因。不得通过降低标准、删除case或扩大用户数据操作来完成循环。

## 6. 本文档的反向检查

已在设计中处理的反例：只画界面会被AC-22/25拒绝；仅移Trash却声称释放会被AC-18拒绝；只校验路径字符串会被AC-15拒绝；权限失败返回空会被AC-02/06拒绝；原库所有行当删除规则会被AC-07/08/26拒绝。它们是设计检查，不是执行过的软件测试。
