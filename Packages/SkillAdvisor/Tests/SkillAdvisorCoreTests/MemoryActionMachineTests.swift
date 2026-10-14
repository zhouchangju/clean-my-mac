import Testing
import Foundation
@testable import SkillAdvisorCore

/// MemoryActionMachine 协议条款逐条覆盖（mac-memory-guardian SKILL.md → 状态机映射）。
/// 每个用例标题标注对应条款。
struct MemoryActionMachineTests {

  // MARK: 条款 4：压力 normal → 报告并停，零动作

  @Test func normalPressureStopsWithZeroActions() async {
    let executor = FakeExecutor()
    executor.inspectResults = [.success(inspection(pressured: false, candidates: [candidate("codex-1", tier: .green)]))]
    let machine = MemoryActionMachine(executor: executor)
    let summary = await machine.beginInspection()
    #expect(summary.state == .reporting)
    #expect(summary.note?.contains("压力正常") == true)
    #expect(summary.note?.contains("零动作") == true)
    // 候选仅展示（displayOnly），无任何动作命令
    #expect(summary.proposals.allSatisfy { $0.disposition == .displayOnly })
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
    #expect(executor.callCount(prefix: "approve-calibration") == 0)
  }

  // MARK: 条款 5：calibrationOnly=true → 全部 would do 展示，零清理

  @Test func calibrationModeLabelsAllWouldDo() async {
    let executor = FakeExecutor()
    executor.inspectResults = [.success(inspection(candidates: [candidate("codex-1", tier: .green), candidate("app-1", kind: .app, tier: .yellow)]))]
    executor.calibrationResults = [.success(true)]
    let machine = MemoryActionMachine(executor: executor)
    let summary = await machine.beginInspection()
    #expect(summary.state == .calibrationPending)
    #expect(summary.calibrationOnly == true)
    #expect(summary.proposals.count == 2)
    #expect(summary.proposals.allSatisfy { $0.disposition == .wouldDo })
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
    #expect(executor.callCount(prefix: "approve-calibration") == 0)
  }

  // MARK: 条款 5：显式批准校准 → approve-calibration 后立即停止，同轮零清理

  @Test func approveCalibrationStopsRoundImmediately() async {
    let executor = FakeExecutor()
    executor.inspectResults = [.success(inspection(candidates: [candidate("codex-1", tier: .green)]))]
    executor.calibrationResults = [.success(true)]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let approved = await machine.approveCalibration()
    #expect(approved.state == .approved)
    #expect(approved.note?.contains("本轮不做任何清理") == true)
    #expect(executor.callCount(prefix: "approve-calibration:/tmp/plan-1.json") == 1)
    // 批准后同轮内任何终止动作都被拒绝（绝不清理）
    let refused = await machine.terminate(candidateID: "codex-1")
    #expect(refused.state == .approved)
    #expect(refused.note?.contains("不允许终止动作") == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  @Test func approveCalibrationRefusedOutsidePendingState() async {
    let executor = FakeExecutor()
    let machine = MemoryActionMachine(executor: executor)
    let refused = await machine.approveCalibration() // idle 状态
    #expect(refused.state == .idle)
    #expect(refused.note?.contains("不允许批准校准") == true)
    #expect(executor.callCount(prefix: "approve-calibration") == 0)
  }

  // MARK: 条款（绿色阶段 1-2）：仅最新计划绿色候选，每计划至多一个动作

