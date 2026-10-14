# 决策、依据和待验证项

版本v0.1，2026-10-12。目标是防止后续AI把研究推断、设计建议与用户决定混成事实。

## 1. 已确认输入

| ID | 来源 | 内容 | 范围 |
|---|---|---|---|
| U-01 | 用户原始目标 | 本机空间有限，希望理解CleanMyMac机制后自研个人Mac清理软件 | 本地个人使用 |
| U-02 | 本轮请求 | 编写PRD、设计、任务等本地Markdown，并提供其他AI开发Prompt | 本轮只编写文档 |
| U-03 | 本轮偏好回复 | “按原生 macOS 方案（推荐）” | 问题明确包含Swift/SwiftUI、中文、本地运行 |
| R-01 | [第二轮汇总](../round2-summary.md) | 规则/保护/计划/计量有可复核静态依据 | 不是LMC已实现/已通过证据 |

## 2. 工程决策

以下是授权设计范围内采用的基线，不声称用户逐项确认。未来修改必须写明原因、受影响FR/AC和替代验证；不得静默降低数据保护。

| ADR | 决策 | 理由/代价 | 何时重开 |
|---|---|---|---|
| ADR-01 | Swift6 + SwiftUI/AppKit，macOS14+，arm64首发 | 用户已选原生；减少运行时体积；只验证宿主不等最低版本实测 | 用户要求Intel/跨平台 |
| ADR-02 | 根Swift Package内核 + Xcode App/UI tests | 核心可测，原生用户路径可实测；有两个构建入口需维护 | 有更简单且等价可验证的工程形式 |
| ADR-03 | 本地分发、非App Sandbox、普通用户权限 | 覆盖本地存储管理；仍受TCC与应用内部范围限制；不支持商店直接发行 | 要求App Store或更强隔离 |
| ADR-04 | M0扫描→M1计划→M2执行，M3独立 | 逐步验证高风险边界；M0不能冒充具有清理能力的v1 | 用户调整首版范围 |
| ADR-05 | 自研严格规则；不加载专有解码数据库 | 避免继承未知匹配语义和坏关联；初始规则数量较少 | 有独立授权/标准化规则来源与单独设计 |
| ADR-06 | 默认不勾选；protect优先；unknown拒绝执行 | 更可解释，牺牲部分一键便利 | 用户明确更改产品风险偏好，且有证据 |
| ADR-07 | v1无root/helper、无后台守护/联网 | 适合个人首版、减少权限和资源占用；存在扫描盲区 | 明确高价值功能必须依赖它们 |
| ADR-08 | 永久动作只针对已准入的普通单链接叶子，先staging/journal | 限制影响范围、支持对账；实现复杂，须技术探针证明 | 平台实验否定方案时重新设计，不能径直降级remove递归 |
| ADR-09 | SQLite索引+JSON规则/设置/计划+事务日志 | 分页与大目录资源可控；需要schema迁移和崩溃测试 | 规模实测证明更简单结构足够 |
| ADR-10 | 500MiB RSS/100MiB app/50k样本等初始预算 | 给AI可验证目标；预算是设计值非基准事实 | 实测并说明成本后调整 |

默认参数：并发2（1–4）、批提交200条/200ms、buffer4096、plan TTL10min、大文件阈值512MiB、npm tmp候选年龄7天、索引软限250MiB。它们集中配置并进入测试边界，不散落魔法数字。

## 3. 研究事实如何进入产品

| 已观察事实 | 设计采用 | 尚不能推断 |
|---|---|---|
| 扫描主链把规则、计量、结果模型分开 | Core分层与统一Planner | 完全重现原产品所有扫描覆盖 |
| 规则库有保护/忽略/深入扫描及应用关联 | 不将命中等同删除；输出理由 | 每条专有记录都适用当前本机 |
| 普通缓存和Gradle默认值相反 | 每规则独立建议与能力 | 缓存默认安全可删 |
| 模型使用全局引用和独立计划 | M3设计参考，v1不贸然执行 | 已知运行中模型/跨组优化全部行为 |
| 原产品保护函数和Trash/直接删除并存 | 自研明确动作及journal | 原产品无误删，或自研已安全 |
| 原产品UI主页可见、扫描结果未跑通 | 原生导航和流程参考；结果页独立设计 | 已像素复刻或实测完整交互 |

## 4. 外部主要依据

查阅日期：2026-10-12。只用于平台能力和语义，不替代编译/运行证据。JS动态文档读取受限处以索引说明为依据，具体签名/availability在T01与平台任务用SDK核对。

- [SwiftPM 官方文档](https://docs.swift.org/main/documentation/packagemanagerdocs/)：package/build/test职责，支持核心与应用分开组织。
- [Swift Testing](https://developer.apple.com/xcode/swift-testing)：原生测试工具；采用Swift Testing/XCTest分工是本项目决策。
- [FileManager](https://developer.apple.com/documentation/foundation/filemanager)：文件操作平台接口，不提供完整应用级恢复协议。
- [URLResourceValues](https://developer.apple.com/documentation/foundation/urlresourcevalues)：文件/卷属性、allocated size等；不代表准确独占回收量。
- [Apple 存储空间说明](https://support.apple.com/en-us/102624)：移入废纸篓不会在清空前释放空间。
- [App Sandbox 文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)：未来sandbox路线的权限背景；本版本不据此承诺全盘访问。
- [npm cache 官方说明](https://docs.npmjs.com/cli/cache/)：默认POSIX cache与`_cacache`的缓存用途；并未证明本项目的年龄阈值、tmp布局及删除策略，RULE-DEV-02仍需T09按版本核验后准入。

## 5. 待验证与后续研究

| 问题 | 负责人/解决方式 | 是否阻塞 |
|---|---|---|
| staging/目录句柄能否覆盖指定竞态与恢复要求 | 开发负责人，T14/AC-15确定性探针 | 阻塞M2，不阻塞M0/M1 |
| 至少两条真实规则是否可重建且可判断活动状态 | 规则开发者，T09准入记录 | 阻塞M2；失败保持previewOnly |
| 原产品完整规则优先级、sentinel、在线更新 | 定向逆向；v1使用独立策略不冒充还原 | 不阻塞当前独立实现 |
| APFS clone/快照精确独占回收量 | 平台测试，无法得出即unknown/estimate | 不阻塞估计UI，禁止精确保证 |
| 最低系统/Intel/正式签名公证 | 用户范围决定及相应环境验证 | 当前宿主个人构建不阻塞，公开分发另定 |
| 本机可实际释放多少 | 用户使用真实扫描后测量；当前未测 | 不阻塞开发，禁止预先承诺 |

## 6. 当前文档交付状态

本轮仅编写这套Markdown；没有生成应用源码、执行构建/软件测试、清理真实文件或发布。版本/工具链只做了只读查询。后续AI应另建 `docs/implementation/` 记录实际执行，不将本表转换成软件已通过状态。
