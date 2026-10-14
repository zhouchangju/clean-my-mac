# 真实整盘扫描性能问题与修复判据

2026-10-13，用户目标保持实际整盘可用。旧中间制品046bb...的扫描B61981AD-5FF5-494E-B581-12620952A37C/PID40265已实测启动后持续运行。4分钟约15.7k项，11分钟18.2k项；不是正常可接受的全盘体验。样本时间和资源见full-data-samples.jsonl。

`sample 40265 3 -file .../full-data-cpu-sample.txt` exit0；采样支持瓶颈在progress同步等待完整看板重算：cooperative线程619样本中583沿receive/reload/dashboard；insert17，FileReader4。主线程大部分处于事件等待，不能由此证明95%忙段100ms目标。只读EXPLAIN显示category GROUP BY和issue排序使用全scan非covering索引并建TEMP B-TREE，见slow-dashboard-query-plans.json。

## 正在实施

- v4统计与entries在同一事务中增量更新；类别计量与硬链接去重保持原定义，计数/字节溢出拒绝，失败回滚不留下绿灯数字。
- 看板读取每scan总数、最多7类别、同层Top目录、索引覆盖的问题页；避免每200ms扫描所有条目/重建每个展示目录的完整祖先链。
- 生产进度回调仅更新轻量ScanRun；唯一合并后台刷新低频读取结果，旧代次丢弃，最终强制读取最新事务结果。
- Plan/可选文件仍需完整身份链，展示性能优化不能降低执行保护。索引250MiB预算不提高；缓存、归档、retirement及旧迁移的统计一致性要独立测试。

## 必须补齐的证据

1. 独立expected检查多批append、取消、rollback/SQL_FULL、hardlinks、v3→v4、retire/history后统计一致。
2. 固定50k测试含真实progress→dashboard callback，三次wall/RSS/数据库体积与旧结果比较；无callback CLI速度不能替代App全链。
3. 原生UI代次/页面/取消/最终刷新不丢状态，刷新任务同时最多一个；无持续任务积压。
4. 新制品/源码hash绑定，停止旧版本必须记录明确cancelled，仅因新输入重启，不因观察timeout重启。
5. 真正Data范围新版本持续运行到终态。若quota导致单次整盘无法完成，继续解决索引规模，不以让用户选小目录替代本目标。

所有尚未运行项UNVERIFIED；当前目标active，不是v1完成。已有图/数据仅证明其对应版本。

## 紧凑格式前的独立容量参考（2026-10-13）

root实际执行`python3 .local/verification/compact-schema4-baseline.py`，exec84688最终exit0；证据`compact-schema4-baseline-result.json`、原始log及脚本保留。生成200000索引条目，34001目录（17.0005%）、路径平均115.689字符、6种决策、JSON平均777.601字符/825.601UTF8bytes。使用schema4表及全部父目录/分配/UUID/去重/issue/topfolder索引，200条事务批次、DELETE/FULL。DB335470592bytes，即1677.353bytes/条；integrity_check=ok。生成耗时5.964s仅为Python合成SQL成本，不是产品扫描成绩。

这不是创建200k真实文件，不使用宿主用户数据，不是API迁移或计划等价证据：目录JSON字节为显式0（原生v4通常nil省略）、目录聚合为0、scan/category counters为空、scanJSON是容量标记，不能交给产品作为合法ScanRun。新schema1M对照须记录数据形状差异，不能按该参考宣称等价。

独立review后脚本补OUT链接/owner拒绝、DB独占nofollow创建及connect后身份核验；未重跑容量。额外`compact-schema4-baseline-guards.json`验证已有自建DB拒绝exit1且其dev/inode/size/mtime不变；新建/链接负例尚未运行。

新版`compact-schema5-regression-third.log`报告50tests PASS，其中3项opt-in规模基准默认skip（1M、50k dashboard、50k基本），系统Trash只验证权限拒绝；不能记为50项全AC或1M已经PASS。新版真实主盘仍UNVERIFIED。

## 第一轮1M紧凑元数据实验终态（非最终源码）

worker确认exec30924 exit0，`compact-schema5-million-typical.log`1test PASS/266.944s，结构化读取结果`compact-schema5-million-typical-result.json`。1M完整写入、独立统计与抽样Entry完整身份还原通过；不是创建1M真实文件或全量每ID/计划hash证明。DB278249472bytes、278.249B/项，pathMean111.740chars、166674目录，250MiB生产预算实际超6.14%，资源budget FAIL（测试measurement-only cap2GiB不改变生产默认）。

写入265.029s、查询前RSSpeak41369600bytes；dashboard0.0004346s、children0.0008725s；allocated/logical/modified首100项排行约0.0174–0.0210s，真实basename/fullpath搜索0.9053/0.7183s且非空。数据形状与200k旧格式参考不同，不能视完全同分布压缩ratio。该binary先于cycle/cache-bound修正，实际版本关系明确保留；后续源码不能继承其全部指标。

node_modified B-tree约36.23MB，其中18.16MBunused；worker以ASC物理索引/反向DESC遍历消除单调逆序写入半空页的工程细化正在实施。维持排序与分页语义，先100k对照/修复负例，再是否重跑1M。默认预算未调，真实主盘仍UNVERIFIED，不能以资源预算实验test PASS标整盘完成。

## 实际紧凑主盘终态与资源预算修订（2026-10-13）

旧250MiB原bundle603binary实际Data扫描终态：981096 processed/980896 stored/17801 issues，59m17s，DB262135808B（约267.24B/存储项），quotaExceeded partial，完整遍历FAIL。entry_nodes137027584B、UUID索引27312128B、inode_seen24211456B、modified21835776B；完整dbstat见experience-v2/compact-native-full-data-terminal.json。这个平均仅已遍历样本，不代表剩余路径分布或容量保证。

ADR-10-R1明确共享1GiB索引+至少1GiB磁盘可用余量；每批前/提交前原生statfs乘法检查，读不到/不足拒绝，commit前不足整batch rollback实测通过。新Release3a30c314/PID62394实际Data scan48FA94B9于08:46:50Z开始，16:48:38CST196878项/DB55422976B/RSS116336KiB，running。没有把旧250FAIL改绿，也不把新约2min速度当完整覆盖或全程峰值。后续只观察exactrun到终态，M2执行保护不变。
