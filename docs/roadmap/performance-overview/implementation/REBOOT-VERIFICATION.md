# 重启后的同源复验

2026-10-13；继续根目录交接。整体仍VERIFYING，未进入人工验收。

## 基线与范围

恢复时逐一核对`expiration-runtime-manifest.json`的31个source hash和binary SHA，全部一致；使用既有Release制品，不继承不同版本的运行证据。软件源码为1e60b8c，恢复时HEAD为e0f70f2（暂停文档提交）。独立bundle签名`codesign --verify --deep --strict`本轮exit0。

环境：Mac14,15，arm64，8逻辑核，24GiB，macOS27.0.1/26A434。使用自建fixture和`-lmcUITest -lmcPerformanceDiagnostics`，默认2秒采样；不打开清理Gate、不启动用户主盘扫描、不修改其他应用。恢复时另有存储版进程，保留不操作。

## 详情CPU预算：PASS（分项）

`rtk proxy python3 .local/performance-overview/collect_resources.py detail-expiration-reboot1 --subscribers 1 --route performance --duration 930`：工具session80399，exit0，实际930.023秒；PID5600为本轮私有实例，默认CPU排序、无搜索，788–840个进程，始终一个订阅，scanning/preparingIndex均false。

| 区间 | 实际秒数 | 平均CPU | RSS中位MiB | RSS最高MiB |
|---|---:|---:|---:|---:|
| 1 | 301.009 | 1.781% | 135.83 | 152.52 |
| 2 | 301.002 | 1.857% | 124.08 | 124.78 |
| 3 | 300.984 | 1.871% | 124.03 | 124.41 |

三段均满足详情≤3%。测量后原生默认完整排行仍可读取，并有CPU/RSS/Footprint真实值。随后CmdQ正常退出，ps确认PID不存在。

原始证据：`.local/performance-overview/resource-detail-expiration-reboot1.json/jsonl`；环境与版本绑定：`reboot1-environment.json`、`expiration-runtime-manifest.json`。之前缓存版三段FAIL与85秒暂停数据继续保留。当前较旧失败版本进程数量也减少，不能把前后差值全归因于代码。

## 后续验证

冷启动同源fixture存储页基线：session22385、PID21141，`storage-expiration-reboot1 --subscribers 0 --route storage --duration 310` exit0，实际310.013秒；有效区间300.994秒，CPU0.063%，RSS中位94.75MiB，最高127.84MiB。全程subscriber0/sequence0，无性能周期工作。原始`resource-storage-expiration-reboot1.json/jsonl`。

详情三个区间RSS中位相对基线分别增加41.08/29.33/29.28MiB，稳定中位增量满足≤50MiB；启动瞬时最高增量57.77MiB，不能称全部时点都≤50MiB。跨实例同源对照，不替代50次切换前后同实例稳定增量。

## 当前回归

- `rtk proxy swift test --package-path Packages/Performance --scratch-path .local/build-performance-package -c release`：session96207，exit0，19项实际PASS，无skip。日志`release-tests-reboot1.log`。
- `rtk proxy swift test -c release --scratch-path .local/build-cleaner-reboot1`：session39059，exit0，57 reported/3 opt-in skipped，即54实际PASS。日志`cleaner-regression-reboot1.log`。系统Trash仍errno1/permissionDenied；PASS仅证明拒权限后的fixture staging恢复，没有系统Trash写入，M2仍BLOCKED。

## 原生控制阻塞

基线结束后CUA对本App的click/getAXState/path与bundle-ID getApp均失败：`cgWindowNotFound`；重建CUA会话、重新激活App后同样失败。原生工具应用清单仍报告running；本App诊断仍visibleMainWindows1、subscriber0、sequence0，进程仍存活。因此只确认原生控制不可用，不能推断App崩溃或锁屏。已询问用户当前显示器/锁屏/远程桌面状态，未回答不能替用户选择。

两个collector均exit0，无活跃采集。概览/双入口/隐藏及菜单等后续原生验收受此阻塞，保持UNVERIFIED；没有改用osascript/JXA或伪造交互。

收尾：无法使用CUA正常退出时，fresh ps核对PID21141的完整私有制品路径/fixture参数；诊断确认无扫描、无准备、零订阅后，只对该私有实例SIGTERM并确认进程不存在。不是正常退出验收PASS，也未停止PID582存储版。`reboot1-cleanup.json`记录精确身份及终态。再次核对31个source hash仍一致。

尚待概览/双入口/隐藏、同实例50切换RSS增量、30次像素首画、菜单/设置/窗口生命周期/fixture任务、历史恢复、辅助功能/多屏、共享可构建基线及最终18AC收口。详情分项PASS不等AC14或全部功能PASS。