  @Test func greenTerminateUsesFreshEvidenceAndSingleShot() async {
    let executor = FakeExecutor()
    let green = candidate("codex-99", tier: .green, rss: 2_000_000_000)
    // 两次体检（初始 + 动作前新 45s fast run）都返回同一绿色候选
    executor.inspectResults = [.success(inspection(candidates: [green])), .success(inspection(candidates: [green]))]
    let machine = MemoryActionMachine(executor: executor)
    let inspected = await machine.beginInspection()
    #expect(inspected.state == .inspected)
    #expect(inspected.proposals.first { $0.id == "codex-99" }?.disposition == .actionable)
    let acted = await machine.terminate(candidateID: "codex-99")
    #expect(acted.state == .reporting)
    #expect(acted.actedCandidateID == "codex-99")
    #expect(acted.terminateOutcome?.isCleanExit == true)
    // 命令序列：inspect → calibration → （用户回复结束预算）→ inspect → calibration → terminate（恰好一次）
    #expect(executor.calls.count == 5)
    #expect(executor.calls[0].hasPrefix("inspect"))
    #expect(executor.calls[1].hasPrefix("calibration-status:/tmp/plan-1.json"))
    #expect(executor.calls[2].hasPrefix("inspect"))
    #expect(executor.calls[3].hasPrefix("calibration-status:/tmp/plan-1.json"))
    #expect(executor.calls[4].hasPrefix("terminate-codex:/tmp/plan-1.json:codex-99:"))
    // 单发后计划作废：再次终止被拒绝，必须重新体检
    let refused = await machine.terminate(candidateID: "codex-99")
    #expect(refused.note?.contains("重新体检") == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 1)
  }

  @Test func terminateRefusedBeforeAnyInspection() async {
    let executor = FakeExecutor()
    let machine = MemoryActionMachine(executor: executor)
    let refused = await machine.terminate(candidateID: "codex-1")
    #expect(refused.state == .idle)
    #expect(refused.note?.contains("不允许终止动作") == true)
    #expect(executor.calls.isEmpty)
  }

  // MARK: 条款（绿色阶段 2）：timeout-seconds = min(15, 余量-12) 向下取整且 ≥1

