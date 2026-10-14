# T3 实施记录：空间地图 v2（全页 squarified treemap）

日期：2026-10-14。对应设计：`02-TECH-DESIGN.md` §2.3；任务拆解：`03-TASKS.md` T3.1–T3.4。

## 1. 交付物

| 文件 | 内容 |
|---|---|
| `Sources/CleanerViz/SquarifiedLayout.swift` | `SquarifiedTreemap.layout(weights:in:)`，Bruls/Huizing/van Wijk squarify 清洁室实现 |
| `Sources/CleanerViz/TreemapWeights.swift` | `compress(weights:exponent:)`（默认指数 4）、`cap(items:topN:minRatio:)`（默认 30 / 0.02，总量守恒） |
| `Tests/CleanerVizTests/SquarifiedTreemapTests.swift` | 黄金矩形（含 Bruls 论文 6×4 七项用例）、覆盖/比例守恒、退化输入、确定性（23 用例之一部分） |
| `Tests/CleanerVizTests/TreemapWeightsTests.swift` | compress 已知值/单调、cap 截断/阈值/守恒/排序稳定性、compress→cap→layout 端到端 |
| `App/LocalMacCleaner/SpaceMapModel.swift` | `@MainActor @Observable` 层栈导航 + 当前层按需查询管线 |
| `App/LocalMacCleaner/SpaceMapPage.swift` | 全页 treemap UI：头部/面包屑/前进后退/模式切换/重扫确认/悬停浮层/详情面板/列表模式 |

占位文件 `CleanerVizInfo` 与 `PlaceholderTests.swift` 已按计划移除（模块接线由真实实现取代）。

GPL 清洁室自查：实现仅依据 squarify 公开算法论文的数学描述与"下钻/面包屑/悬停"通用交互范式；未复制 lemon 任何代码、资源或字符串表。

## 2. 布局算法与参数

- **squarify**：输入按权重降序稳定排序（同权重按输入序，保证确定性）；沿剩余矩形短边成行，
  贪心接受使行内最差纵横比不恶化的下一项（`worst = max over items of max(t/s, s/t)`，
  t=条带厚度 `rowSum/total × 长边`，s=项沿短边长度 `w_i/rowSum × 短边`）；
  锁定行后对剩余矩形递归。行内用累计分数定位并把行尾项强制贴边，最后一行由 `total` 精确递减
  收口，保证**并集恰好覆盖容器**（单测断言并集面积 == 容器面积、两两交集≈0、面积与权重比例 1e-9 内）。
- 退化安全：空输入、全零/负/NaN 权重、零/NaN 容器返回空；CGRect 自身会把负宽高规范化，
  故不存在"负尺寸容器"形态（测试注释已记录）。
- **压缩**：`pow(log2(1+bytes), 4)`（`TreemapWeights.defaultExponent = 4`）。设计文档取 4 的
  折中理由：lemon 的 log¹² 过激，指数 4 在真实 home 扫描上让小目录可见又不至于让面积脱离占比。
- **截断**：`cap(topN: 30, minRatio: 0.02)`，minRatio 作用于**已压缩**权重（与瓦片布局同一量纲）；
  被丢弃项与 topN 之外全部并入"其他"，`Σkept + other == Σ正值输入`（单测覆盖）。
- **"其他"的瓦片权重** = `compress(聚合字节数)`（视作一个虚拟大项），而非小项压缩值求和——
  避免"1000 个 1MB 文件"的压缩和在视觉上压过单个 1GB 目录（log 压缩的次可加性取舍，已在悬停
  卡片展示真实字节与占比弥补）。
- 布局在 `CGRect(0,0,1,1)` 单位空间完成，视图层按 GeometryReader 实际尺寸缩放，无需重排。

## 3. 查询管线（SQLiteScanStore API 及理由）

每次导航/刷新对**当前层**只做 2–3 次按需 SQL（绝不整树加载，无 Timer/轮询）：

1. `children(scanID:parentID:limit:120, sort: .allocated)` — 当前层元数据（名称/kind/mtime/
   规则决定），SQL 端按"目录 aggregate_allocated / 文件 allocated"降序取 top 120（索引
   `entry_parent` 支持，成本与当前层子数相关、与全库规模无关）。
2. `mapWeights(scanID:parentID:ids:)` — 对已取回的 120 个 id 取**去重归因权重**（目录 =
   aggregate_allocated，文件 = counted_allocated，硬链接别名为 0）。选它而非
   `mapWeights(parentID:)` 全量形态，是性能红线要求：巨型目录（上万子项）不产生万行结果集；
   未取回部分的质量经"其他"兜底（见下）。`ids ≤ 1000` 的既有限制天然满足。
3. `entries(scanID:ids:[层目录id])`（仅非根层）— 刷新该层 aggregate，防止下钻时缓存的层总量
   在扫描推进/完成后过时。根层总量优先 `model.summary`（CleanerModel 已刷新的看板数据），
   缺失时回退 `store.summary(scanID:)`。

**层总量守恒**：`otherBytes = levelTotalBytes − ΣkeptBytes`。levelTotal 来自父目录 aggregate
（或根层扫描摘要），自动涵盖 top-120 之外未取回项与被 cap 丢弃的小项，"其他"角块不丢量。
真实数据验证：根层 Σchildren 权重 == summary.knownAllocatedBytes 精确相等（见 §5）。

**展示数据**（`SpaceMapModel.Tile`）：`(id, name, bytes, kind, isDirectory, mtime, share, unitRect)`；
share 用**未压缩**字节相对层总量计算（诚实比例），瓦片面积用压缩权重（可读性）——两者解耦并在
 UI 注脚说明。

