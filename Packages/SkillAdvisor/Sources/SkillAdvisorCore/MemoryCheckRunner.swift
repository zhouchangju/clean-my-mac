import Foundation

/// 内存体检公共计划摘要（guardian_inspect.py 只输出脱敏字段；绝不读取私有运行记录）。
public struct MemoryPressure: Sendable, Equatable {
  public let pressured: Bool
  public let reasons: [String]
  public init(pressured: Bool, reasons: [String]) { self.pressured = pressured; self.reasons = reasons }
}

public struct MemoryCandidate: Sendable, Equatable, Identifiable {
  public enum Kind: String, Sendable { case codex, app }
  /// tier 原值：green/yellow/red/unsupported；未知值归 unknown，仅展示不参与判定。
  public enum Tier: String, Sendable { case green, yellow, red, unsupported, unknown }

  public let id: String        // candidate_id
  public let kind: Kind        // codex / app
  public let tier: Tier
  public let tierRaw: String
  public let reasons: [String]
  public let rssBytes: Int?    // rss_bytes（可回收内存）
  public let appName: String?  // display_name（仅 app 候选）

  public init(id: String, kind: Kind, tier: Tier, tierRaw: String, reasons: [String], rssBytes: Int?, appName: String?) {
    self.id = id; self.kind = kind; self.tier = tier; self.tierRaw = tierRaw
    self.reasons = reasons; self.rssBytes = rssBytes; self.appName = appName
  }
}

public struct MemoryInspection: Sendable, Equatable {
  public let planPath: String
  public let policyVersion: String?
  public let mode: String?
  public let pressure: MemoryPressure
  public let candidates: [MemoryCandidate]

  public init(planPath: String, policyVersion: String?, mode: String?, pressure: MemoryPressure, candidates: [MemoryCandidate]) {
    self.planPath = planPath; self.policyVersion = policyVersion; self.mode = mode
    self.pressure = pressure; self.candidates = candidates
  }
  public var codexCandidates: [MemoryCandidate] { candidates.filter { $0.kind == .codex } }
  public var appCandidates: [MemoryCandidate] { candidates.filter { $0.kind == .app } }
  public func candidate(id: String) -> MemoryCandidate? { candidates.first { $0.id == id } }
}

/// 校准批准结果：apply.py approve-calibration → {"status":"approved","record":path}。
public struct ApproveOutcome: Sendable, Equatable {
  public let status: String
  public let recordPath: String?
  public init(status: String, recordPath: String?) { self.status = status; self.recordPath = recordPath }
}

/// 绿色 Codex 终止单发结果：status/exited/survivor_pids/recovery_record/recovery_status。
public struct TerminateOutcome: Sendable, Equatable {
  public let status: String
  public let exited: Bool?
  public let survivorPIDs: [Int]?
  public let recoveryRecordPath: String?
  public let recoveryStatus: String?
  public init(status: String, exited: Bool?, survivorPIDs: [Int]?, recoveryRecordPath: String?, recoveryStatus: String?) {
    self.status = status; self.exited = exited; self.survivorPIDs = survivorPIDs
    self.recoveryRecordPath = recoveryRecordPath; self.recoveryStatus = recoveryStatus
  }
  /// 干净终态：进程退出且恢复记录持久化（apply.py 退出码 0 的同一判定）。
  public var isCleanExit: Bool { status == "exited" && recoveryStatus == "persisted" }
}

/// fail-closed 错误：任何非预期输出一律停，绝不放宽。
public enum MemoryCheckError: Error, Sendable, Equatable {
  case skillNotReady(String)
  case commandTimedOut(String)
  case nonZeroExit(String, exitCode: Int32)
  case unexpectedOutput(String)    // JSON 形状与协议不符
  case evidenceIncomplete(String)  // 关键证据（plan_path/pressure/tier 等）缺失
}

/// 内存 Guardian 命令执行器：inspect / calibration-status / approve-calibration / terminate-codex。
/// 命令构造集中在此（argv 直传，无 shell 拼接），便于漂移维护与测试断言。
public struct MemoryCheckRunner: MemoryActionExecuting {
  public static let inspectTimeout: TimeInterval = 30
  public static let actionTimeout: TimeInterval = 60 // apply 自身有有界 timeout，外层只兜底

