# 03 任务拆解与执行计划

日期：2026-10-14。并行策略：T0 由主会话串行完成（消共享文件冲突），随后
T1–T4 四个子代理并行（文件所有权互斥），T5 主会话集成验收。

## 文件所有权矩阵（冲突消解核心）

| 任务 | 独占文件/目录 |
|---|---|
| T0 预接线 | Package.swift、pbxproj、App/LocalMacCleanerApp.swift、4 个 App 占位页文件 |
| T1 AI Runtime | Packages/AIAdvisor/**、Sources/CleanerCLI/main.swift |
| T2 体检中心 | Packages/SkillAdvisor/** |
| T3 空间地图 v2 | Sources/CleanerViz/**、App/LocalMacCleaner/SpaceMapPage.swift、SpaceMapModel.swift |
| T4 重复文件+分类+规则 | Sources/CleanerExtras/**、Sources/CleanerCore/Rules.swift、Resources/Rules/seed-v1.json、App/LocalMacCleaner/DuplicatesPage.swift |
| T5 集成验收 | 全仓（只读验证 + 必要修复） |

## T0 预接线（主会话，先行）

- T0.1 Package.swift：新增 targets CleanerViz / CleanerExtras（+测试）。
- T0.2 Packages/AIAdvisor、Packages/SkillAdvisor 包骨架（含 Package.swift）。
- T0.3 pbxproj：新增 App 源文件引用（AICenterPage/SpaceMapPage/
  DuplicatesPage）+ 6 个产品依赖。
- T0.4 LocalMacCleanerApp.swift：`CleanerPage` 增加 `.aiCheckup` /
  `.duplicates`，map 分支指向 `SpaceMapPage`，侧栏中文标题「AI 体检中心」
  「重复文件」；占位视图可编译。
- T0.5 验证：`swift build` + `scripts/build-app.sh` 双绿。
- 交付物：可编译的空壳骨架，子代理即插即用。

## T1 AI Runtime 中心（子代理 A）

- T1.1 AIAdvisorCore：AIRuntime 模型、RuntimeDetector（PATH+已知位+
  版本探测+缓存）、RuntimePreferences（默认 runtime 持久化）、
  AIAnalysisRunner（codex/opencode 命令构造、stdin prompt、超时/取消、
  输出净化）。实跑 `codex exec --help` 确认最终 flags 后固化。
- T1.2 AIAdvisorUI：RuntimePanel（列表/版本/默认设置/选择）、
  AnalysisPanel（上下文预览、运行按钮、进度、结果 Markdown 展示、
  "仅建议不执行"声明）。
- T1.3 App/LocalMacCleaner/AICenterPage.swift 的 Runtime 区块。
- T1.4 CLI：`lmc air list|default|analyze`。
- T1.5 测试：命令构造 argv 断言（假 runner）、检测逻辑（假 PATH）、
  prefs 读写；`LMC_REAL_RUN=1` 时真跑一次 analyze。
- 验收：AC-E3、AC-E4（本机 codex 真实出中文分析）。

## T2 体检中心（子代理 B）

- T2.1 实跑采样：`audit.py --output` 与 `guardian_inspect.py run --json`
  的真实输出固化为 fixtures（放 Packages/SkillAdvisor/Tests/Fixtures/）。
- T2.2 SkillAdvisorCore：SkillLocator、StorageAuditRunner+容错解码、
  MemoryCheckRunner、MemoryActionMachine（45s 预算、校准门、green 单发、
  yellow needs-user、fail-closed）。
- T2.3 SkillAdvisorUI：CheckupPanel（双卡片、运行按钮、进度、结果渲染、
  三色候选表、建议列表、协议文案）。
- T2.4 App/LocalMacCleaner/AICenterPage.swift 的体检区块。
- T2.5 测试：状态机逐协议条款（≥10 用例：正常即停/校准批准即停/预算耗尽/
  单发后作废/证据不完整停）、fixture 解码。
- 验收：AC-E5、AC-E6；真跑一次磁盘+内存体检。

## T3 空间地图 v2（子代理 C）

- T3.1 CleanerViz：SquarifiedLayout（纯函数）+ 权重压缩 + top-N +
  单测（黄金矩形/退化/全零权重）。
- T3.2 SpaceMapModel：层栈导航、前进/后退、面包屑、按需查询
  （复用 CleanerModel 暴露的 store 与 scanID；必要时在 SpaceMapPage 内
  自建查询通道，禁止改 CleanerModel 既有方法语义）。
- T3.3 SpaceMapPage：Canvas 瓦片渲染、点击下钻、悬停浮层、右键 Finder、
  列表模式切换、容量头部、重扫确认。
- T3.4 UITest 手工清单：下钻 3 层/面包屑跳级/前进后退/悬停数值正确。
- 验收：AC-E7（含 1M 索引首帧目标 <1s，按需查询）。

## T4 重复文件 + 分类 + 规则（子代理 D）

- T4.1 CleanerExtras.DuplicateFinder：三段漏斗 + 取消 + 进度流 +
  skipped 记录；夹具测试（真重复全命中、头 64K 相同但内容不同的文件不误判、
  硬链接只报一次或标注）。
- T4.2 FileTypeClassifier + 单测（含 AI 模型扩展名）。
- T4.3 Rules.swift 种子扩充（先在真机验证路径存在再写入；全部
  previewOnly；备份目录维持保护）；Resources/Rules/seed-v1.json 同步；
  若测试断言规则数量则更新。
- T4.4 DuplicatesPage（范围选择/进度/分组结果/导出/取消）。
- 验收：AC-E8、AC-E9。

## T5 集成验收（主会话）

- T5.1 `swift test` 全绿（既有 54+19 不回归 + 新增 4 套）。
- T5.2 `scripts/build-app.sh` Release 构建 + 手动冒烟（新页面可达、AI
  分析真跑、体检真跑、树图真下钻）。
- T5.3 `scripts/cli-smoke.py` + mutation-check 不回归。
- T5.4 文档收尾：implementation/STATUS.md + README 状态更新。
- 验收：AC-E1、AC-E2、AC-E10。

## 后续阶段（本期不做，已立项防漂移）

- P2-a 应用卸载残留分析（四策略，previewOnly）。
- P2-b 相似照片（时间桶 + 指纹，pHash 改良）。
- P2-c storage-guardian 迁移计划生成/apply/finalize 全协议 UI。
- P2-d droid/ollama 分析适配；AI 建议与规则候选联动（AI 输出结构化）。
- P2-e 大文件页"上次打开"分组（需 Spotlight/FSEvents 元数据策略评估）。

## 执行时间线（单日冲刺模型）

1. 主会话 T0（预接线+双绿基线）。
2. 并行 T1/T2/T3/T4（各自 `swift test --filter` 自验）。
3. 主会话 T5 集成 + 修复 + 验收记录。
