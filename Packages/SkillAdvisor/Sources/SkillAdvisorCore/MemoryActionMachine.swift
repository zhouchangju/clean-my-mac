import Foundation

/// 内存动作执行器协议：状态机的唯一副作用出口（生产 MemoryCheckRunner，测试注入假实现）。
public protocol MemoryActionExecuting: Sendable {
  func inspect() async throws -> MemoryInspection
  func calibrationStatus(planPath: String) async throws -> Bool
  func approveCalibration(planPath: String) async throws -> ApproveOutcome
  func terminateCodex(planPath: String, candidateID: String, timeoutSeconds: Int) async throws -> TerminateOutcome
}

/// 单调时钟注入（预算计时专用；测试用假时钟推进）。
public protocol MonotonicClock: Sendable { func now() -> ContinuousClock.Instant }
public struct SystemMonotonicClock: MonotonicClock {
  public init() {}
  public func now() -> ContinuousClock.Instant { .now }
}

/// 显式建模的状态机状态。
public enum MemoryActionState: String, Sendable, Equatable {
  case idle               // 未体检
  case inspected          // 已体检 + 校准状态已知（非校准、有压力 → 允许单发动作）
  case calibrationPending // 校准模式：全部 would do，等待用户决定
  case approved           // 校准已批准（终态：本轮零清理）
  case acting             // 正在执行单个 terminate-codex
  case reporting          // 报告终态（正常即停 / 预算用尽 / 动作完成）
  case failed             // fail-closed 终态（协议违规、证据缺失、超时）
}

/// 显式建模的用户事件（本机仅用户操作驱动，无任何自动循环）。
public enum MemoryEvent: Sendable, Equatable {
  case beginInspection     // 运行体检
  case approveCalibration  // 显式批准校准
  case terminate(String)   // 对指定绿色 Codex 候选发起受控终止（确认后）
}

/// 候选处置建议。
public enum ProposalDisposition: String, Sendable, Equatable {
  case wouldDo    // 校准模式：仅展示"would do"，零动作
  case actionable // 绿色 Codex：状态机可单发一次
  case needsUser  // 黄色：建议手动退出，无自动路径
  case displayOnly // 红色/未知/普通应用：仅展示
}

public struct MemoryProposal: Sendable, Equatable, Identifiable {
  public let candidate: MemoryCandidate
  public let disposition: ProposalDisposition
  public var id: String { candidate.id }
  public init(candidate: MemoryCandidate, disposition: ProposalDisposition) {
    self.candidate = candidate; self.disposition = disposition
  }
}

/// 一轮体检/动作的完整报告（含已完成与已跳过项，fail-closed 时也如实呈现）。
public struct MemoryRoundSummary: Sendable, Equatable {
  public let state: MemoryActionState
  public let inspection: MemoryInspection?
  public let calibrationOnly: Bool?
  public let proposals: [MemoryProposal]
  public let note: String?
  public let actedCandidateID: String?
  public let terminateOutcome: TerminateOutcome?
  public let skipped: [String]
  public let budgetRemainingSeconds: Double?
  public let budgetExpired: Bool

  public init(state: MemoryActionState, inspection: MemoryInspection? = nil, calibrationOnly: Bool? = nil,
              proposals: [MemoryProposal] = [], note: String? = nil, actedCandidateID: String? = nil,
              terminateOutcome: TerminateOutcome? = nil, skipped: [String] = [],
              budgetRemainingSeconds: Double? = nil, budgetExpired: Bool = false) {
    self.state = state; self.inspection = inspection; self.calibrationOnly = calibrationOnly
    self.proposals = proposals; self.note = note; self.actedCandidateID = actedCandidateID
    self.terminateOutcome = terminateOutcome; self.skipped = skipped
    self.budgetRemainingSeconds = budgetRemainingSeconds; self.budgetExpired = budgetExpired
  }
}

