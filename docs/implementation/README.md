# 实施与交付状态

2026-10-12；LMC-v0.1 / acceptance design 2。

已交付真实只读扫描、中文SwiftUI界面、清理计划与保守预检，以及可启动Release `.app`。**M0/M1仍DOING，M2/v1 BLOCKED**：完整阶段AC未齐，真实规则准入0/2、活动覆盖unknown、系统Trash EPERM、完整事务/逐crashpoint重启恢复和原生执行全链未满足。生产ExecutionGate=false。内部fixture原型不能作为已完成的产品清理能力。

产物：`.local/dist/LocalMacCleaner.app`，Release、arm64、ad-hoc Hardened Runtime，1,474,715 bytes；全新DerivedData构建、签名验证、独立目录launch exit0。CUA观察首次启动scope未选且scan/plan禁用。完整manifest见`.local/verification/release-manifest.json`，[使用说明](USER-GUIDE.md)。

本轮仅在自建目录验证变更，未清理用户现有文件。早期系统Trash原型确实移动过自建fixture对象并留下未核实遗留；收据不完整、对象数量不完整，见[探针报告](execution-probe.md)及trash-probe-orphans.json。没有提权、扫描/清空系统Trash、覆盖安装、发布或push。

| 任务 | 阶段 | 当前状态 | 实现/剩余边界 |
|---|---|---|---|
| [T01](tasks/T01.md) | M0 | DONE | Package.swift、App工程/shared scheme/UI target、构建入口；工程建立完成；AC-22整体尚非PASS，最低系统/干净checkout及所有运行依赖独立审计未齐 |
| [T02](tasks/T02.md) | M0 | DOING | Models.swift、严格codec、ID/bytes/states/protocol；完整坏JSON/未知枚举/全部状态向量仍UNVERIFIED |
| [T03](tasks/T03.md) | M0 | DOING | 私有Fixture marker+身份、权限/链接/sparse布局；独立完整manifest/访问spy、跨卷与全部故障注入仍UNVERIFIED |
| [T04](tasks/T04.md) | M0 | DOING | nofollow anchored metadata、扫描代次/取消、仓库根与外祖先保护；mount/完整权限变化/外部读取spy仍UNVERIFIED |
| [T05](tasks/T05.md) | M0 | DOING | SQLite分页、硬链接聚合、quota、overflow rollback；clone/完整排序rendered/所有索引限额场景仍UNVERIFIED |
| [T06](tasks/T06.md) | M0 | DOING | 严格规则/保护策略、所有seed previewOnly；完整坏规则矩阵/网络观察未齐 |
| [T07](tasks/T07.md) | M0 | DOING | 生产只读CLI scan/plan/receipt边界；完整root外访问spy/无网络宿主未验证 |
| [T08](tasks/T08.md) | M0 | DOING | 中文原生真实Scan/Store连接、分页候选/大文件/UI标识；VoiceOver、长路径、三次导航订阅、主线程busy95%仍UNVERIFIED |
| [T09](tasks/T09.md) | M1 | DONE | 两个真实规则调查及previewOnly能力标注；调查DONE、准入0/2；活动worker完备覆盖unknown，AC-09 BLOCKED |
| [T10](tasks/T10.md) | M1 | DOING | 持久忽略、选择版本、筛选与失效；完整隐藏选择/组去重/重启UI矩阵未齐 |
| [T11](tasks/T11.md) | M1 | DOING | 纯Planner、规范hash、固定叶子、动作与TTL；Unicode/多item顺序/外来计划与所有异常向量仍UNVERIFIED |
| [T12](tasks/T12.md) | M1 | DOING | 预检owner/祖先身份/卷/rule/activity；scope外新增.git使旧计划拒绝；activity恒unknown保守拒绝；完整权限撤销/卸卷/cloud矩阵未验证 |
| [T13](tasks/T13.md) | M1 | DOING | 计划预览/预检/两动作差异与执行禁用；完整失效提示与确认全矩阵未齐；执行意图不能绕过Gate |
| [T14](tasks/T14.md) | M2 | DOING | internal fixture-only anchored stage/race probe；完整竞态/非协作写入与独立执行器审查未满足，AC-15整体UNVERIFIED |
| [T15](tasks/T15.md) | M2 | DOING | internal prototype journal、flock、fsync、一次itemID、unknown不重试；不是完整Transaction；ENOSPC/逐crashpoint子进程中断、断电持久性未验证 |
| [T16](tasks/T16.md) | M2 | BLOCKED | internal system Trash prototype与能力预检；系统Trash parent EPERM；成功Trash→receipt→恢复BLOCKED。早期自建对象遗留/收据不完整，见trash-probe-orphans.json，不能宣称未发生文件移动 |
| [T17](tasks/T17.md) | M2 | BLOCKED | internal固定stage普通叶子unlinkat，不删目录；真实规则准入0/2；完整Purge事务与非协作写入边界未满足 |
| [T18](tasks/T18.md) | M2 | DOING | internal stage无覆盖恢复、journal状态分类；未实现完整重启Recovery服务；系统Trash恢复、所有crashpoint BLOCKED/UNVERIFIED |
| [T19](tasks/T19.md) | M2 | BLOCKED | 生产App执行Gate=false，阻塞说明；真实执行/停止/结果/历史恢复闭环未完成 |
| [T20](tasks/T20.md) | M2 | DOING | 初步私有存储/export/忽略设置；history retention/pending保护/脱敏名称/宿主network观察UNVERIFIED |
| [T21](tasks/T21.md) | M2 | DOING | 当前fixture suites与三错误变体；完整正常/失败/取消/崩溃/恢复矩阵受M2 gate阻塞；局部变体不等整AC PASS |
| [T22](tasks/T22.md) | M2 | DOING | 两原生UI用例、三次固定50k APFS测量；主线程busy95%/VoiceOver/完整执行原生链未验证；ui-final.log外部Vanish/Zcode窗口打断失败保留，使用activate修复，不关闭其他app |
| [T23](tasks/T23.md) | M2 | DOING | 独立源码/文件边界/错误恢复review；M2关键条件仍未满足，不以工作中review替最终PASS |
| [T24](tasks/T24.md) | M2 | BLOCKED | 可启动Release制品、源码、构建运行手册已交付；制品交付成功；前置T23/M2关键条件不完整，不能称v1完成。macOS14/Intel/公证未验 |

实际检查：Swift package最终run exit0、24项实际测试+1项benchmark skipped（50k skipped，Trash只验证拒权限路径）；原生UI两项exit0；CLI缺root/非法purge拒绝与fixture before=after；三项错误变体均被断言检出；三次50k RSS约20.4MiB，主线程busy仍UNVERIFIED。低阶段/局部PASS不能提升整体AC。

完整矩阵见[acceptance.md](acceptance.md)，源码/规则/fixture hash与决定见[decisions.md](decisions.md)，独立审查见[independent-review.md](independent-review.md)。所有失败原始日志保留。

新源码副本`.local/source-reproduction`（无.build/.git）中swift test exit0，最终三次50k复测exit0；正式独立review APPROVE当前Gate=false交付，不构成M2/v1 PASS。
