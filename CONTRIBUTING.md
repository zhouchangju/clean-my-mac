# 贡献指南

感谢你考虑为 Local Mac Cleaner 贡献。这是一个安全优先的只读分析项目，请先理解并遵守以下红线，再开始写代码。

## 安全红线（违反即拒绝合并）

1. **不新增任何删除/移动执行路径。** `ExecutionGate.enabled == false` 是编译期常量，
   不能被偏好、配置或参数打开。清理执行能力的开放有独立验收前置（见
   `docs/implementation/execution-probe.md`）。
2. **规则准入保持 previewOnly。** 规则加载器强制 `capability == previewOnly`；
   任何能力提升都要走独立的准入证据流程（`docs/implementation/rule-admission/`）。
3. **fail-closed。** 证据不完整、格式异常、身份漂移、超时——一律停止并报告，
   不放宽、不猜测、不重试旧计划。
4. **无遥测、无后台常驻。** 新功能必须按需触发：不加 Timer、轮询、LaunchAgent
   或守护进程（性能模块的采样会话也是按需订阅的）。
5. **隐私。** 不上报任何数据；导出必须走既有脱敏逻辑；不把原始路径/凭据段写进日志或测试快照。

## 开发环境

- macOS 14+（arm64 实测）、Xcode 16+ / Swift 6 工具链
- GUI 应用：`./scripts/build-app.sh`（产物在 `.local/build/`，已 gitignore）
- 命令行：`swift build -c release`，产物 `.build/release/lmc`

## 代码约定

- **中文文案**直接内联（用户可见字符串、注释、文档均为简体中文）。
- 分层：纯模型 → 规则/计划 → 平台 I/O → UI；新功能优先做成独立 SwiftPM 模块
  （参考 `Packages/AIAdvisor`、`Sources/CleanerViz` 的形状）。
- 并发：有状态服务用 actor；视图模型 `@MainActor @Observable`；阻塞 POSIX 工作
  放 `Task.detached(.utility)`；用代币（generation）丢弃过期结果。
- 错误：统一 `CleanerError(code:message:)`，消息面向用户可读。
- App 工程是显式文件引用：新增 App 源文件需要同步修改
  `App/LocalMacCleaner.xcodeproj/project.pbxproj`（参照既有条目模式）。

## 测试要求

- 使用 Swift Testing（`import Testing` / `@Test` / `#expect`）。
- 行为变更必须带测试；扫描/索引类测试用 `CleanerTestSupport` 的临时夹具，
  不依赖真机用户目录。
- 提交前自检：`swift test`（根包 + 涉及的子包）、`./scripts/build-app.sh`、
  `python3 scripts/cli-smoke.py`、`python3 scripts/mutation-check.py` 全绿。
- UI 行为变更同步更新 `App/LocalMacCleanerUITests`。

## 提交规范

```
<type>(<scope>): <subject>

type: feat / fix / perf / refactor / test / docs / chore
scope: core / viz / extras / ai / skill / app / cli / docs / perf
subject: 一句话中文或英文均可，祈使语气
```

按模块分批提交；不要把无关文件扫进同一个提交（尤其注意仓库里有大量本地研究
产物位于 `.local/`，已被 gitignore，绝不能入库）。
