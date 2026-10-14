import Testing
import Foundation
@testable import SkillAdvisorCore

/// 真实采样 fixture（2026-10-14 本机实跑，脱敏后固化）解码验证。
struct MemoryDecodeTests {
  @Test func decodesRealSample() throws {
    let inspection = try MemoryInspection.parse(stdoutText: try Fixtures.text("memory-inspect-sample.json"))
    #expect(inspection.planPath.hasPrefix("/Users/sample/Library/Application Support/mac-memory-guardian/runs/"))
    #expect(inspection.planPath.hasSuffix(".json"))
    #expect(inspection.policyVersion == "mac-memory-guardian-v2-fast")
    #expect(inspection.mode == "fast")
    #expect(inspection.pressure == MemoryPressure(pressured: true, reasons: ["saturated"]))
    // 真实样例：3 个红色 Codex + 7 个黄色应用候选
    #expect(inspection.codexCandidates.count == 3)
    #expect(inspection.appCandidates.count == 7)
    #expect(inspection.candidates.count == 10)
    let firstCodex = try #require(inspection.codexCandidates.first)
    #expect(firstCodex.id.hasPrefix("codex-"))
    #expect(firstCodex.tier == .red)
    #expect(firstCodex.reasons.contains("identity-incomplete"))
    #expect(firstCodex.rssBytes == 491_077_632)
    #expect(firstCodex.appName == nil)
    let chrome = try #require(inspection.candidate(id: "app-com.google.Chrome"))
    #expect(chrome.kind == .app)
    #expect(chrome.tier == .yellow)
    #expect(chrome.appName == "Google Chrome")
    #expect(chrome.rssBytes == 3_406_004_224)
  }

  @Test func malformedOutputsFailClosed() {
    #expect(throws: MemoryCheckError.self) {
      _ = try MemoryInspection.parse(stdoutText: #"{"plan":{"pressure":{"pressured":false}}}"#) // 缺 plan_path
    }
    #expect(throws: MemoryCheckError.self) {
      _ = try MemoryInspection.parse(stdoutText: #"{"plan_path":"/tmp/p.json"}"#) // 缺 plan/pressure
    }
    #expect(throws: MemoryCheckError.self) {
      _ = try MemoryInspection.parse(stdoutText: #"{"plan_path":"/tmp/p.json","plan":{"pressure":{"reasons":[]},"codex_candidates":[{"candidate_id":"c1"}]}}"#) // 候选缺 tier
    }
    #expect(throws: MemoryCheckError.self) {
      _ = try MemoryInspection.parse(stdoutText: "not json at all") // 非 JSON
    }
    #expect(throws: MemoryCheckError.self) {
      _ = try MemoryInspection.parse(stdoutText: "[1,2,3]") // 顶层非对象
    }
  }
}

/// apply.py 各子命令的 argv 构造与输出协议校验（fail-closed）。
struct MemoryRunnerArgvTests {
  private func makeRunner(_ results: CommandResult...) throws -> (MemoryCheckRunner, FakeCommandRunner, URL) {
    let tree = try SkillTree.makeDefault()
    let fake = FakeCommandRunner(results: results)
    return (MemoryCheckRunner(commandRunner: fake, skills: tree.locator, pythonPath: "/usr/bin/python3"), fake, tree.root)
  }

  @Test func inspectArgvAndDecode() async throws {
    let fixture = try Fixtures.text("memory-inspect-sample.json")
    let (runner, fake, _) = try makeRunner(CommandResult(exitCode: 0, stdout: fixture))
    let inspection = try await runner.inspect()
    let call = try #require(fake.calls.first)
    #expect(call.executable == "/usr/bin/python3")
    #expect(call.arguments.count == 3)
    #expect(call.arguments[0].hasSuffix("/.agents/skills/mac-memory-guardian/scripts/guardian_inspect.py"))
    #expect(Array(call.arguments.suffix(2)) == ["run", "--json"])
    #expect(inspection.planPath.contains("/mac-memory-guardian/runs/"))
  }

