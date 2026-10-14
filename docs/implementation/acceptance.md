# 验收记录

2026-10-12最终交付快照；LMC-v0.1 / design 2。宿主macOS 27.0.1、arm64、APFS、Xcode 26.1.1、Swift 6.2.1；seed-1/schema1，软件/fixture逐文件hash见[decisions](decisions.md)。无Git commit。

完整AC状态按其全部独立判据判断；局部PASS保留明确范围，未运行断言保持UNVERIFIED。**M0/M1 DOING、M2/v1 BLOCKED**。所有真实变更仅自建fixture，早期Trash遗留确实发生且清单不完整。

| AC/TC | 阶段 | 完整状态 | 实际观察与剩余证据 |
|---|---|---|---|
| AC-01/TC-01 | M0 | UNVERIFIED | PASS分项：首次Release启动无scope且scan disabled；CLI缺root exit2；自建scope扫描成功。缺root外sentinel读取spy。 |
| AC-02/TC-02 | M0 | UNVERIFIED | PASS分项：nofollow symlink/根symlink/../拒绝，SSH/AI精确子根保护，repo/worktree根及子根保护。挂载边界、完整权限与外部sentinel访问spy未齐。 |
| AC-03/TC-03 | M0 | UNVERIFIED | PASS分项：fixture CLI before=after；50k真实scan/增量索引和计数。50k完整mtime/hash+write-spy与扫描中rendered增量断言未齐。 |
| AC-04/TC-04 | M0 | UNVERIFIED | PASS分项：fixture取消在2秒内停止、并发拒绝、新代次隔离。故意迟到回调完整事件日志未齐。 |
| AC-05/TC-05 | M0 | UNVERIFIED | PASS分项：4096B/sparse独立stat blocks、hardlink去重/聚合单测。所有unknown与父子独立计量矩阵未齐。 |
| AC-06/TC-06 | M0 | UNVERIFIED | PASS分项：partial/quota/未知聚合与真实UI列表。clone、不同口径排序rendered独立值矩阵未验。 |
| AC-07/TC-07 | M0 | UNVERIFIED | PASS分项：保护决策表、repo/worktree/AI容器保护；protect-priority错误变体exit1被4处断言检出。完整保护/ignore UI拒选矩阵未齐。 |
| AC-08/TC-08 | M0 | UNVERIFIED | PASS分项：严格bool/schema/非法root与bad revision保留测试；全部seed previewOnly且Gate=false。所有原始坏规则向量完整矩阵未齐。 |
| AC-09/TC-09 | M2 | BLOCKED | T09真实Xcode/npm格式与受控再生成调查完成（exit0），准入0/2。活动worker覆盖unknown、npm真实中断残留链未验。 |
| AC-10/TC-10 | M1 | UNVERIFIED | PASS分项：ignore持久化、选择版本和原生选择→计划。完整筛选隐藏/分组去重/重启rendered矩阵未齐。 |
| AC-11/TC-11 | M1 | UNVERIFIED | PASS分项：独立canonical JSON+固定SHA256向量、hash篡改与TTL单测。多item顺序/Unicode及外来执行计划完整边界未齐。 |
| AC-12/TC-12 | M1/M2 | UNVERIFIED | PASS分项：TTL过期边界/版本、真实身份/新仓库祖先使旧计划拒绝。完整scope权限撤销/卸卷/身份变化矩阵未齐。 |
| AC-13/TC-13 | M2 | BLOCKED | 普通文件Purge拒绝、两动作差异、生产Gate=false/原生确认禁用已验证。真实两动作确认执行未满足。 |
| AC-14/TC-14 | M1/M2 | UNVERIFIED | PASS分项：fixture链接/硬链/非持有根/身份拒绝；activity unknown预检保守拒绝。cloud/跨卷/active完整host矩阵未齐。 |
| AC-15/TC-15 | M2 | UNVERIFIED | PASS分项：真实fixture同步hook叶子/父替换、新文件保留、postmove错配不purge；identity-bypass变体exit1检出。不是完整生产动作最终竞态保证，非协作写入边界未满足。 |
| AC-16/TC-16 | M2 | UNVERIFIED | PASS分项：prototype flock/同itemID不重复调度。完整transaction双击、处理第二项前取消和rendered计数未验。 |
| AC-17/TC-17 | M2 | UNVERIFIED | PASS分项：durable journal/fsync、损坏尾部拒绝、unknown不自动重删、stage无覆盖恢复。逐crashpoint子进程终止/重启、ENOSPC、无journal无变更完整链未验。 |
| AC-18/TC-18 | M2 | UNVERIFIED | PASS分项：Trash estimate不算释放的模型断言；错误trash-is-release变体exit1检出。真实混合结果、net-space samples及rendered未齐，系统Trash完整链BLOCKED。 |
| AC-19/TC-19 | M0/M2 | UNVERIFIED | PASS分项(M0)：SQLite quota partial/overflow rollback、私有权限。M2 pending/history retention/journal不足不动目标未验。 |
| AC-20/TC-20 | M0/M2 | UNVERIFIED | PASS分项：无联网产品代码/本地store、仅metadata扫描与相对路径export实现。路径secret名称脱敏、mock network拒绝/宿主网络观察未验。 |
| AC-21/TC-21 | M0/M2 | UNVERIFIED | PASS分项：两真实UI测试，1000×680 dark keyboard search与1180×780 light真实扫描→选择→计划disabled。VoiceOver/长路径/三次进出/唯一AX全表与真实危险流程未齐。 |
| AC-22/TC-22 | M0/M2 | UNVERIFIED | PASS分项：新源码副本swift test、全新DerivedData Release构建、独立dist启动/CUA首次状态、ad-hoc codesign、≤100MiB和hash。完整clean-checkout app/test独立依赖审计未齐；不是AC25执行链。 |
| AC-23/TC-23 | M0/M2 | UNVERIFIED | PASS分项：最终代码三次固定50k APFS wall/RSS≤500MiB；主线程95%忙段≤100ms与UI扫描交互实测未运行。 |
| AC-24/TC-24 | M1/M2 | UNVERIFIED | PASS分项：预检真实新repo祖先使旧计划失效/fixture root身份拒绝。权限撤销/卸卷/重启/scope全部host矩阵未齐。 |
| AC-25/TC-25 | M2 | BLOCKED | 原生首次扫描→选择→计划真实链通过至执行disabled。Trash/Purge→结果历史→receipt恢复完整生产链未实现/未验；Gate=false。 |
| AC-26/TC-26 | M1/M2 | UNVERIFIED | PASS分项：严格decimal64/overflow、规则严格bool、阈值边界与canonical向量。引用缺失rootID/父子重复等全部人工坏JSON矩阵未齐。 |

