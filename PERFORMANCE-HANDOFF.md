# 性能整合开发交接：重启后续接

更新时间：2026-10-13。**用户要求关机，任务主动暂停；未完成，不进入人工验收。**

## 先读这些

1. 本文件（恢复入口）。
2. [验收状态](docs/roadmap/performance-overview/implementation/ACCEPTANCE-STATUS.md)：18项AC的已知证据与缺口。
3. [PRD与技术方案入口](docs/roadmap/performance-overview/README.md)、[资源验收预算](docs/roadmap/performance-overview/04-ACCEPTANCE.md)。
4. [自检与修复记录](docs/roadmap/performance-overview/implementation/AUDIT-REMEDIATION.md)。
5. [详细历史](docs/roadmap/performance-overview/implementation/STATUS.md)：末尾更新优先，旧的running/PID不代表当前运行。

## 授权与工作边界

用户已授权开发全部计划功能、自检、按完成特性本地提交，并说另一AI已经结束。现在明确暂停，**本轮停止后台测量和验证应用，不再推进开发**。重启后收到继续指令再恢复。

以clean-my-mac为主工程；不改清理执行Gate、不操纵用户现有应用、不自动安装/发布/push。此前另一AI负责存储功能，保留其修改。存储状态文档还记录真实主盘TCC等待和索引预算失败，不能因用户说另一AI结束就把这些验收标PASS；只读性能整合不替代完整主盘验收。

## 当前代码与制品

- 最新功能提交：`1e60b8c perf: refresh metric labels at expiration boundaries`。本交接和状态更新随后另有文档提交，恢复时看git log。
- 性能实现：`Packages/Performance/`，四层Domain/Core/MacPlatform/UI，本地package接入单一原生App。
- App桥接：`App/LocalMacCleaner/PerformanceIntegration.swift`，单一CleanerModel、单一PerformanceController、菜单入口、路由与退出协调。
- 主App入口及Xcode项目已接入，但原工程很多文件仍未跟踪；不能用git checkout/reset/clean或git add .处理它们。源文件留在当前工作区，重启不会需要重新生成。
- 本轮仅更新根README末尾性能段，根README仍未跟踪；文档提交不会擅自收录另一AI全部存储源码。最终交付前仍需受控冻结完整可构建基线。
- 最新主App Release构建成功：`.local/build-performance-main/Build/Products/Release/LocalMacCleaner.app`，日志`.local/performance-overview/main-build-expiration.log`。
- 独立验证制品：`.local/performance-overview/LocalMacCleanerPerformanceReview.app`；bundle ID `com.localmaccleaner.performance-review`，已签名和verify，通过自建fixture运行；非安装版。
- 制品SHA256：ee5f3f60ee525cbe8fad2e6ec519ffae8eca90fe125ee23e92fefb333ab7f2c4。
- 源码/制品绑定清单：`.local/performance-overview/expiration-runtime-manifest.json`。恢复时先核对hash；变化后必须新构建，不继承旧运行证据。

## 已落地行为

- CPU、内存用量、启动数据卷可用空间；内存压力明确暂未取得，不用占用百分比替代。
- 进程CPU/RSS/Footprint，只读、搜索后排序裁剪前20，PID+startToken避免跨身份累计；缺失不假0、不用VSZ替Footprint。
- actor共享采样，默认2秒，概览/详情需求合并；隐藏释放订阅，旧代次结果丢弃，阻塞调用完成前不叠加采样。
- NSStatusItem+NSPopover概览，卡片跳转同一个主窗口；存储任务只读适配，不因打开概览发起扫描。
- 独立偏好、2/5/10秒刷新间隔、sleep/wake基线重置、退出协调；存储Gate保持false。
- 排行缓存已落地；本轮进一步把1Hz全列表Timeline改为显式过期边界刷新。新快照/搜索/排序仍即时刷新；停更后依然显示过期，未来时间也有恢复边界。未调整采样间隔或验收预算。

## 已验证与不能声称的结果

- 最新性能包Release **19项实际测试PASS**：`.local/performance-overview/release-tests-expiration.log`。覆盖计算/身份/共享/取消/设置/缺失历史值/排序缓存与过期时间表边界。
- 最新主AppRelease BUILD SUCCEEDED，独立验证制品签名verify通过。原生性能页可打开，1030左右进程进入采样。
- 旧版本原生50次存储/性能切换已记录；新版本未重新完成同系列RSS前后测量。
- 旧存储回归53reported、3opt-in skipped，即50项实际通过；本輪未重新跑最新存储源码回归，不能写当前全工程验收PASS。
- 上一排行缓存版本3个有效5分钟详情平均CPU **3.164%、3.442%、4.238%，均FAIL**（预算≤3%）。旧证据`resource-detail-cache.json/jsonl`和`detail-cache-runtime-sample.txt`保留。
- 本轮过期边界版本资源测量启动后因用户关机请求在85.24秒主动停止，18个样本，临时平均CPU约2.006%、末次RSS118.84MiB。**不足5分钟，不能判定预算PASS，也没有3组正式区间。** 证据`resource-detail-expiration.jsonl`和`resource-detail-expiration-paused.json`。
- 本轮collector已SIGTERM，工具会话78685终态exit143；原因是用户要求暂停，不是采集器故障。独立验证App PID81482已正常CmdQ退出；PID81482与collector82456均确认不存在。
- 没有停止另一AI遗留的真实扫描进程。重启后所有旧PID/临时路径都必须重新发现，禁止按旧PID操作。

