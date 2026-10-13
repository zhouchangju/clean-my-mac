# 验收计划：性能整合与菜单栏概览

全部软件验收初始UNVERIFIED。状态可为PASS/FAIL/BLOCKED/UNVERIFIED；跳过不是PASS。
每份证据记录源码版本或文件hash、环境、入口、输入、预期、实际、时间、命令/退出码、原始路径及检查人。日志与截图保持.local/verification/performance-overview/，不包含其他窗口/命令参数/私人内容；必要截图裁剪仅用于文档，原始证据本地保存。

## 验收案例

| ID | 前提与操作 | 独立通过判据 |
|---|---|---|
| PO-AC-01 | 用自建storage fixture记录基线；拆分后重新执行扫描、排序、取消、计划预览 | 规范化结果等价；保护/未知/执行限制不变；CLI行为保留 |
| PO-AC-02 | 真机点击菜单图标、点击外部、重新打开、设置禁用/恢复 | 面板可用；关闭后订阅释放；禁用后主窗口仍能恢复 |
| PO-AC-03 | 注入两轮已知tick；首次/计数倒退/唤醒；真机稳定自建负载 | 首次未知，已知向量计算正确，异常不假0；稳定读数对照说明成立 |
| PO-AC-04 | 注入内存used/total/压力缺失及权限失败，观察面板 | 用量与压力分开；没有百分比冒充压力；footprint缺失不冒充VSZ |
| PO-AC-05 | 读取当前数据卷并显示昨天partial扫描；模拟空间读取失败 | 当前空间来源/时间正确；历史扫描时间和partial仍可见；不启动扫描 |
| PO-AC-06 | 独立fixture含25个进程、同名项及缺失值；搜索排序 | 已知排行正确；前20只是展示裁剪；缺失值不排成高占用；搜索先于裁剪 |
| PO-AC-07 | 同PID不同startToken、token未知、进程退出、CPU计数回退 | 不跨身份累计；无token不算差值；历史裁剪；缺失显示正确 |
| PO-AC-08 | FakeSampler记录调用；面板/详情反复开关50次及双入口 | 系统只有一份循环；最多一个同类inFlight；最后release后无新周期 |
| PO-AC-09 | 主窗口已开/关闭时分别点每张卡片 | 聚焦同一目标窗口；正确路由；不重复服务/Store；设置可达 |
| PO-AC-10 | storage fixture扫描中关闭窗口/面板，重开概览，取消任务 | 扫描不意外取消；进度/取消中准确；摘要不触发扫描或动作 |
| PO-AC-11 | FakeClock推进超6/30秒，注入权限/未知/partial/失败 | 过期保留时间与状态；0与缺失区分；不同卡独立更新 |
| PO-AC-12 | 关闭主窗口，再从菜单打开；明确退出；有存储任务时退出 | 关闭窗口不退出入口；明确退出无采样残留；遵循既有任务中断规则 |
| PO-AC-13 | 自建临时偏好/索引；切换设置，重启App | 新设置独立持久；旧路径/计划/事务未被迁移；日志有界 |
| PO-AC-14 | 隐藏、概览、详情、双入口、睡眠恢复及扫描并行测量 | 满足下方资源预算；睡眠后不把长间隔算成有效CPU；无叠加 |
| PO-AC-15 | 用测试用Mock第三功能接入摘要/路由，再移除 | 不修改CleanerCore或PerformanceCore；依赖无环；无动态插件运行要求 |
| PO-AC-16 | 真机键盘、VoiceOver、浅深色、多屏边缘、长机器名 | 卡片/按钮可识别和操作；不截关键值；未知不用仅颜色表达 |
| PO-AC-17 | 只读入口/摘要全路径检查，注入未发现进程 | 无执行动作；unknown仍unknown；ExecutionGate不因整合改变 |
| PO-AC-18 | 独立构建目录构建，检查签名/identity，再独立路径启动 | 制品对应新源码；菜单/主窗口均可运行；原生关键AC齐全；未自动安装/发布 |

准确性实机检查只创建并结束自己的测试进程；不要操纵用户已有应用。CPU可用持续单线程已知负载并对照Activity Monitor稳定窗口；初始建议取10秒稳定区间、至少3组样本，系统CPU绝对差≤10个百分点、进程CPU绝对差≤15个百分点。此为待验证容差；噪声导致无法判断就标UNVERIFIED并记录环境，不能伪造精准。纯计算器使用独立手算向量，不能用被测实现生成expected。

## 资源预算与测量方法

以下为首版设计预算，不是实测。以交接后的同版本storage-only基线对照，记录机器、系统、进程数、采样间隔、采样工具及本应用PID。
- 面板缓存/加载首画p95≤500ms，30次原生打开；新CPU样本允许约两轮内形成，首次不填0。
- 两入口隐藏、停止完成后，60秒FakeClock无新采集；真实宿主采样5分钟，无性能周期工作；可有窗口系统正常事件和既有存储任务。
- 概览模式平均本App CPU≤1%（macOS进程口径，单核100%）；详情≤3%，每种模式5分钟3次。扫描并行另记录，不把扫描消耗归零。
- 性能新增模块相对storage-only稳定RSS增量≤50MiB；50次切换稳定后增长≤10MiB。历史最多60轮，流buffer最新1项，图标缓存有上限。
- 点击关闭后立即阻止新调度；已开始系统调用完成后不发布旧代次。5秒内释放订阅及可取消任务，若同步API超过5秒必须FAIL并调查，不能强行kill绕过。
- 扫描并行下主窗口与面板保持可交互，采用现有存储验收基线判据；采样超时跳轮，不创建排队积压。

预算失败需定位、调整实现或记录有理由的需求版本变更。不得通过删场景、缩范围或把fixture通过当宿主通过来关闭任务。

## 开发时检查入口

以下只作为后续建议命令，不是本轮执行记录：
```sh
swift test --package-path Packages/Performance --scratch-path .local/build-performance-package --filter PerformanceCoreTests
swift test --package-path Packages/Performance --scratch-path .local/build-performance-package --filter PerformancePlatformTests
swift test
xcodebuild -project App/LocalMacCleaner.xcodeproj -scheme LocalMacCleaner -configuration Debug -destination 'platform=macOS' -derivedDataPath .local/build-performance-overview CODE_SIGN_IDENTITY=- test
LMC_DERIVED_DATA=.local/build-performance-overview-release scripts/build-app.sh
```
实际测试名称由实施确定；不能0匹配exit0即PASS，记录实际发现/执行/跳过数量。系统采集宿主测试与纯fixture测试分开。UI测试可能无法直接控制菜单栏，允许授权的原生UI工具或手工走查并保留实际证据，不能用网页浏览器截图替原生App验收。
