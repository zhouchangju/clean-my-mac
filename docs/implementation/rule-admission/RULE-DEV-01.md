# RULE-DEV-01：Xcode 中间构建产物

状态：previewOnly；版本范围仅实测 Xcode 26.1.1 (17B100)，其他版本 unknown。默认根由生产 home-relative `Library/Developer/Xcode/DerivedData` 与所选 scope 求交集；只允许单工程 `Build/Intermediates.noindex` 的普通后代，不接受改全局 HOME。调查使用显式 `-derivedDataPath` 指向自建0700 fixture/profile，不据此宣称用户当前默认目录配置已核验。

用途/格式：真实 xcodebuild 生成 `Probe.build/Debug/Probe.build/Objects-normal/arm64/main.o` 及辅助文件；39个中间普通叶子观察。`xcodebuild -help` 官方本机工具说明提供 `-derivedDataPath` 与 build action。可重建证明仅覆盖 main.o：先 build/run、将 main.o 无删除移至自建 staging、重新 build/run，SHA256相同。日志含重编译命令；不推断所有中间产物/其他工程都同样低成本。

保护反例：源码、Archives、Build/Products/dSYM 在边界外；它们不是候选。fixture保留相应 sentinel；产品排除处理尚需独立 RuleEngine 测试。目录、symlink、硬链接、云/跨卷、身份未知一律不授予执行。不得选整个 DerivedData、工程目录或删除目录。

活动检查：Xcode、xcodebuild、XCBBuildService、clang、swift-frontend 等已知进程可构成 busy 证据；无命中不等 inactive（还有后台索引、helper、第三方构建 worker、进程启动竞态）。枚举失败、未知worker、未知版本 → unknown。当前没有足以证明 inactive 的 adapter，故 previewOnly。

允许动作：仅分析/预览；不得 Trash/Purge。未来准入还需动作特定 evidence、单链接普通固定叶子、身份/祖先/卷及事务约束；名字匹配不能授权。

失败恢复：本次在已有再生成文件时不覆盖源路径，原对象移至自建新恢复路径并核对hash。产品方案应留 staged receipt、无覆盖恢复/人工冲突指引；永久删除无恢复。未执行 crash/journal 或产品恢复验收。

原始结果与命令见 README 和 probe-result.json。AC-09 / M2 BLOCKED；bounded fixture rebuild 已实际运行，不等于规则准入 PASS。