  @Test func calibrationStatusStrictProtocol() async throws {
    let (runner, fake, _) = try makeRunner(CommandResult(exitCode: 0, stdout: #"{"calibration_only": true}"#))
    let planPath = "/tmp/plan-abc.json"
    let value = try await runner.calibrationStatus(planPath: planPath)
    #expect(value == true)
    let call = try #require(fake.calls.first)
    #expect(call.arguments[0].hasSuffix("apply.py"))
    #expect(Array(call.arguments.suffix(3)) == ["calibration-status", "--plan", planPath])

    // 任何非"恰好一个布尔"的输出 → fail-closed
    let extra = try makeRunner(CommandResult(exitCode: 0, stdout: #"{"calibration_only": true, "extra": 1}"#)).0
    await #expect(throws: MemoryCheckError.self) { _ = try await extra.calibrationStatus(planPath: planPath) }
    let nonBool = try makeRunner(CommandResult(exitCode: 0, stdout: #"{"calibration_only": "yes"}"#)).0
    await #expect(throws: MemoryCheckError.self) { _ = try await nonBool.calibrationStatus(planPath: planPath) }
    let empty = try makeRunner(CommandResult(exitCode: 0, stdout: #"{}"#)).0
    await #expect(throws: MemoryCheckError.self) { _ = try await empty.calibrationStatus(planPath: planPath) }
    let failed = try makeRunner(CommandResult(exitCode: 2, stdout: "", stderr: #"{"error":"plan not found"}"#)).0
    await #expect(throws: MemoryCheckError.self) { _ = try await failed.calibrationStatus(planPath: planPath) }
  }

  @Test func approveCalibrationArgvAndParse() async throws {
    let (runner, fake, _) = try makeRunner(CommandResult(exitCode: 0, stdout: #"{"record":"/tmp/cal-record.json","status":"approved"}"#))
    let outcome = try await runner.approveCalibration(planPath: "/tmp/plan-1.json")
    #expect(outcome.status == "approved")
    #expect(outcome.recordPath == "/tmp/cal-record.json")
    let call = try #require(fake.calls.first)
    #expect(Array(call.arguments.suffix(3)) == ["approve-calibration", "--plan", "/tmp/plan-1.json"])
  }

  @Test func terminateCodexArgvAndParse() async throws {
    let stdout = #"{"exited":true,"recovery_record":"/tmp/r.json","recovery_status":"persisted","status":"exited","survivor_pids":[]}"#
    let (runner, fake, _) = try makeRunner(CommandResult(exitCode: 0, stdout: stdout))
    let outcome = try await runner.terminateCodex(planPath: "/tmp/plan-1.json", candidateID: "codex-123", timeoutSeconds: 7)
    #expect(outcome.isCleanExit)
    let call = try #require(fake.calls.first)
    #expect(Array(call.arguments.suffix(7)) == ["terminate-codex", "--plan", "/tmp/plan-1.json", "--candidate", "codex-123", "--timeout-seconds", "7"])

    // 退出码 3（拒绝/超时终态）：仍是合法结果，交状态机报告
    let rejected = try makeRunner(CommandResult(exitCode: 3, stdout: #"{"status":"rejected-plan-consumed"}"#)).0
    let rejection = try await rejected.terminateCodex(planPath: "/tmp/p", candidateID: "c", timeoutSeconds: 5)
    #expect(rejection.status == "rejected-plan-consumed")
    #expect(!rejection.isCleanExit)
    // 退出码 2（证据错误）或格式异常：抛错
    let evidenceError = try makeRunner(CommandResult(exitCode: 2, stdout: "", stderr: #"{"error":"deadline"}"#)).0
    await #expect(throws: MemoryCheckError.self) { _ = try await evidenceError.terminateCodex(planPath: "/tmp/p", candidateID: "c", timeoutSeconds: 5) }
    let garbage = try makeRunner(CommandResult(exitCode: 0, stdout: "garbage")).0
    await #expect(throws: MemoryCheckError.self) { _ = try await garbage.terminateCodex(planPath: "/tmp/p", candidateID: "c", timeoutSeconds: 5) }
  }

  @Test func skillNotReadyThrowsWithoutCommand() async throws {
    let fake = FakeCommandRunner()
    let runner = MemoryCheckRunner(commandRunner: fake, skills: SkillLocator(root: FileManager.default.temporaryDirectory.appendingPathComponent("lmc-none-\(UUID().uuidString)")))
    await #expect(throws: MemoryCheckError.self) { _ = try await runner.inspect() }
    #expect(fake.calls.isEmpty)
  }
}
