# 开发任务与交付顺序

版本v0.1；所有任务初始 **TODO**。XS/S/M是相对复杂度，不是工期/Token承诺。任务超出一次工作会话时按明确行为继续拆分并保留父ID，不整批标完成。

先读PRD/契约/验收，再按依赖执行。多AI并行只安排无依赖、文件职责分离的任务；不是“同时让所有AI改整个仓库”。协作者必须保留他人改动，数据模型变更先协调。

## 1. 任务表

下表“验收”引用完整AC，不表示该任务单独即可让全项PASS。公共输入是 [01](01-PRD.md)、[03](03-CONTRACTS-AND-RULES.md)、[05](05-ACCEPTANCE.md)。

| ID / 阶段 / 大小 | 任务、输入与交付 | 主要文件职责 | 依赖 | 验收 |
|---|---|---|---|---|
| T01 / M0 / S | 探测xcrun工具链，建立根package与App/shared scheme/UI test target；输出可复现构建入口，不做清理 | Package.swift、App工程、初始scripts | 无 | AC-22 |
| T02 / M0 / S | 按契约实现ID、字节/错误/状态类型、JSON codec与固定测试向量；提供protocol stubs | CleanerDomain、Domain tests | T01 | AC-05、AC-08、AC-26 |
| T03 / M0 / S | 创建私有fixture builder、独立expected manifest、权限/链接/稀疏/故障注入；拒绝非fixture根 | TestSupport、fixture tests | T02 | AC-01、AC-02、AC-15基础 |
| T04 / M0 / M | 实现范围/卷/文件身份与不跟链接枚举；受限worker、取消和generation | CleanerMacPlatform/FileReader、CleanerCore/Scan | T02、T03 | AC-01–04、AC-24 |
| T05 / M0 / S | SQLite增量存储、分页/树聚合、硬链接去重、容量口径及上限 | CleanerMacPlatform/Store、Core/Measurement | T02、T03 | AC-05、AC-06、AC-19、AC-26 |
| T06 / M0 / S | 实现严格规则schema与保守优先级、保护边界、理由码；所有seed previewOnly | Core/Rules、Resources/Rules | T02、T03 | AC-07、AC-08、AC-20 |
| T07 / M0 / S | 真实scan/规则/Store连接；只读CLI、正常/部分/取消结果；无隐含Home默认 | CleanerCLI、App composition接口 | T04、T05、T06 | AC-01–08、AC-20 |
| T08 / M0 / M | 原生范围/总览/候选/大文件页，连接真实服务；分页和唯一AX标识；完成M0演示 | App/Views、ViewModels、UITests基础 | T07 | AC-03、AC-06、AC-21–23 |
| T09 / M1 / M | 至少2个真实seed候选的格式/版本/受控验证调查；完成逐规则记录并明确eligible/previewOnly/rejected，失败不升级能力；至少2条准入通过另为M2条件 | Resources/Rules、docs/implementation/rule-admission | T06、T07 | AC-08；AC-09仅在M2要求PASS |
| T10 / M1 / S | 忽略持久化、选择集合/筛选语义、规则/忽略版本失效 | Core/Selection、Core/Ignore、App对应页 | T08 | AC-10、AC-19 |
| T11 / M1 / S | 实现纯Planner、规范化hash、固定叶子清单、单动作计划与TTL | Core/Planning、plan tests | T09、T10 | AC-11、AC-12、AC-26 |
| T12 / M1 / S | 实现非变更预检：owner activity、身份、卷、规则准入、权限，unknown保守拒绝 | MacPlatform/Preflight、Activity | T04、T09、T11 | AC-12、AC-14、AC-24 |
| T13 / M1 / S | 计划预览/失效/动作差异UI，确认UI仅发出当前plan intent；生产执行仍禁用 | App/Plan、CLI plan | T11、T12 | AC-10–14、AC-21 |
| T14 / M2 / M | 技术探针：anchored父目录、同卷staging、替换/重命名/新文件竞态；写取舍报告，判定方案是否可启用 | CleanerExecution/Probe、Execution tests、probe报告 | T03、T12 | AC-14、AC-15；失败阻塞M2 |
| T15 / M2 / S | durable journal、单事务锁、至多一次调度与未知结果隔离、空间不足拒绝；不做真实删除 | Execution/Journal、Transaction、Receipt | T11、T14 | AC-16、AC-17、AC-19 |
| T16 / M2 / S | Trash动作适配：stage对象→系统Trash，记录返回位置与原路径；失败保留/恢复 | MacPlatform/Trash、Execution/Trash | T15 | AC-13、AC-14、AC-18 |
| T17 / M2 / S | Purge动作：仅固定准入普通叶子、不删目录、不扩大集合；测试build内反例验证 | Execution/Purge、Execution tests | T15、T09 | AC-13–16、AC-18 |
| T18 / M2 / M | 中断/重启对账、staging无覆盖恢复、Trash收据驱动恢复原位置；不确定不重试 | Execution/Recovery、MacPlatform/Restore | T16、T17 | AC-17、AC-24、AC-25恢复部分 |
| T19 / M2 / S | 原生执行确认、停止、结果/历史/恢复UI；生产CLI保持无真实delete入口 | App/Execution、App/History | T13、T18 | AC-13、AC-16、AC-18、AC-21 |
| T20 / M2 / S | 隐私/导出/索引与收据保留、pending事务保护；离线/无联网证明 | Store维护、App/Settings、export | T05、T18、T19 | AC-19、AC-20 |
| T21 / M2 / M | 跑完整fixture正常/失败/取消/崩溃/恢复和三个错误变体；留独立结果 | tests、.local/verification | T19、T20 | AC-01–20、AC-24、AC-26 |
| T22 / M2 / S | 原生UI全链+无障碍+窗口尺寸；固定50k基准三次，必要优化且保护case不退化 | UITests、benchmark、App定向修正 | T21 | AC-21、AC-23、AC-25 |
| T23 / M2 / S | 独立源码/文件边界/错误恢复复核，按证据检查AC；修复后复验，不降标准 | review记录、定向修正 | T21、T22 | 所有M2 AC；报告残余限制 |
| T24 / M2 / S | clean build、Release.app、独立目录启动、用户手册/操作限制/验收汇总 | scripts/package、README、docs/implementation | T23 | AC-22、AC-25；v1交付 |

