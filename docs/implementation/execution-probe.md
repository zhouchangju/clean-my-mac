# M2 execution probe / fixture-only prototype

2026-10-12。生产 `ExecutionGate` 未修改，执行始终关闭。此报告不将内部 fixture probe 当作 M2 准入或原生全链完成。所有入口 internal，仅 `@testable` 能使用；创建时传入 Fixture 持有的 token + root device/inode，检查 root 0700、owner、marker 的 no-follow 普通单链接身份/token。任意本人目录、Home、软链接根、错 token、换根拒绝。Fixture 仅新增创建时身份的只读 getter。

## 实际验证

命令 `xcrun swift test --filter CleanerExecutionTests`。最新日志 `.local/verification/execution-authorized-tests.log`：构建及测试退出 0，10 个测试。绑定源码 SHA256：`.local/verification/execution-source-sha256.txt`；宿主 `.local/verification/execution-host.txt`。所有文件变更仅本次 Fixture 根；独立 CryptoKit hash / Data / 文件存在性与目录快照校验，不依赖 executor 返回成功作为唯一 oracle。

- T14 定向 isolated PASS：从持有根逐级 `openat(O_DIRECTORY|O_NOFOLLOW)`，验证祖先 device/inode；普通叶子单链接/owner/mtime/ctime/size；同卷 0700 stage；`renameatx_np(RENAME_EXCL)`，移动后身份/大小/mtime检查。同步 hook 覆盖叶子替换、父目录改名再软链交换、新文件不扩选、移动后写入错配、恢复同名冲突。错配留在 stage、不进行永久处理。AC-15 整项仍 UNVERIFIED；仅覆盖记录中的 hook 时点。
- T15 prototype 定向 PASS：独占 `flock`，journal 0600/目录0700，创建及追加 `fsync`，相同 itemID 拒绝再次调度，损坏 JSONL 尾部拒绝对账，intent/unknown 不作为重删指令。这不是完整事务执行器；未验证断电持久性、quota/ENOSPC 或子进程 crashpoint。
- T17 prototype：固定 stage 普通叶子 `unlinkat`，删除目录树接口不存在；独立验证未选文件保留。真实规则 AC-09 0/2 准入，因此 T17/M2 **BLOCKED**，不称 Purge 准入 PASS。非协作同 UID 写入者仍可写打开的 inode；采样 identity 不能证明动作间隔没有变化。
- T18 prototype 定向恢复 PASS：stage 恢复 `RENAME_EXCL`、祖先身份检查、同名不覆盖；已写 journal 的状态纯分类，不自动重删。未实现完整重启恢复服务。

## 系统 Trash 实测失败与补救

第一轮 `.local/verification/execution-trash-tests.log`（9 tests，退出1）、第二轮诊断 `.local/verification/execution-trash-second.log`（1 test，退出1）：系统 `trashItem` 移走本次自建测试文件并返回 URL；打开返回父目录失败，第二轮明确 errno=1/EPERM。没有申请/提升权限。第一轮旧原型未先记录返回 URL，fixture teardown 又删除原路径 journal，这是实际缺陷，日志保留。第二轮可确认返回路径的元数据记录在 `.local/verification/trash-probe-orphans.json`；无法读取身份、无法安全恢复，保持 interruptedUnknown。第一轮返回位置缺口如实 null；未扫描或清空系统 Trash，未操作任何现有 Trash 文件。遗留仅自建测试文件。

修复后：先进行只读 Trash 能力预检，失败时不调用 trashItem；系统返回 URL 在后续身份验证前先写 durable `trashReturnedUnknown`；测试一旦开始系统 Trash 动作且不能恢复，禁止 fixture teardown，保留根/journal。最新日志明确 `BLOCKED ... errno=1; fixture stage restored; no system Trash write`，10 tests 的 PASS 只证明拒绝路径，**不证明 Trash + receipt 恢复成功**。returnedURL 包含 file-reference 时先转 filePathURL，不放松 no-follow。

T16/系统Trash恢复仍 **BLOCKED**。不能靠关闭权限边界或 mock 冒充通过。即使系统 Trash 成功，路径 URL API 本身仍有同 UID stage 路径替换边界；生产 gate 继续关闭。

## 未运行及阶段边界

子进程 crashpoint（journal 前、stage 后、purge 后 commit 前）UNVERIFIED；无 throw 模拟冒称真实崩溃。跨卷、云占位、永久删除完整事务、取消、原生执行/历史/恢复 UI 链、系统 Trash 完整恢复、AC-25 UNVERIFIED。journal 故障之后已发生外部动作的 receipt 持久化无法保证，生产使用之前仍需独立设计与验证。

当前交付是可审查源码 + 实测 fixture 探针，不是已完成的 M2。阻塞为真实规则准入、系统 Trash 可验证能力、完整事务与 crash recovery，以及非协作写入边界。保持清理禁用。
