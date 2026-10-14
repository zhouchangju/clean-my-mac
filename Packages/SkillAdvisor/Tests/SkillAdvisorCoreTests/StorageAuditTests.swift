import Testing
import Foundation
@testable import SkillAdvisorCore

/// 真实采样 fixture（2026-10-14 本机实跑，脱敏后固化）解码验证。
struct StorageAuditDecodeTests {
  @Test func decodesRealSample() throws {
    let report = StorageAuditReport.parse(stdoutText: try Fixtures.text("storage-audit-sample.json"))
    #expect(report.rawText == nil)
    #expect(report.runError == nil)
    // 内置卷事实
    let internalVolume = try #require(report.internalVolume)
    #expect(internalVolume.path == "/Users/sample")
    #expect(internalVolume.capacityPercent == 92.6)
    #expect(internalVolume.totalBytes ?? 0 > 400_000_000_000)
    // 外置卷：可写 APFS → isExternalWritable
    let external = report.volumes.first { $0.isExternalWritable }
    #expect(external?.filesystem == "APFS")
    #expect(external?.volumeUUID?.isEmpty == false)
    // 10 个默认 scope；三分类映射（真实 classification 取值）
    #expect(report.scopes.count == 10)
    #expect(report.scopes.filter { $0.category == .migrate }.map { $0.scope } == ["Documents", "Movies"])
    let gitScope = report.scopes.first { $0.scope == "git" }
    #expect(gitScope?.rawClassification == "REVIEW_PROJECTS")
    #expect(gitScope?.category == .review)
    // children 保留 + 字段容错
    #expect(gitScope?.children.isEmpty == false)
    #expect(gitScope?.children.first?.actualBytes ?? 0 > 0)
    // 权限盲区来自 warning 字段
    #expect(report.permissionGaps.count == 3)
    #expect(report.permissionGaps.contains { $0.path.contains("/Library/Containers") })
    // 建议列表：REVIEW → 人工核实；MIGRATE → 迁移流程提示
    #expect(report.suggestions.contains { $0.contains("Documents") && $0.contains("迁移") })
    #expect(report.suggestions.contains { $0.contains("git") && $0.contains("人工核实") })
    #expect(report.suggestions.contains { $0.contains("权限盲区") })
  }

  @Test func unknownClassificationFallsBackToReview() {
    #expect(StorageAuditReport.category(for: "SOMETHING_NEW") == .review)
    #expect(StorageAuditReport.category(for: "MIGRATION_CANDIDATE") == .migrate)
    #expect(StorageAuditReport.category(for: "KEEP_LOCAL") == .keepLocal)
    #expect(StorageAuditReport.category(for: nil) == .review)
  }

  @Test func plainTextFallsBackToRawText() {
    let report = StorageAuditReport.parse(stdoutText: "INTERNAL used=456.7 GiB available=34.9 GiB capacity=92.6%\nSCOPE ...")
    #expect(report.rawText != nil)
    #expect(report.rawText?.contains("INTERNAL") == true)
    #expect(report.scopes.isEmpty)
    #expect(report.runError == nil) // 解码失败不是运行错误，是兜底展示
  }

  @Test func emptyAndPartialJSONAreTolerant() {
    // 关键字段全缺：结构化为空但不崩溃，rawText 为 nil（JSON 合法）
    let report = StorageAuditReport.parse(stdoutText: #"{"schema_version":1,"notes":["x"]}"#)
    #expect(report.scopes.isEmpty)
    #expect(report.volumes.isEmpty)
    #expect(report.rawText == nil)
    // 单 scope 缺字节数：仍解码，bytes 为 nil
    let partial = StorageAuditReport.parse(stdoutText: #"{"scopes":[{"path":"/Users/sample/Movies"}]}"#)
    #expect(partial.scopes.count == 1)
    #expect(partial.scopes[0].actualBytes == nil)
    #expect(partial.scopes[0].category == nil)
  }

  @Test func locatorReportsReadiness() throws {
    let tree = try SkillTree.makeDefault()
    let located = tree.locator.locate()
    #expect(located.count == 2)
    #expect(located.allSatisfy { $0.isReady })
    #expect(located.first { $0.id == "mac-memory-guardian" }?.skillDir?.path.hasSuffix("mac-memory-guardian") == true)

    // 缺脚本：不就绪且列出缺失项
    let brokenRoot = FileManager.default.temporaryDirectory.appendingPathComponent("lmc-broken-\(UUID().uuidString)", isDirectory: true)
    let dir = brokenRoot.appendingPathComponent(".agents/skills/mac-storage-guardian/scripts", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "# s".write(to: dir.deletingLastPathComponent().appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let brokenSkillsRoot = brokenRoot.appendingPathComponent(".agents/skills", isDirectory: true)
    let broken = SkillLocator(root: brokenSkillsRoot).locate().first { $0.id == "mac-storage-guardian" }
    #expect(broken?.isReady == false)
    #expect(broken?.missingScripts == ["audit.py"])

    // 目录不存在
    let absent = SkillLocator(root: brokenSkillsRoot.appendingPathComponent("nowhere")).locate()
    #expect(absent.allSatisfy { !$0.isReady && $0.skillDir == nil })
  }
}

/// 命令构造断言（假 runner 检查 argv）。
struct StorageAuditRunnerArgvTests {
  @Test func buildsAuditArgvAndDecodesStdout() async throws {
    let fixture = try Fixtures.text("storage-audit-sample.json")
    let fake = FakeCommandRunner(results: [CommandResult(exitCode: 0, stdout: fixture)])
    let tree = try SkillTree.makeDefault()
    let runner = StorageAuditRunner(commandRunner: fake, skills: tree.locator, pythonPath: "/usr/bin/python3")
    let report = await runner.runAudit()
    let call = try #require(fake.calls.first)
    #expect(call.executable == "/usr/bin/python3")
    #expect(call.arguments.count == 3)
    #expect(call.arguments[0].hasSuffix("/.agents/skills/mac-storage-guardian/scripts/audit.py"))
    #expect(call.arguments[1] == "--output")
    #expect(call.arguments[2].hasSuffix(".json"))
    // 未写输出文件时回退 stdout 解码
    #expect(report.isStructured)
    #expect(report.scopes.count == 10)
  }

  @Test func skillNotReadyFailsClosedWithoutCommand() async throws {
    let fake = FakeCommandRunner()
    let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("lmc-nowhere-\(UUID().uuidString)")
    let report = await StorageAuditRunner(commandRunner: fake, skills: SkillLocator(root: nowhere)).runAudit()
    #expect(fake.calls.isEmpty)
    #expect(report.runError?.contains("mac-storage-guardian") == true)
  }

  @Test func nonZeroExitAndTimeoutReportRunError() async throws {
    let tree = try SkillTree.makeDefault()
    let failing = FakeCommandRunner(results: [CommandResult(exitCode: 2, stdout: "", stderr: "boom")])
    let failed = await StorageAuditRunner(commandRunner: failing, skills: tree.locator, pythonPath: "/usr/bin/python3").runAudit()
    #expect(failed.runError?.contains("退出码 2") == true)
    #expect(failed.rawText == nil)

    let timedOut = FakeCommandRunner(results: [CommandResult(exitCode: -1, stdout: "partial", stderr: "", timedOut: true)])
    let timeoutReport = await StorageAuditRunner(commandRunner: timedOut, skills: tree.locator, pythonPath: "/usr/bin/python3").runAudit()
    #expect(timeoutReport.runError?.contains("超时") == true)
    #expect(timeoutReport.rawText == "partial") // 部分输出留档兜底
  }
}
