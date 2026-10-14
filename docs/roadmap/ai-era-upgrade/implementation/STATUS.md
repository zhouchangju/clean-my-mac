# AI 时代升级 实施状态

日期：2026-10-14。状态：**本期五项功能全部交付，全部测试与构建验收通过。**

## 交付清单

| 模块 | 位置 | 实施记录 |
|---|---|---|
| AI Runtime 中心 | Packages/AIAdvisor + lmc air CLI + App AI 中心页 | [T1-ai-runtime.md](T1-ai-runtime.md) |
| 体检中心（Guardian Skill） | Packages/SkillAdvisor + App AI 中心页 | [T2-skill-checkup.md](T2-skill-checkup.md) |
| 空间地图 v2（squarified treemap） | Sources/CleanerViz + App SpaceMapPage/Model | [T3-spacemap.md](T3-spacemap.md) |
| 重复文件 + 分类 + 规则扩充 | Sources/CleanerExtras + Rules.swift + App 重复文件页 | [T4-duplicates-rules.md](T4-duplicates-rules.md) |
| 预接线与集成 | Package.swift / pbxproj / 页面路由 / UITest 适配 | 本文件 |

## 集成验收结果（T5，2026-10-14）

| 验收项 | 结果 |
|---|---|
| 根包 `swift test` | ✅ 全绿（含新增 CleanerViz 23、CleanerExtras 15；CoreTests 更新为 13 条种子规则断言） |
| AIAdvisor `swift test` | ✅ 27/27 |
| SkillAdvisor `swift test` | ✅ 38/38（协议状态机逐条款覆盖） |
| Performance 包 `swift test` | ✅ 19/19（无回归） |
| App Release 构建（build-app.sh） | ✅ BUILD SUCCEEDED |
| UI 测试（XCUITest 12 例） | ✅ 12/12（含 v2 地图下钻/面包屑/前进后退断言） |
| scripts/cli-smoke.py | ✅ exit 0 |
| scripts/mutation-check.py | ✅ 3/3 变异被检出（修复：隔离工作区需一并拷贝 Packages/） |
| 安全不变式 | ✅ ExecutionGate=false 未动；无新增删除路径；新规则全部 previewOnly |

## 集成期修正（主会话 T5）

1. **新增「文件浏览」页**：空间地图 v2 取代了旧 map 页（原为 browser 视图承载
   搜索/排序/表格），浏览器能力迁至新 `CleanerPage.browse`（面包屑+表格），
   refresh 管线的 children/mapWeights 分支随之从 `.map` 改挂 `.browse`；
   旧 top-12 SpaceMap 视图删除（被 v2 取代）。
2. **瓦片可访问性修复**：树图容器 ZStack 上的 accessibilityIdentifier 会覆盖
   子瓦片的 `map.tile.*` 标识（SwiftUI 扁平化行为），移除容器标识后瓦片
   标识恢复，UI 测试可命中。
3. **UI 测试适配 v2 语义**：目录瓦片点击即下钻（无 detail.enter 中转）；
   瓦片 label 为「名称，大小」改为 BEGINSWITH 匹配；浏览器类断言改走
   「文件浏览」页；恢复快照测试经名称单元格双击进入 Downloads。
4. **mutation-check.py**：拷贝清单加入 Packages/（根包新增路径依赖后隔离
   工作区解析失败）。
5. **误删恢复**：清理旧 SpaceMap 块时误删同块的 LegacyIndexFixture，已从
   会话转录工件完整恢复（73 行，功能等价；如后续 diff 发现风格差异以此为准）。

## 端到端实机验证摘要

- `lmc air list`：检出 codex 0.162.1 / opencode 1.18.35 / droid 0.159.1 /
  ollama（claude 未装）；`lmc air analyze`（codex）真实返回中文回答。
- 磁盘/内存体检实跑：audit.py 输出为标准 JSON（候选分类实际取值
  MIGRATION_CANDIDATE/REVIEW_*，已按真实 schema 解码）；内存 inspect 本机
  当前为校准模式（calibration_only=true），状态机按协议展示 would-do 并停。
- 空间地图实机冒烟：本仓库扫描 163,193 条目/12.1 GB，下钻 4 层，每层查询
  0.6–47 ms（与全库规模解耦）。
- 重复文件实机冒烟：~/Downloads 379 文件/3.06 GB → 44 组重复/139.9 MB
  名义浪费/0.82 s。

## 遗留与后续（详见各 T 文档与 03-TASKS 后续阶段）

- droid/ollama 分析适配；磁盘审计超时上调或 --scope 注入（实测 2–4 分钟）；
- segmentGlob/extensionSet 语义进入 decide（当前休眠回落 review，fail-closed）；
- P2 阶段：卸载残留分析、相似照片、迁移计划 UI、AI 建议与规则候选联动。