  @Test func boundedTimeoutFormula() {
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 13) == 1)
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 13.9) == 1)   // floor(1.9)=1
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 27) == 15)
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 100) == 15)   // 上限 15
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 26.99) == 14) // floor(14.99)=14
  }

  @Test func boundedTimeoutBoundary() {
    // <12s 不启动；恰好 12s 可启动且 timeout=1
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 11.99) == nil)
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 12.0) == 1)
    #expect(MemoryActionMachine.boundedTimeout(remainingSeconds: 0) == nil)
  }

  @Test func insufficientBudgetSkipsAction() async {
    let clock = FakeClock()
    let executor = FakeExecutor()
    executor.clock = clock
    let green = candidate("codex-7", tier: .green)
    executor.inspectResults = [
      .success(inspection(candidates: [green])),                            // 初始体检：0 耗时
      .success(inspection(planPath: "/tmp/plan-2.json", candidates: [green])), // 动作前新轮体检：耗时 35s
    ]
    executor.inspectCostSeconds = 35
    let machine = MemoryActionMachine(executor: executor, clock: clock)
    _ = await machine.beginInspection() // 预算近乎满额 → inspected
    let summary = await machine.terminate(candidateID: "codex-7") // 新 45s 预算，inspect 耗 35s → 余 10s < 12s
    #expect(summary.state == .reporting)
    #expect(summary.note?.contains("12s") == true)
    #expect(summary.skipped.contains { $0.contains("codex-7") } == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  @Test func terminateTimeoutSecondsRespectsRemainingBudget() async {
    let clock = FakeClock()
    let executor = FakeExecutor()
    executor.clock = clock
    let green = candidate("codex-8", tier: .green)
    executor.inspectResults = [.success(inspection(candidates: [green])), .success(inspection(planPath: "/tmp/plan-2.json", candidates: [green]))]
    executor.calibrationCostSeconds = 25 // 新轮：inspect(0) + calibration(25) → 余 20 → timeout = min(15, 8) = 8
    let machine = MemoryActionMachine(executor: executor, clock: clock)
    _ = await machine.beginInspection()
    _ = await machine.terminate(candidateID: "codex-8")
    #expect(executor.calls.contains { $0.hasPrefix("terminate-codex:/tmp/plan-2.json:codex-8:8") })
  }

  // MARK: 条款（黄色 5）：yellow 候选无自动路径

  @Test func yellowCandidatesHaveNoAutomatedPath() async {
    let executor = FakeExecutor()
    let yellowCodex = candidate("codex-y", tier: .yellow)
    let yellowApp = candidate("app-2", kind: .app, tier: .yellow)
    executor.inspectResults = [.success(inspection(candidates: [yellowCodex, yellowApp])),
                               .success(inspection(candidates: [yellowCodex, yellowApp]))]
    let machine = MemoryActionMachine(executor: executor)
    let inspected = await machine.beginInspection()
    #expect(inspected.proposals.allSatisfy { $0.disposition == .needsUser })
    // 即便用户点名黄色候选：重新体检后仍非绿色 → 不执行（fail-closed）
    let summary = await machine.terminate(candidateID: "codex-y")
    #expect(summary.state == .reporting)
    #expect(summary.skipped.contains { $0.contains("codex-y") } == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  // MARK: 条款（黄色/绿色共同）：证据漂移 → 不执行

  @Test func candidateDriftInFreshPlanSkipsAction() async {
    let executor = FakeExecutor()
    executor.inspectResults = [
      .success(inspection(candidates: [candidate("codex-5", tier: .green)])),
      .success(inspection(planPath: "/tmp/plan-2.json", candidates: [candidate("codex-5", tier: .red)])), // 漂移为红色
    ]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let summary = await machine.terminate(candidateID: "codex-5")
    #expect(summary.state == .reporting)
    #expect(summary.note?.contains("非绿色") == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  @Test func candidateMissingFromFreshPlanSkipsAction() async {
    let executor = FakeExecutor()
    executor.inspectResults = [
      .success(inspection(candidates: [candidate("codex-6", tier: .green)])),
      .success(inspection(planPath: "/tmp/plan-2.json", candidates: [])), // 新计划没有该候选
    ]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let summary = await machine.terminate(candidateID: "codex-6")
    #expect(summary.state == .reporting)
    #expect(summary.note?.contains("未出现在最新计划") == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  @Test func freshNormalPressureDuringTerminateStopsWithZeroActions() async {
    let executor = FakeExecutor()
    executor.inspectResults = [
      .success(inspection(candidates: [candidate("codex-4", tier: .green)])),
      .success(inspection(planPath: "/tmp/plan-2.json", pressured: false, candidates: [])), // 压力恢复正常
    ]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let summary = await machine.terminate(candidateID: "codex-4")
    #expect(summary.state == .reporting)
    #expect(summary.note?.contains("零动作") == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  @Test func freshCalibrationModeDefersActionToApproval() async {
    let executor = FakeExecutor()
    executor.inspectResults = [
      .success(inspection(candidates: [candidate("codex-3", tier: .green)])),
      .success(inspection(planPath: "/tmp/plan-2.json", candidates: [candidate("codex-3", tier: .green)])),
    ]
    executor.calibrationResults = [.success(false), .success(true)] // 动作前新计划处于校准模式
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let summary = await machine.terminate(candidateID: "codex-3")
    #expect(summary.state == .calibrationPending)
    #expect(summary.proposals.allSatisfy { $0.disposition == .wouldDo })
    #expect(summary.skipped.contains { $0.contains("would do") } == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  // MARK: 条款：任何失败/超时/证据不完整/格式异常 → fail-closed，不重试旧计划

  @Test func inspectFailureFailsClosed() async {
    let executor = FakeExecutor()
    executor.inspectResults = [.failure(MemoryCheckError.unexpectedOutput("输出与协议不符"))]
    let machine = MemoryActionMachine(executor: executor)
    let summary = await machine.beginInspection()
    #expect(summary.state == .failed)
    #expect(summary.note?.contains("fail-closed") == true)
    // fail-closed 后终止动作被拒绝（不重试旧计划）
    let refused = await machine.terminate(candidateID: "codex-1")
    #expect(refused.state == .failed)
    #expect(refused.note?.contains("不允许终止动作") == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 0)
  }

  @Test func calibrationStatusFailureFailsClosed() async {
    let executor = FakeExecutor()
    executor.inspectResults = [.success(inspection())]
    executor.calibrationResults = [.failure(MemoryCheckError.unexpectedOutput("多了一个键"))]
    let machine = MemoryActionMachine(executor: executor)
    let summary = await machine.beginInspection()
    #expect(summary.state == .failed)
    #expect(summary.note?.contains("fail-closed") == true)
  }

  @Test func terminateFailureFailsClosedWithoutRetry() async {
    let executor = FakeExecutor()
    let green = candidate("codex-2", tier: .green)
    executor.inspectResults = [.success(inspection(candidates: [green])), .success(inspection(candidates: [green]))]
    executor.terminateResults = [.failure(MemoryCheckError.commandTimedOut("terminate-codex 超时"))]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let summary = await machine.terminate(candidateID: "codex-2")
    #expect(summary.state == .failed)
    #expect(summary.skipped.contains("codex-2")) // 报告已跳过项
    #expect(summary.note?.contains("不重试") == true)
    // 失败后同计划再试 → 拒绝
    let refused = await machine.terminate(candidateID: "codex-2")
    #expect(refused.state == .failed)
    #expect(executor.callCount(prefix: "terminate-codex") == 1)
  }

  @Test func rejectedOutcomeIsTerminalForPlan() async {
    let executor = FakeExecutor()
    let green = candidate("codex-10", tier: .green)
    executor.inspectResults = [.success(inspection(candidates: [green])), .success(inspection(candidates: [green]))]
    executor.terminateResults = [.success(TerminateOutcome(status: "rejected-pressure-normal", exited: nil, survivorPIDs: nil, recoveryRecordPath: nil, recoveryStatus: nil))]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let summary = await machine.terminate(candidateID: "codex-10")
    #expect(summary.state == .reporting)
    #expect(summary.note?.contains("作废") == true)
    #expect(summary.note?.contains("rejected-pressure-normal") == true)
    let refused = await machine.terminate(candidateID: "codex-10")
    #expect(refused.note?.contains("重新体检") == true)
    #expect(executor.callCount(prefix: "terminate-codex") == 1)
  }

  @Test func survivorPIDsReportedAsNeedsUser() async {
    let executor = FakeExecutor()
    let green = candidate("codex-11", tier: .green)
    executor.inspectResults = [.success(inspection(candidates: [green])), .success(inspection(candidates: [green]))]
    executor.terminateResults = [.success(TerminateOutcome(status: "exited", exited: true, survivorPIDs: [4321, 8765], recoveryRecordPath: "/tmp/r.json", recoveryStatus: "persisted"))]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    let summary = await machine.terminate(candidateID: "codex-11")
    #expect(summary.terminateOutcome?.isCleanExit == true)
    #expect(summary.skipped.contains { $0.contains("4321") && $0.contains("needs-user") } == true) // 存活 PID 仅报告，不追加信号
  }

  // MARK: 新轮语义：终态后重新体检开新轮

  @Test func newRoundAfterReportedActionStartsFreshInspection() async {
    let executor = FakeExecutor()
    let green = candidate("codex-12", tier: .green)
    executor.inspectResults = [
      .success(inspection(candidates: [green])),
      .success(inspection(candidates: [green])),
      .success(inspection(planPath: "/tmp/plan-3.json", pressured: false, candidates: [])), // 新轮体检
    ]
    let machine = MemoryActionMachine(executor: executor)
    _ = await machine.beginInspection()
    _ = await machine.terminate(candidateID: "codex-12")
    let renewed = await machine.beginInspection()
    #expect(renewed.state == .reporting)
    #expect(renewed.inspection?.planPath == "/tmp/plan-3.json")
    #expect(executor.callCount(prefix: "terminate-codex") == 1)
  }
}