/// 内存动作状态机：逐条落实 mac-memory-guardian SKILL.md 协议，纯逻辑 + 执行器注入。
/// 协议条款 → 实现：
/// - 45 秒单调预算：每轮第一条命令前起表（startRound）；进入任何下一阶段前检查剩余。
/// - 压力 normal → reporting 零动作。
/// - calibrationOnly=true → 全部 would do；仅显式 approve 事件才调 approve-calibration，
///   批准后立即进入 approved 终态，同一轮绝不清理。
/// - 用户回复（确认终止）结束当前预算 → 新开一轮 45s fast run 重新取证据，
///   只使用最新计划的绿色 Codex 候选；每计划至多一个动作；动作后计划作废，须重新体检。
/// - timeout-seconds = min(15, 余量-12) 向下取整且 ≥1；fast 余量 <12s 不启动。
/// - yellow 无自动路径（needs-user）；红色/未知仅展示。
/// - 任何失败/超时/证据不完整/格式异常 → failed（fail-closed），不重试旧计划。
public actor MemoryActionMachine {
  public static let workBudgetSeconds: Double = 45
  public static let actionReserveSeconds: Double = 12
  public static let maxActionTimeoutSeconds: Double = 15

  private let executor: any MemoryActionExecuting
  private let clock: any MonotonicClock
  private(set) public var state: MemoryActionState = .idle
  private(set) public var lastSummary = MemoryRoundSummary(state: .idle, note: "尚未体检")
  private var budgetEnd: ContinuousClock.Instant?

  public init(executor: any MemoryActionExecuting, clock: any MonotonicClock = SystemMonotonicClock()) {
    self.executor = executor; self.clock = clock
  }

  // MARK: - 事件入口

  @discardableResult
  public func handle(_ event: MemoryEvent) async -> MemoryRoundSummary {
    switch event {
    case .beginInspection: return await performBeginInspection()
    case .approveCalibration: return await performApprove()
    case .terminate(let candidateID): return await performTerminate(candidateID: candidateID)
    }
  }
  @discardableResult public func beginInspection() async -> MemoryRoundSummary { await handle(.beginInspection) }
  @discardableResult public func approveCalibration() async -> MemoryRoundSummary { await handle(.approveCalibration) }
  @discardableResult public func terminate(candidateID: String) async -> MemoryRoundSummary { await handle(.terminate(candidateID)) }

  // MARK: - 阶段实现

  /// 运行体检：inspect → calibration-status（任何一步非预期输出 → fail-closed）。
  private func performBeginInspection() async -> MemoryRoundSummary {
    startRound() // 条款：首条命令前起 45s 预算
    do {
      let inspection = try await executor.inspect()
      let calibrationOnly = try await queryCalibration(planPath: inspection.planPath)
      return await route(inspection: inspection, calibrationOnly: calibrationOnly, selectedCandidateID: nil)
    } catch {
      return failClosed("体检失败：\(describe(error))")
    }
  }

  /// 显式批准校准：仅 calibrationPending 状态有效；批准后立即停止，本轮零清理。
  private func performApprove() async -> MemoryRoundSummary {
    guard state == .calibrationPending else { return refused("当前状态（\(state.rawValue)）不允许批准校准") }
    guard let planPath = lastSummary.inspection?.planPath else {
      return failClosed("校准批准缺少计划路径：证据不完整")
    }
    do {
      let outcome = try await executor.approveCalibration(planPath: planPath)
      state = .approved // 条款：批准后立即停止，同一轮绝不做任何清理
      lastSummary = MemoryRoundSummary(
        state: .approved, inspection: lastSummary.inspection, calibrationOnly: true,
        proposals: lastSummary.proposals,
        note: "已批准校准（记录：\(outcome.recordPath ?? "未返回")）。本轮不做任何清理；后续清理需重新体检且校准状态为否。",
        budgetRemainingSeconds: remainingSeconds())
      return lastSummary
    } catch {
      return failClosed("校准批准失败：\(describe(error))")
    }
  }

  /// 受控终止单个绿色 Codex 候选。
  /// 条款：用户回复结束当前预算 → 新开 45s fast run；只认最新计划的绿色候选；
  /// 每计划至多一个动作；动作后计划作废（终态 reporting/failed），继续操作必须重新体检。
  private func performTerminate(candidateID: String) async -> MemoryRoundSummary {
    guard state == .inspected else { return refused("当前状态（\(state.rawValue)）不允许终止动作；已完成动作的计划已作废，请重新体检") }
    startRound() // 新一轮 45 秒 fast run，重新取证据
    do {
      let inspection = try await executor.inspect()
      let calibrationOnly = try await queryCalibration(planPath: inspection.planPath)
      return await route(inspection: inspection, calibrationOnly: calibrationOnly, selectedCandidateID: candidateID)
    } catch {
      return failClosed("动作前重新体检失败：\(describe(error))", skipped: [candidateID])
    }
  }

  /// 体检证据分流（beginInspection 与 terminate 的共同闸门）。
  private func route(inspection: MemoryInspection, calibrationOnly: Bool, selectedCandidateID: String?) async -> MemoryRoundSummary {
    // 条款：压力 normal → 报告判定并停，零动作。
    if !inspection.pressure.pressured {
      state = .reporting
      lastSummary = MemoryRoundSummary(
        state: .reporting, inspection: inspection, calibrationOnly: calibrationOnly,
        proposals: inspection.candidates.map { MemoryProposal(candidate: $0, disposition: .displayOnly) },
        note: "内存压力正常（0 个压力原因）：报告判定，本轮零动作。",
        budgetRemainingSeconds: remainingSeconds())
      return lastSummary
    }
    // 条款：校准模式 → 全部标注 would do 展示，等待显式批准。
    if calibrationOnly {
      state = .calibrationPending
      let skipped = selectedCandidateID.map { ["\($0)：计划处于校准模式，动作未执行（would do）"] } ?? []
      lastSummary = MemoryRoundSummary(
        state: .calibrationPending, inspection: inspection, calibrationOnly: true,
        proposals: inspection.candidates.map { MemoryProposal(candidate: $0, disposition: .wouldDo) },
        note: selectedCandidateID == nil
          ? "计划处于校准模式：以下均为 would do，未执行任何清理。可显式批准校准；批准后本轮仍零清理。"
          : "最新计划仍处于校准模式：终止动作未执行。可显式批准校准；批准后本轮零清理。",
        skipped: skipped, budgetRemainingSeconds: remainingSeconds())
      return lastSummary
    }
    // 非校准且有压力：生成提案（绿色 Codex=actionable，黄色=needs-user，其余=protected）。
    let proposals = inspection.candidates.map { candidate -> MemoryProposal in
      switch (candidate.kind, candidate.tier) {
      case (.codex, .green): return MemoryProposal(candidate: candidate, disposition: .actionable)
      case (.codex, .yellow), (.app, .yellow): return MemoryProposal(candidate: candidate, disposition: .needsUser)
      default: return MemoryProposal(candidate: candidate, disposition: .displayOnly)
      }
    }
    guard let candidateID = selectedCandidateID else {
      state = .inspected
      lastSummary = MemoryRoundSummary(
        state: .inspected, inspection: inspection, calibrationOnly: false, proposals: proposals,
        note: "检测到内存压力（\(inspection.pressure.reasons.joined(separator: "、"))）。绿色 Codex 候选可受控单发终止（需确认）；黄色候选建议手动退出。",
        budgetRemainingSeconds: remainingSeconds())
      return lastSummary
    }
    // 有选中候选：只使用最新计划里的同一候选，且必须仍是绿色 Codex。
    guard let fresh = inspection.candidate(id: candidateID) else {
      state = .reporting
      lastSummary = MemoryRoundSummary(
        state: .reporting, inspection: inspection, calibrationOnly: false, proposals: proposals,
        note: "候选「\(candidateID)」未出现在最新计划中：证据漂移，不执行（fail-closed）。",
        skipped: ["\(candidateID)：最新计划中不存在"], budgetRemainingSeconds: remainingSeconds())
      return lastSummary
    }
    guard fresh.kind == .codex, fresh.tier == .green else {
      state = .reporting
      let reason = fresh.kind == .app ? "普通应用候选无自动终止路径" : "候选在最新计划中已非绿色（\(fresh.tierRaw)）：不执行"
      lastSummary = MemoryRoundSummary(
        state: .reporting, inspection: inspection, calibrationOnly: false, proposals: proposals,
        note: "\(reason)（fail-closed）。",
        skipped: ["\(candidateID)：\(reason)"], budgetRemainingSeconds: remainingSeconds())
      return lastSummary
    }
    // 条款：进入动作阶段前检查剩余预算；fast 模式余量 <12s 不启动新动作。
    let remaining = remainingSeconds() ?? 0
    guard let timeoutSeconds = Self.boundedTimeout(remainingSeconds: remaining) else {
      state = .reporting
      lastSummary = MemoryRoundSummary(
        state: .reporting, inspection: inspection, calibrationOnly: false, proposals: proposals,
        note: String(format: "剩余预算 %.1fs（<12s 预留线）：不启动终止动作，本轮停止。", remaining),
        skipped: [String(format: "%@：剩余预算不足（%.1fs）", candidateID, remaining)],
        budgetRemainingSeconds: remaining, budgetExpired: remaining <= 0)
      return lastSummary
    }
    state = .acting
    do {
      let outcome = try await executor.terminateCodex(planPath: inspection.planPath, candidateID: candidateID, timeoutSeconds: timeoutSeconds)
      state = .reporting // 计划已消费：终态，任何后续动作都要求重新体检
      var skipped: [String] = []
      if let survivors = outcome.survivorPIDs, !survivors.isEmpty {
        skipped.append("存活辅助进程 PID \(survivors.map(String.init))：needs-user，不自动追加信号")
      }
      let note = outcome.isCleanExit
        ? "已终止绿色 Codex 候选「\(candidateID)」（timeout=\(timeoutSeconds)s，恢复记录已持久化）。该计划已作废；如需继续，请重新体检。"
        : "终止动作终态：\(outcome.status)（recovery_status=\(outcome.recoveryStatus ?? "未知")）。该计划已作废，不重试；重新体检后再评估。"
      lastSummary = MemoryRoundSummary(
        state: .reporting, inspection: inspection, calibrationOnly: false, proposals: proposals,
        note: note, actedCandidateID: candidateID, terminateOutcome: outcome,
        skipped: skipped, budgetRemainingSeconds: remainingSeconds())
      return lastSummary
    } catch {
      return failClosed("终止动作失败：\(describe(error))；该计划作废，重新体检前不重试", skipped: [candidateID], inspection: inspection)
    }
  }

  // MARK: - fail-closed 与工具

  private func failClosed(_ message: String, skipped: [String] = [], inspection: MemoryInspection? = nil) -> MemoryRoundSummary {
    state = .failed // 任何失败/超时/证据不完整/格式异常：停止，绝不放宽
    let display = inspection ?? lastSummary.inspection
    lastSummary = MemoryRoundSummary(
      state: .failed, inspection: display, calibrationOnly: lastSummary.calibrationOnly,
      proposals: (display?.candidates ?? []).map { MemoryProposal(candidate: $0, disposition: .displayOnly) },
      note: "fail-closed：\(message)",
      skipped: skipped + lastSummary.skipped, budgetRemainingSeconds: remainingSeconds(),
      budgetExpired: remainingSeconds().map { $0 <= 0 } ?? false)
    return lastSummary
  }

  private func refused(_ message: String) -> MemoryRoundSummary {
    lastSummary = MemoryRoundSummary(
      state: state, inspection: lastSummary.inspection, calibrationOnly: lastSummary.calibrationOnly,
      proposals: lastSummary.proposals, note: "动作未执行：\(message)",
      actedCandidateID: lastSummary.actedCandidateID, terminateOutcome: lastSummary.terminateOutcome,
      skipped: lastSummary.skipped, budgetRemainingSeconds: remainingSeconds())
    return lastSummary
  }

  /// 查询校准状态；协议要求任何非预期输出都视为停止（错误原样上抛给调用分支 fail-closed）。
  private func queryCalibration(planPath: String) async throws -> Bool {
    try await executor.calibrationStatus(planPath: planPath)
  }

  /// 条款：45s 单调预算，每轮首条命令前起表。
  private func startRound() {
    budgetEnd = clock.now().advanced(by: .seconds(Self.workBudgetSeconds))
  }

  private func remainingSeconds() -> Double? {
    guard let budgetEnd else { return nil }
    let duration = clock.now().duration(to: budgetEnd)
    let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    return seconds
  }

  /// 条款：bounded-timeout = min(15, 余量-12) 向下取整且 ≥1；余量 <12s 返回 nil（不启动）。
  public nonisolated static func boundedTimeout(remainingSeconds: Double) -> Int? {
    guard remainingSeconds >= Self.actionReserveSeconds else { return nil }
    return max(1, Int(min(Self.maxActionTimeoutSeconds, remainingSeconds - Self.actionReserveSeconds).rounded(.down)))
  }

  private func describe(_ error: Error) -> String {
    if let checkError = error as? MemoryCheckError {
      switch checkError {
      case .skillNotReady(let m), .commandTimedOut(let m), .unexpectedOutput(let m), .evidenceIncomplete(let m): return m
      case .nonZeroExit(let m, _): return m
      }
    }
    return error.localizedDescription
  }
}
