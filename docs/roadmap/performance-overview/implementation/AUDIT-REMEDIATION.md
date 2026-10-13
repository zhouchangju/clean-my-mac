# 有证据的自检与修复循环

## 基线审查

详情资源采集在约532秒后因diagnostic source stale停止；PID28834仍存活，日志随后恢复，存在22.27秒和18.81秒间隔。没有假定退出，没有重启collector。同期另一AI有live原生UI test，主机环境干扰存在，但不能单独归因为它。

第一段实际300.90秒详情平均CPU5.653%，高于3%设计预算；RSS中位107.31MiB、最高123.45MiB。证据resource-detail-partial.json、resource-detail-failure.json、jsonl。三组验收未完成，CPU项FAIL。

运行时sample PID28834 3秒（detail-runtime-sample.txt）显示TimelineView每秒刷新调用ProcessRanking.rows，主线程747份栈落在该路径；这不是必要的每秒完整样本排序。

## 修复计划与实现

仅在PerformanceController缓存排序后前20行；新快照、搜索或排序变化时失效/重算。时效时钟仍每秒更新，但复用排行。缓存字段ObservationIgnored，避免渲染时产生观察状态反馈。每个接受的新快照都清缓存，包括同sequence但进程集合已清空的快照。没有改存储模块或资源预算。

另一次宿主CPU校准测试发现原ratio读数时间窗包含全进程枚举尾部开销：采用getrusage在两次采集前后作独立上下界，仍验证单位换算，不放宽数值或跳过测试。原失败release-tests-ranking-cache.log保留。

## 验证证据

Release 18项实际测试通过（release-tests-ranking-cache-bracketed.log），新增60次时效重绘只计算一次、搜索/排序变化再算的回归。主App新构建正在独立目录执行，尚未部署新binary。

## 复审与剩余边界

排序缓存代码失效条件已审读；18测试证明局部行为，不证明CPU预算已恢复。必须绑定新源新binary，重做三个有效5分钟区间，检查日志更新间隔及CPU/RSS。尚未查明所有旧日志间隔原因。没有采用打分代替功能验收。最终18AC及原生隐藏/资源/辅助功能仍未全部完成。

## 第二轮修复：按过期边界刷新

2026-10-13续接：缓存版三组有效5分钟CPU为3.164%、3.442%、4.238%，仍FAIL。新采样栈保留SwiftUI布局刷新路径。详情和概览将1Hz周期Timeline替换为显式时间表：新快照由Observation刷新；时间表只安排当前可见值的过期边界及未来测量时间恢复边界。使用实际Date格式化，不使用提前的计划时间。未改变两秒采样或CPU预算。

新增边界测试覆盖正常、已过期、历史值、未来时间、未知；Release19项实际测试通过（release-tests-expiration.log）。自审检查时间表去重、有限终止及新样本重建。主App构建与同源运行时资源验证继续进行，旧FAIL不转为PASS。
