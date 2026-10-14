# Local Mac Cleaner 使用与构建

当前是本地扫描与计划预览开发版，**不是完成验收的 v1**。真实清理执行始终关闭。Swift/SwiftUI 中文原生应用，无联网、root helper、第三方运行时或遥测。

## 启动

```sh
open -n .local/dist/LocalMacCleaner-v2-wait.app
```

不需要复制到 Applications。已有真实扫描时先等待它结束并退出旧副本，再启动新版，避免两个副本同时使用真实索引。当前新版等待提示制品已在自建目录原生启动验证；其默认真实索引启动与完整主盘覆盖仍未验证。首次启动默认选择内置启动盘的数据卷，但不会自动扫描。点击「扫描内置存储」即可开始；也可以直接扫描我的文件、下载文件夹，或自选目录。权限不足时显示部分结果，不修改系统权限。应用包和代码仓库可只读计量，其后代仍不可清理；凭据、会话、云同步目录、系统边界及本应用状态不深入。

存储看板显示卷容量、已扫描分配、分类及整理建议；点击分类进入详细审阅。空间地图与列表使用同层数据，目录双击下钻、面包屑返回；列表支持搜索和分配／逻辑／修改时间排序。面积仅代表本页前12项的已知去重计量，未知项保留在列表。大文件阈值 512 MiB。逻辑大小不是磁盘占用，分配大小不是精确可释放量。硬链接只在汇总中计算一次。部分目录不能读取时，未知不会显示成0；保护子树没有展开也会使覆盖不完整。符号链接不遍历，外置/跨卷不执行。

每轮扫描选择为空。重启后只恢复最近保留的终态结果供浏览，显示日期；旧结果不能勾选或生成计划，需重新扫描。缓存规则目前全部「仅预览」。大文件可明确勾选并生成 Trash 计划，预检会说明无法确认使用状态等拒绝理由。动作、选择、忽略或扫描变化后旧计划作废；计划 TTL 为10分钟。移入废纸篓通常不释放空间，永久删除无法撤销；目前两种执行均禁用。

## 可复现构建

宿主验证：Apple Silicon / macOS 27.0.1，Xcode 26.1.1，Swift 6.2.1。部署目标 macOS14，仅当前宿主验证，Intel/最低系统/正式签名公证未验证。无全局生成器或 npm/Python 运行依赖。

```sh
xcodebuild -version
xcrun swift --version
xcrun swift test
xcrun swift build -c release
zsh scripts/build-app.sh
```

App 构建输出 `.local/build/Build/Products/Release/LocalMacCleaner.app`。可以给 `LMC_DERIVED_DATA` 指定新目录以验证 clean build。本轮在旧共享构建缓存中发生过SIGSEGV，干净构建未复现；复验建议使用 `xcrun swift test --scratch-path .local/fresh-package-build` 和独立DerivedData，不把缓存失败丢弃或冒充已定位的根因。构建为 arm64、ad-hoc 签名、Hardened Runtime；不绕过 Gatekeeper/SIP，不自动安装。

原生 UI 测试（会启动本应用并创建独立私有稀疏文件夹，不使用你的现有文件）：

```sh
xcodebuild -project App/LocalMacCleaner.xcodeproj -scheme LocalMacCleaner -configuration Debug -destination 'platform=macOS' -derivedDataPath .local/build CODE_SIGN_IDENTITY=- test
```

固定50k性能检查：

```sh
LMC_BENCHMARK=1 xcrun swift test --filter fixed50kBenchmark
python3 scripts/mutation-check.py
python3 scripts/cli-smoke.py
```

Python仅为开发验证脚本依赖，不是app运行依赖。`rule-admission-probe.sh` 仅在已装 npm 的本机进行自建工具产物调查，不安装包。

## CLI

```sh
.build/release/lmc scan --root /明确选择的目录 --json
.build/release/lmc plan --scan UUID --selection UUID,UUID --action trash --json
.build/release/lmc inspect-receipt 本地收据.json
```

不传root报错，不默认扫Home；没有生产 delete/purge/execute 命令。CLI结果写私有本应用索引，plan不能导入外部文件作为执行授权。

## 隐私与剩余限制

私有索引位于系统解析的 `~/Library/Application Support/LocalMacCleaner/`，目录0700、索引0600，索引上限1GiB，并在每批写入与提交前通过原生statfs保留至少1GiB可用空间；读取失败或余量不足会停止扫描。当前单worker顺序枚举/200条提交，设置并发尚未实现。历史90天/1000次与明细30天的维护服务、完整事务/重启恢复、用户导出、VoiceOver、主线程忙段、跨卷/云占位实机覆盖等未完成，详见[验收矩阵](acceptance.md)。

M2 阻塞：两条规则准入0/2，无法可靠确认活动worker；系统Trash父目录EPERM，完整恢复未通过；竞态probe不证明同UID非协作写入隔离；子进程崩溃点及完整原生执行恢复链未完成。不能通过设置或启动参数打开执行。

早期内部Trash探针存在已记录缺陷：仅自建测试文件移入系统Trash后无法读取返回目录，部分返回位置未保存；可能留下额外测试文件。已修为动作前权限能力拒绝和durable返回记录，但无法替早期结果补造身份。遗留记录 `.local/verification/trash-probe-orphans.json`，不扫描/清空已有Trash、不自动恢复不确定项。原生UI测试失败自动附图可能包含其他桌面窗口，全部证据保留本地，不应对外分享原始xcresult。


## 2026-10-13 体验 v2 与实际限制

参考[官方逐页研究](experience-v2/cleanmymac-official-research.md)和[本机实际页面观察](experience-v2/cleanmymac-runtime-research.md)改善入口和结果组织。最新状态见[体验v2验收](experience-v2/ACCEPTANCE.md)，不能用旧版本的测试证明新版本。

内置存储实际范围为`/System/Volumes/Data`；不等于所有APFS卷、只读系统卷和快照。权限、保护、挂载边界与资源预算均可能使结果不完整。旧250MiB紧凑版实际主盘扫描在981096项时因索引预算停止，完整范围验收FAIL。新版依据ADR-10-R1设1GiB上限与1GiB可用余量保护，已原生启动并恢复旧部分结果；新版主盘扫描scan48FA94B9-4983-445B-A92D-150EC5544434于2026-10-13 16:46 CST开始，尚未终态，完整范围验收UNVERIFIED。不能从fixture或启动成功称整盘已完成。

应用会在新扫描前专属维护自己的旧扫描索引：保留摘要，回收终态明细并压缩；活动扫描或任何计划／执行／收据／staging数据存在、链接或无法读取时不回收。此维护不访问或删除扫描目标文件。配额和写入失败会报告原因，未成功计量显示未知，不显示为“整个目录为空”。

## 系统权限等待（2026-10-13 17:15 CST）

当前真实scan48FA94B9/PID62394在357612项时等待macOS媒体资料库权限提示，未终态；这次运行的是resource旧制品3a30，新wait制品4e0已补30秒无进度提示。权限由你自行处理，选择不允许应作为权限缺口继续；应用和开发代理不自动授予权限。CUA工具以安全原因不能访问系统UserNotificationCenter，需本人处理系统提示。不能从CPU0或等待时间推断扫描已完成，也不能通过重启或虚构终态掩盖等待。

扫描使用同步原生文件系统调用；停止请求需等当前系统调用返回后生效。新提示的准备阶段停止与32项真实自建目录扫描已有原生证据，但真正阻塞openat的取消仍未验证。完整主盘、VoiceOver、主线程P95以及M2清理恢复继续保持UNVERIFIED/BLOCKED；详见experience-v2/ACCEPTANCE.md。