M0完成条件：T01–T08及对应AC；M1：T09–T13及对应AC；M2：T14–T24且所有v1阻塞AC满足。若T09准入不足或T14探针失败，可以报告M1已交付、M2 BLOCKED，不能宣称整个软件完成。

T09完成是完成调查、证据和能力标注，不要求两条都通过。T11/T12在此后可消费previewOnly并验证拒绝/解释行为；M1的DONE不包含M2专属AC-09的通过。两个准入通过条件在T17和M2最终验收再次核对。

## 2. 可并行批次

```text
T01 → T02 → T03
              ├ T04 文件系统/扫描
              ├ T05 Store/计量
              └ T06 规则
                   ↓ 三者汇合
                 T07 → T08
                 T09 ↔ T10（文件职责分开）
                   ↓
                 T11 → T12 → T13
                         ↓
                        T14 → T15
                              ├ T16 Trash
                              └ T17 Purge
                                  ↓
                                 T18 → T19 → T20 → T21 → T22 → T23 → T24
```

T09可在T07后开始，不必等待T08；T10需T08。图中的↔表示可并行，不表示循环依赖。T16/T17只能各自修改动作适配模块，共享journal接口由T15冻结。T14可在T12后和T13 UI并行，失败必须阻止执行能力启用。

## 3. 每任务交付模板

未来写入 `docs/implementation/tasks/Txx.md`，不要把下列空模板当证据：

```text
Task ID / status / phase:
输入文档revision与软件revision:
改动文件及行为:
实际运行命令、退出码:
AC与证据路径（unit/isolated/real_host/rendered）:
未运行项、失败、限制:
独立复核结果（若适用）:
下一任务与阻塞:
```

每任务最多两轮针对同一验收失败的无进展重试；超过时先分析根因或标BLOCKED，不无限换实现。日志必须保留失败记录，不能只留下最后一次绿灯。例行测试不修改用户真实目标，真正删除fixture外文件需要用户对明确计划确认。

## 4. 未来扩展任务（不在本次默认开发范围）

| ID | 主题 | 前置证据 |
|---|---|---|
| F01 | Ollama/LM Studio库存、共享引用计划 | 全manifest失败关闭、aliases、分片、选择闭包、计划后新增引用、在用/自定义根处理 |
| F02 | 内容重复文件 | 内容判等独立oracle、硬链接/clone计量、每组保留、逐字节/哈希策略 |
| F03 | 应用卸载/残留 | bundle/receipt/container归属、多app共享、系统保护与恢复 |
| F04 | 邮件/云文件/设备备份 | 实际恢复语义、同步传播、稳定设备身份；不能只靠资源文案 |

后续任务需要单独范围决定，不因v1做完而由AI自动开始。
