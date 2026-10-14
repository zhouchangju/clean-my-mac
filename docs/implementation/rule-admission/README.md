# T09 规则准入调查

2026-10-12；输入 LMC-v0.1 / development 03、05、06、08。阶段 M1。

**调查完成；准入通过 0/2。两条规则均 `previewOnly`。M2 的 AC-09 为 BLOCKED。**

这不是准入失败后降低标准：契约明确要求相关 worker 无法识别、版本未知、枚举失败均为 unknown；不能由没看到 Xcode 窗口或进程列表无命中推断 inactive。当前只能提供进程采样，无法证明相关 worker 的完备覆盖，也不能锁住第三方程序防止采样后启动。因此不能升级 Trash/Purge 能力。

| 规则 | 调查结论 | 再生成范围 | 独立阻塞 |
|---|---|---|---|
| RULE-DEV-01 | previewOnly | Xcode 26.1.1 的自建 C 工程，中间目录一个真实 `.o` 移到自建 staging 后再次 build，SHA256 相同，二进制前后运行成功 | 所有 Xcode/构建 worker 活动覆盖未证明；整个中间目录各格式/产物未逐个证明 |
| RULE-DEV-02 | previewOnly | npm 11.19.1 自带 cacache 20.0.4 的 tmp.mkdir + put/get，8天的自建普通暂存叶子移走后，用同 API 生成同内容新 tmp 叶子；恢复原叶子 | 留存的中断 npm install tmp 未真实验证；活动 npm/node/worker 覆盖未证明；7天仅设计阈值 |

## 实际证据

命令 `scripts/rule-admission-probe.sh` 退出 0；内部十条工具命令均退出 0。宿主 macOS 27.0.1 (26A434) / arm64 / APFS；Xcode 26.1.1 (17B100)、npm 11.19.1、Node v26.10.0。

- `.local/verification/rule-admission/probe-result.json`：真实命令、退出码、0700独占 fixture 根、卷/inode、普通叶子前后 hash 与恢复。
- 同目录 `xcode-build-before.log` / `xcode-build-after.log`：真实 build；`xcode-run-before.log` / `xcode-run-after.log`：程序运行。
- `npm-cacache-before.log` / `npm-cacache-after.log`：本机已安装 npm 的 cacache API 执行，无依赖安装。
- `protection-and-activity.json`：保护反例布局、独立 lstat/age oracle；产品 RuleEngine 的保护断言仍 UNVERIFIED。
- `source-hashes.json` 与 `*.source.txt`：本机已安装 npm 源码快照/hash；不读用户 npm 配置。

fixture 留存供复核，脚本不自动递归清空。只移动两个自己生成的普通文件；未操作用户真实缓存/会话/配置，不改 HOME、不提权、不安装依赖、不关闭应用、不终止其他进程、不联网、不 push。脚本的 staging/恢复是调查动作，**不是 CleanerExecution 的 AC-17 验收**。

过程中的只读定位错误：先猜测 `.local/lib/node_modules/npm` 路径，ls 退出 1；依据 npm symlink 改为 `.hermes/node/lib/node_modules/npm`。本机 npm 未附 docs Markdown，rg 返回缺失，改以安装源码核验。没有用错误结果宣称证据存在。

## AC 状态

- T09 / M1：DONE（调查、能力标注与阻塞已记录）。是否可执行没有被冒充为任务完成条件。
- AC-09 / M2：BLOCKED。两条均未准入，不能达到 ≥2。
- AC-08：这里只提供调查依据，产品 schema 验收 UNVERIFIED。
- 活动状态反例：采样 ps 退出 0，51 个 node、0 个 xcodebuild；npm 为 busy 保守拒绝，Xcode 无命中仍 unknown。未制造或终止其他 app，未证明完备 activity detector。
- 保护/恢复反例：调查 oracle 检出 symlink、nlink>1、新 tmp 年龄不足；Xcode 已再生成位置视作冲突，不覆盖，新位置恢复原 `.o` hash 一致。产品保护、无覆盖恢复、journal、race、崩溃链仍由其他任务验收。

下一步 Planner/Preflight 应消费 previewOnly，返回明确理由 `ruleNotAdmitted` / `activityUnknown` / `ownerActive`。不得通过 UI 手选绕开。真正完成 M2 需补足每条规则的 worker 覆盖与 fail-closed 状态证据，或由有证据的新规则替代；不能为数量改变本准入结论。
