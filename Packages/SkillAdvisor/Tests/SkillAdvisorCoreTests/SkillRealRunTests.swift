import Testing
import Foundation
@testable import SkillAdvisorCore

/// LMC_REAL_RUN=1 时真跑（沿用 LMC_BENCHMARK 的 opt-in 模式）。
/// 只真跑只读命令：guardian_inspect.py run --json 与 apply.py calibration-status；
/// 绝不真跑 terminate-codex / approve-calibration。
/// （磁盘审计虽只读，但全量 home 扫描在本机实测超过 60s 预算，不纳入真跑断言。）
struct SkillRealRunTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["LMC_REAL_RUN"] == "1"))
  func realInspectAndCalibrationStatusOnly() async throws {
    let located = SkillLocator().locate()
    #expect(located.first { $0.id == "mac-memory-guardian" }?.isReady == true)
    #expect(located.first { $0.id == "mac-storage-guardian" }?.isReady == true)

    let runner = MemoryCheckRunner() // pythonPath 走 PATH 解析（guardian 脚本需 ≥3.10）
    let inspection = try await runner.inspect()
    #expect(!inspection.planPath.isEmpty)
    #expect(inspection.mode == "fast")
    print("LMC_REAL_RUN plan_path=\(inspection.planPath) pressured=\(inspection.pressure.pressured) reasons=\(inspection.pressure.reasons) codex=\(inspection.codexCandidates.count) app=\(inspection.appCandidates.count)")
    // 只读查询校准状态（fail-closed：非预期输出会抛错）
    let calibrationOnly = try await runner.calibrationStatus(planPath: inspection.planPath)
    print("LMC_REAL_RUN calibration_only=\(calibrationOnly)")
    #expect(calibrationOnly == true || calibrationOnly == false)
  }
}

/// 解释器解析：PATH 优先、家酿次之、系统 3.9 兜底。
struct PythonResolverTests {
  @Test func prefersPathOrderAndFallsBack() throws {
    // PATH 中第一个 python3 胜出
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lmc-py-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let py = tmp.appendingPathComponent("python3")
    try "#!/bin/sh".write(to: py, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: py.path)
    #expect(PythonResolver.resolve(environment: ["PATH": tmp.path]) == py.path)
    // 空 PATH：已知安装位或系统兜底，永不空串
    let fallback = PythonResolver.resolve(environment: [:])
    #expect(!fallback.isEmpty && fallback.hasSuffix("/python3"))
  }
}
