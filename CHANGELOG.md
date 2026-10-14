# 更新日志

本项目的显著变更记录在此。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-10-14

首个公开快照：只读分析型 Mac 清理与体检工具。

### 新增

- **扫描引擎**：FD 锚定只读遍历（openat 链、符号链接不跟随、跨卷停止），
  紧凑 SQLite 索引（LZFSE+CRC32 元数据、硬链接去重、聚合滚动更新、
  1 GiB 配额与 1 GiB 磁盘保留水位），权限缺口以"不可读"如实呈现并继续。
- **规则与保护**：13 条种子规则（Xcode DerivedData/DeviceSupport/Archives、
  npm、Codex 缓存、Sketch、iOS 备份/固件、Safari/Chrome、Mail 附件等，全部
  previewOnly）；保护谓词覆盖凭证、系统、应用包、Git 仓库、云盘、备份与
  AI 容器白名单；用户忽略列表持久化。
- **计划预览**：规范哈希、10 分钟 TTL、修订绑定、逐项预检（身份/属主/卷/云/
  规则新鲜度）；执行门默认禁用，确认按钮硬禁用。
- **空间地图 v2**：squarified treemap（log₂ 压缩权重、top-30 截断），点击下钻、
  面包屑、前进/后退、悬停详情、列表模式；每层按需查询。
- **重复文件**：尺寸分桶 → 头 64KB SHA-256 → 全量哈希漏斗，硬链接组标注，
  进度/取消/JSON 导出。
- **文件浏览 / 大文件 / 整理建议**：同层浏览、搜索排序分页、大文件类型过滤
  （含 AI 模型类别）、规则候选与逐项理由。
- **AI 体检中心**：本地 AI Runtime 检测与默认设置（Codex CLI/OpenCode 等），
  只读沙箱非交互分析（脱敏扫描摘要 → 中文建议）；`lmc air` CLI 子命令族。
- **Guardian Skill 体检**：mac-storage-guardian 磁盘审计与 mac-memory-guardian
  内存体检的协议忠实集成（45 秒预算、校准门、green 单发、fail-closed 状态机）。
- **性能监控**（独立工作流）：CPU/内存/启动盘采样、进程排行、菜单栏概览。
- **CLI（lmc）**：`scan` / `plan` / `inspect-receipt` / `air list|default|analyze`。
- **测试与护栏**：单元/UI/CLI 冒烟/变异测试（三个故意错误实现必须被捕获）。

### 安全声明

- 真实删除执行**未开放**（编译期执行门），本项目当前不能替用户清理任何文件。
- 与 lemon-cleaner 的关系：仅借鉴交互范式与路径事实，未复制任何 GPL 代码/资源。