**刷新时机**：页面 `.task(id: runID#navigationToken)`——进入页面、每次导航（下钻/后退/前进/
跳级/手动刷新令牌 +1）、扫描 run 变化（新扫描/恢复快照→重置到根层）自动重查；
`onChange(of: model.scanning)` 在扫描结束时再触发一次刷新。`model.run == nil` 时显示引导态
（快捷扫描入口，调 `model.quickScan`）。并发防护：`reloadGeneration` 令牌丢弃过期查询结果。

## 4. Finder 显示的实现方式

- 瓦片右键菜单与列表 `contextMenu(forSelectionType:)` 均提供「在 Finder 中显示」，
  直接复用 `CleanerModel.reveal(_:)`（`NSWorkspace.shared.activateFileViewerSelecting`，
  路径 = `scope.rootPath + entry.relativePath`）。Entry 携带相对扫描根的完整路径，
  **无需**额外 catalog 查询拼路径，目录与文件均可 reveal。
- 详情面板另有同名按钮（`spacemap.reveal`）。

## 5. 测试与验证结果

- `swift build` 全绿；`swift test --filter CleanerViz`：**23 用例全绿**（黄金矩形 ×4、
  比例/覆盖/重叠守恒、极端悬殊 1e12:1、退化输入 ×5、确定性/乱序等价、compress 已知值与
  单调、cap 守恒 ×5 形态、端到端管线）。
- App 侧编译：`xcodebuild … Debug` **BUILD SUCCEEDED**（含真实 App target）。
- **真实数据冒烟**（复刻 SpaceMapModel 管线的独立二进制，扫描本仓库目录，163,193 条 / 12.1GB
  已计量 / 222 处权限缺口，索引 12GB 已知分配）：
  - 下钻 4 层：根 → `.local` → `.local/verification` → `compact-capacity/schema4-200k.sqlite`；
  - 每层守恒 `keptBytes + otherBytes == levelTotal` 全部通过；单位矩形并集面积 == 1.000000000；
  - 查询时延：根层 7.5ms、120 子项层 47ms、单子项层 0.6ms——按需查询与全库规模解耦；
  - `.local` 层（>120 子项，截断提示触发）"其他"角块正确聚合 4.04GB 未取回质量。

### 人工复验步骤（主会话执行，真实 home 扫描）

1. 启动 App → 空间地图：未扫描时显示引导态；点「扫描我的文件」。
2. 扫描完成：根层瓦片出现；悬停任一瓦片核对 浮层大小/占比/修改时间 与列表模式同项一致。
3. 点击最大目录瓦片（应立即下钻，面包屑 +1）；再下钻两层，累计 ≥3 层。
4. 「后退」两次、「前进」一次，确认层数据与面包屑同步还原。
5. 点面包屑第 2 层跳级：栈应截断（前进不可用），当前层立即刷新。
6. 切列表模式：核对名称/大小/类型/修改时间；右键任一行「在 Finder 中显示」应定位真实文件。
7. 点击文件瓦片：右侧详情面板显示规则理由/大小/占比/mtime；共享文件显示"已另计"说明。
8. 悬停"其他"角块：显示合并项数；找一层 >120 子项的目录确认"含未取回项"提示。
9. 「重新扫描」→ 确认对话框 → 确认后地图自动重置到根层并随扫描推进刷新。
10. 性能红线复核：全程无轮询；1M 条目索引下下钻应即时（冒烟已证单层 <50ms）。

## 6. 遗留问题与已知取舍

1. **既有 UITest 断言需 T5 更新**：T0 占位后 `testRealDashboardMapAndPlan` 等对旧版
   top-12 地图的期望（单击瓦片出 `detail.enter`、`results.table`/`results.search`/`results.sort`
   在地图页）已失效。v2 按规格"点击目录即下钻"；保留了 `map.tile.*`、`map.breadcrumb.*`、
   `map.back`（新增 `map.forward`）标识符把 T5 改动降到最小。文件瓦片单击出详情、
   列表行双击出详情、目录详情面板仍有 `detail.enter`。
2. **dashboard「打开空间地图」深链降级**：`model.enter(entry)` 只更新旧版 CleanerModel 状态，
   v2 页面不消费（不改 LocalMacCleanerApp.swift 的边界约束）；表现为跳到地图页根层。
   T5 可在集成时接 `SpaceMapModel` 的初始层。
3. **mapWeights 的 ids ≤ 1000 限制**与 fetchLimit 120 共同决定单层最多呈现 120 项元数据；
   更深列表分页暂未做（列表脚注如实显示"仅显示前 120 项"）。
4. **零权重文件不出现在瓦片**（硬链接别名，mapWeights 计 0）：列表模式仍可见并标注
   "共享已另计"，悬停/详情有说明；这是去重归因语义的正确表达而非缺陷。
5. **`children` 排序用原始 allocated**（非去重 counted）：极端情况下大硬链接别名文件可能
   挤占 top-120 名额，使个别真实计数文件落到"其他"；量级可忽略，记录备查。
6. 压缩指数 4 / topN 30 / minRatio 0.02 为可调常量（`SpaceMapModel` 静态属性 +
   CleanerViz 默认参数），真实 home 大范围目测校准留给 T5 验收阶段。
7. App 侧无独立单元测试（App target 不在 SwiftPM 测试图内，且 `CleanerVizTests` 依赖面按
   Package.swift 约束只能 import CleanerViz）；App 逻辑以真实数据冒烟 + 人工清单覆盖。