## 实际命令与产物

- `xcrun swift test` exit 0：`.local/verification/swift-test-final.log`，24项实际测试+1项benchmark skipped；`fixed50kBenchmark`明确skipped，系统Trash测试只证明权限拒绝路径（BLOCKED）及stage恢复，不能记完整动作PASS。
- `xcrun swift test --filter CleanerPlatformTests` exit 0：`platform-tests-repo-ancestor.log`，7个实际平台case与默认跳过benchmark；scope在repo/src或worktree/src不能绕过保护。最后加入Preflight祖先复验见最终suite的`newAncestorRepositoryInvalidatesOldPlan`。
- 将Package/Sources/Tests/TestSupport/Resources/App/scripts复制到新建`.local/source-reproduction`（无`.build`/`.git`），在该目录 `xcrun swift test` exit 0：`source-reproduction-tests.log`，24项实际测试+1项benchmark skipped，benchmark skipped，Trash仅拒绝路径。证明源码在新路径可构建/测试；不是所有macOS兼容证明。
- `xcrun swift build -c release` exit 0：`swift-release-build.log`。
- `LMC_DERIVED_DATA=.local/clean-release-build zsh scripts/build-app.sh` exit 0：`clean-release-build.log`，全新DerivedData。复制`.app`到`.local/dist`；`codesign --verify --deep --strict .local/dist/LocalMacCleaner.app` exit 0；`open -n .local/dist/LocalMacCleaner.app` exit 0，CUA实际观察首次scope未选，scan/plan disabled。`release-manifest.json`记录bundle 1,474,715 bytes（du 1452KiB）、exe SHA256 `bc2928e205cb2586a926bcd08373583e7f4a9ea71ae54ad7502aeabf6554331c`、source hashes、环境。没有覆盖安装。
- `xcodebuild -project App/LocalMacCleaner.xcodeproj -scheme LocalMacCleaner -configuration Debug -destination platform=macOS -derivedDataPath .local/build -resultBundlePath .local/verification/ui-activate.xcresult CODE_SIGN_IDENTITY=- test` exit 0：`ui-activate.log/xcresult`，2项真实原生UI测试。最小1000×680 dark键盘搜索；1180×780 light真实scan→selection→plan→disabled。测试截图为布局/交互证据，文件fixture before/after为独立行为证据，不能互替。
- `python3 scripts/cli-smoke.py` exit 0：`cli-smoke.log`、`cli/results.json`，缺root命令exit2，fixture scan exit0，非法purge命令exit2；before=after。
- `python3 scripts/mutation-check.py` exit 0：`mutations-summary.log`、`mutations/results.json`。protect-priority、identity-bypass、trash-is-release三个独立错误副本分别测试exit1，实际被断言检出。错误实现未合入产品，不作为全AC PASS。
- `scripts/rule-admission-probe.sh` exit 0：`rule-admission/probe-result.json`内十条工具命令exit0；仅有限真实再生成，0/2准入。
- `xcrun swift test --filter CleanerExecutionTests` exit 0：`execution-authorized-tests.log`，10 tests。internal stage/race/journal/restore的定向fixture范围见[execution-probe](execution-probe.md)；系统Trash成功恢复仍BLOCKED。