  private let commandRunner: any CommandRunning
  private let skills: any SkillLocating
  private let pythonPath: String

  public init(commandRunner: any CommandRunning = ProcessCommandRunner(),
              skills: any SkillLocating = SkillLocator(),
              pythonPath: String = PythonResolver.resolve()) {
    self.commandRunner = commandRunner; self.skills = skills; self.pythonPath = pythonPath
  }

  private func script(_ name: String) throws -> String {
    guard let skill = skills.readySkill(id: SkillLocator.memorySpec.id),
          let dir = skill.skillDir else {
      throw MemoryCheckError.skillNotReady("未找到就绪的 mac-memory-guardian Skill")
    }
    return dir.appendingPathComponent("scripts").appendingPathComponent(name).path
  }

  /// 运行并校验"退出码 0 + stdout 是 JSON 对象"，返回解析后的字典。
  private func runObject(_ scriptPath: String, _ subcommandArgs: [String], timeout: TimeInterval, what: String) async throws -> [String: Any] {
    let result = await commandRunner.run(pythonPath, [scriptPath] + subcommandArgs, timeout: timeout)
    try Self.checkExit(result, what: what)
    guard let parsed = LenientJSON.parse(result.stdout), let dict = LenientJSON.object(parsed) else {
      throw MemoryCheckError.unexpectedOutput("\(what) 输出不是 JSON 对象")
    }
    return dict
  }

  /// 退出码/超时/启动失败统一检查（fail-closed）。
  static func checkExit(_ result: CommandResult, what: String) throws {
    if result.timedOut { throw MemoryCheckError.commandTimedOut("\(what) 超时") }
    if let launchError = result.launchError { throw MemoryCheckError.unexpectedOutput("\(what) 无法启动：\(launchError)") }
    if result.exitCode != 0 {
      throw MemoryCheckError.nonZeroExit("\(what) 退出码 \(result.exitCode)：\(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))", exitCode: result.exitCode)
    }
  }

  // MARK: - MemoryActionExecuting

  /// guardian_inspect.py run --json（fast 模式；deep 只能由用户显式要求，绝不自动进入）。
  public func inspect() async throws -> MemoryInspection {
    let result = await commandRunner.run(pythonPath, [try script("guardian_inspect.py"), "run", "--json"], timeout: Self.inspectTimeout)
    try Self.checkExit(result, what: "内存体检")
    return try MemoryInspection.parse(stdoutText: result.stdout)
  }

  /// apply.py calibration-status --plan <path>：仅接受"恰好一个 calibration_only 布尔"的输出。
  public func calibrationStatus(planPath: String) async throws -> Bool {
    let dict = try await runObject(try script("apply.py"), ["calibration-status", "--plan", planPath], timeout: Self.actionTimeout, what: "校准状态查询")
    guard dict.count == 1, let value = dict["calibration_only"] as? Bool else {
      throw MemoryCheckError.unexpectedOutput("calibration-status 输出与协议不符（期望仅一个 calibration_only 布尔，实际键：\(dict.keys.sorted().joined(separator: ","))）")
    }
    return value
  }

  /// apply.py approve-calibration --plan <path>（仅用户显式批准后调用；批准后本轮零清理）。
  public func approveCalibration(planPath: String) async throws -> ApproveOutcome {
    let dict = try await runObject(try script("apply.py"), ["approve-calibration", "--plan", planPath], timeout: Self.actionTimeout, what: "校准批准")
    guard let status = LenientJSON.string(dict, "status"), status == "approved" else {
      throw MemoryCheckError.unexpectedOutput("approve-calibration 输出与协议不符：\(dict)")
    }
    return ApproveOutcome(status: status, recordPath: LenientJSON.string(dict, "record"))
  }