## 重启后第一步

在`/Users/leozhou/git/clean-my-mac`执行（所有shell用rtk）：

```sh
rtk git status --short
rtk git log -5 --oneline
rtk proxy pgrep -fl 'LocalMacCleaner|collect_resources.py|xcodebuild'
```

读最新存储`docs/implementation/experience-v2/STATUS.md`和本功能AC状态。确认没有其他AI/测试活动；不碰其他应用。核对manifest的全部source hash及binary SHA；如已变化，重新运行性能19tests和独立Release构建。构建目录与其他工作隔离，不覆盖旧失败日志。

如需重建：

```sh
rtk proxy swift test --package-path Packages/Performance --scratch-path .local/build-performance-package -c release
rtk proxy xcodebuild -project App/LocalMacCleaner.xcodeproj -scheme LocalMacCleaner -configuration Release -destination 'platform=macOS' -derivedDataPath .local/build-performance-main CODE_SIGN_IDENTITY=- build
```

测试发现数/跳过数要实际记录。主App源由存储方更改过，不能用只编译PerformancePreview替代主App构建。

## 优先续接：完成新版本资源验收

1. 先使用新的独立验证App、自建fixture启动参数`-lmcUITest -lmcPerformanceDiagnostics`；不得扫描用户主盘来测试性能UI。若复制新制品，保持独立bundle ID，重新签名verify并生成manifest。
2. 通过原生CUA打开默认CPU完整排行；不要留搜索条件。CUA摘要后首次使用先`await cua.rewriteDocumentation()`，再按路径获取App。不可用osascript/JXA/CGEvent替代操作。
3. 从原生界面读取新LMC-UI目录，诊断文件在其父目录，更新`.local/performance-overview/active-diagnostics.json`的真实PID/path。旧路径不能复用；不要只挑最新临时文件冒认当前实例。
4. 确认诊断route=performance、subscribers=1、scanning=false、preparingIndex=false、默认2秒，然后只启动**一份**采集器：

```sh
rtk proxy python3 .local/performance-overview/collect_resources.py detail-expiration-reboot1 --subscribers 1 --route performance --duration 930
```

5. 用新模式名保留本轮暂停raw；该脚本jsonl是append，不要复用旧名称混合证据。运行过程中不切页/打开菜单/反复读AX干扰。保留工具session ID，只poll同一个collector；超时不是退出，不重复启动。
6. 完成后检查3个**实际≥300秒**区间；exit0不等于CPU预算PASS。详情≤3%，概览≤1%；不改采样间隔或放宽预算。失败继续sample定位，保留旧FAIL。
7. 然后同版本storage-only稳定基线、overview三组、both及hidden真机5分钟；诊断sequence停止且订阅归零，RSS新增≤50MiB；50切换稳定前后增长≤10MiB。关闭5秒内释放订阅，sleep/wake无跨间隔CPU，扫描并行可交互。

## 完整未完成项（不得缩掉）

- 新CPU修复正式三组资源复验；概览、隐藏、双入口、RSS基线/50次切换增量。
- 30次原生面板首画p95≤500ms。DidShow回调或AX往返耗时不能无说明当像素首画；按有效测量记录。
- 真实菜单图标打开/点击外部关闭、禁用恢复、间隔即时生效及重启偏好。
- 主窗口关闭后从菜单重开，各卡路由仍单窗口；无任务退出及索引准备/fixture扫描中退出协调。
- fixture扫描中关闭窗口不取消任务、重开摘要准确、手动取消；概览不发起扫描。
- 历史partial结果重启恢复、日期/读取失败/未知展示；存储方已新增restore，需同版本整条链验证。
- 键盘/VoiceOver/浅深色/长机器名/多屏边缘原生可用性，不能把AX标签当VoiceOver实测。
- 第三功能扩展已私有副本编译/回调验证，核心hash不变；是否需要补实际交互证据按AC收口。
- 当前存储回归及完整共享源码受控纳入Git；不提交.local、个人临时数据或未审查材料。
- 18AC同源汇总、PO任务完成证据、最终签名制品与用户人工验收入口。

只有全部必要验证收口才声明完成/请用户人工验收。最新19单元测试与短资源样本不是完整通过。

## 本地提交约定

用户允许每特性本地提交，不push。现有提交身份使用命令级`-c user.name=zhouchangju -c user.email=superzhou2007@126.com`，不改全局Git配置。只暂存明确职责文件。保留原工程未跟踪文件和其他AI改动；最终基线提交须单独审查。