所有上述日志/xcresult/JSON在`.local/verification/`。源码hash绑定和独立review见[decisions](decisions.md)、[independent-review](independent-review.md)。

## 50k实测（最终源码）

命令：`LMC_BENCHMARK=1 xcrun swift test --filter fixed50kBenchmark` exit 0（exec session 47777 poll确认），日志`benchmark-final-50k.log`。100子目录×500个1KiB普通文件，计数50102包含fixture自身边界；APFS allocatedFixture=204,800,000 bytes。cache=uncontrolled-warm，没有清系统cache制造冷启动。

| trial | wall seconds | RSS peak bytes | 主线程忙段 |
|---|---:|---:|---|
| 1 | 11.976054334 | 21,364,736 | UNVERIFIED |
| 2 | 11.014497208 | 21,397,504 | UNVERIFIED |
| 3 | 10.999772125 | 21,430,272 | UNVERIFIED |

RSS预算分项PASS；wall仅记录，不自造PRD扫描时间预算。AC-23整体UNVERIFIED：CLI进程RSS不能证明SwiftUI主线程95%忙段≤100ms。更早版本`benchmark-50k.log`三次12.001592/11.549169/11.964705秒，RSS21,397,504/21,495,808/21,512,192 bytes，原始保留不挑最快。

## 失败、修正与遗留

初始Swift/DIR指针编译失败、锚定根失败、保护遍历/索引失败日志完整保留。平台修复后定向测试及最终suite通过，失败记录不删除。`ui-final.log`2 tests/4 failures为最小窗口用例被外部Vanish/Zcode窗口打断；测试launch后activate本App修复，`ui-activate.log`2 tests通过；没有关闭其他应用。原失败不转换成PASS。

早期`execution-trash-tests.log`和`execution-trash-second.log`退出1；自建fixture对象实际移入系统Trash，后置父目录open EPERM导致不能验证/恢复。旧原型缺returnedURL持久记录且teardown删除journal，独立review旧run也可能额外遗留自建对象。`trash-probe-orphans.json`清单不完整，含null身份/原路径/未知返回位置；不能声称没有副作用或所有测试对象已恢复。后续修复先能力预检，拒权限不调用trashItem；返回URL先durable unknown记录，未对账不teardown。没有读/清用户Trash、没有提权、没有自动重试未知动作。

独立review最初3 HIGH已定向修复；最终判定APPROVE仅适用于Gate=false当前只读/计划交付，不能提升M2。完整Transaction/History/Recovery未实现，逐crashpoint子进程中断重启/ENOSPC/成功Trash收据恢复/非协作永久动作竞态/原生两动作历史恢复未齐。VoiceOver、主线程busy、最低macOS14、Intel、正式签名公证与宿主网络观察UNVERIFIED。用户现有文件未清理，没有提权、安装覆盖、发布或push。