  /// apply.py terminate-codex：每计划至多一次；timeout-seconds 由状态机按预算计算。
  public func terminateCodex(planPath: String, candidateID: String, timeoutSeconds: Int) async throws -> TerminateOutcome {
    let result = await commandRunner.run(pythonPath, [try script("apply.py"), "terminate-codex", "--plan", planPath, "--candidate", candidateID, "--timeout-seconds", String(timeoutSeconds)], timeout: Self.actionTimeout)
    if result.timedOut { throw MemoryCheckError.commandTimedOut("terminate-codex 超时") }
    if let launchError = result.launchError { throw MemoryCheckError.unexpectedOutput("terminate-codex 无法启动：\(launchError)") }
    // 退出码 0 = 干净终态；3 = 拒绝/超时等终态（仍是合法"结果"，由状态机报告）；2 = 证据错误。
    guard let parsed = LenientJSON.parse(result.stdout), let dict = LenientJSON.object(parsed),
          let status = LenientJSON.string(dict, "status"), !status.isEmpty else {
      throw MemoryCheckError.unexpectedOutput("terminate-codex 输出与协议不符：\(result.stdout)")
    }
    if result.exitCode == 2 { throw MemoryCheckError.evidenceIncomplete("terminate-codex 证据错误：\(result.stderr)") }
    return TerminateOutcome(
      status: status,
      exited: LenientJSON.bool(dict, "exited"),
      survivorPIDs: (dict["survivor_pids"] as? [Any])?.compactMap { $0 as? Int },
      recoveryRecordPath: LenientJSON.string(dict, "recovery_record"),
      recoveryStatus: LenientJSON.string(dict, "recovery_status"))
  }
}

// MARK: - 解码（真实 schema 见 Tests/Fixtures/memory-inspect-sample.json）

extension MemoryInspection {
  /// 协议校验解码：plan_path 必填非空；pressure.pressured 必填；候选缺 id/tier 视为证据不完整（fail-closed）。
  public static func parse(stdoutText: String) throws -> MemoryInspection {
    guard let parsed = LenientJSON.parse(stdoutText), let root = LenientJSON.object(parsed) else {
      throw MemoryCheckError.unexpectedOutput("输出不是 JSON 对象")
    }
    guard let planPath = LenientJSON.string(root, "plan_path"), !planPath.isEmpty else {
      throw MemoryCheckError.evidenceIncomplete("缺少 plan_path")
    }
    guard let plan = root["plan"] as? [String: Any] else {
      throw MemoryCheckError.evidenceIncomplete("缺少公共 plan 摘要")
    }
    guard let pressureDict = plan["pressure"] as? [String: Any],
          let pressured = LenientJSON.bool(pressureDict, "pressured") else {
      throw MemoryCheckError.evidenceIncomplete("缺少 pressure.pressured 判定")
    }
    let pressure = MemoryPressure(pressured: pressured, reasons: LenientJSON.strings(pressureDict, "reasons"))

    var candidates: [MemoryCandidate] = []
    for entry in LenientJSON.objects(plan, "codex_candidates") {
      guard let id = LenientJSON.string(entry, "candidate_id"), !id.isEmpty,
            let tierRaw = LenientJSON.string(entry, "tier"), !tierRaw.isEmpty else {
        throw MemoryCheckError.evidenceIncomplete("codex 候选缺少 candidate_id/tier")
      }
      candidates.append(MemoryCandidate(id: id, kind: .codex, tier: .init(rawValue: tierRaw) ?? .unknown,
                                        tierRaw: tierRaw, reasons: LenientJSON.strings(entry, "reasons"),
                                        rssBytes: LenientJSON.int(entry, "rss_bytes"), appName: nil))
    }
    for entry in LenientJSON.objects(plan, "app_candidates") {
      guard let id = LenientJSON.string(entry, "candidate_id"), !id.isEmpty,
            let tierRaw = LenientJSON.string(entry, "tier"), !tierRaw.isEmpty else {
        throw MemoryCheckError.evidenceIncomplete("app 候选缺少 candidate_id/tier")
      }
      candidates.append(MemoryCandidate(id: id, kind: .app, tier: .init(rawValue: tierRaw) ?? .unknown,
                                        tierRaw: tierRaw, reasons: LenientJSON.strings(entry, "reasons"),
                                        rssBytes: LenientJSON.int(entry, "rss_bytes"), appName: LenientJSON.string(entry, "display_name")))
    }
    return MemoryInspection(planPath: planPath,
                            policyVersion: LenientJSON.string(plan, "policy_version"),
                            mode: LenientJSON.string(plan, "mode"),
                            pressure: pressure, candidates: candidates)
  }
}
