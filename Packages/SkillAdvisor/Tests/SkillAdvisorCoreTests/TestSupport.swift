import Foundation
import SkillAdvisorCore

/// 测试夹具与假实现公共库。

/// 同步作用域锁：NSLock 的 async 安全包装（锁操作限制在同步方法内）。
final class SyncBox: @unchecked Sendable {
  private let lock = NSLock()
  func withLock<R>(_ body: () throws -> R) rethrows -> R {
    lock.lock(); defer { lock.unlock() }
    return try body()
  }
}

enum Fixtures {
  static func text(_ name: String) throws -> String {
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures"),
          let data = try? Data(contentsOf: url) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return String(decoding: data, as: UTF8.self)
  }
}

/// 记录 argv 并按队列回放的假命令执行器。
final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
  struct Call { let executable: String; let arguments: [String] }

  private let box = SyncBox()
  private var callsStorage: [Call] = []
  private var results: [CommandResult]

  init(results: [CommandResult] = []) { self.results = results }

  var calls: [Call] { box.withLock { callsStorage } }

  func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
    box.withLock {
      callsStorage.append(Call(executable: executable, arguments: arguments))
      if results.isEmpty { return CommandResult(exitCode: 0) }
      return results.count > 1 ? results.removeFirst() : results[0]
    }
  }
}

/// 可手动推进的单调时钟。
final class FakeClock: MonotonicClock, @unchecked Sendable {
  private let box = SyncBox()
  private var current: ContinuousClock.Instant = .now

  func now() -> ContinuousClock.Instant { box.withLock { current } }
  func advance(seconds: Double) { box.withLock { _ = seconds; current = current.advanced(by: .seconds(seconds)) } }
}

/// 脚本化假执行器：按队列回放各命令结果，并按配置消耗假时钟。
final class FakeExecutor: MemoryActionExecuting, @unchecked Sendable {
  private let box = SyncBox()
  private var callsStorage: [String] = []
  var inspectResults: [Result<MemoryInspection, Error>] = []
  var calibrationResults: [Result<Bool, Error>] = []
  var approveResults: [Result<ApproveOutcome, Error>] = []
  var terminateResults: [Result<TerminateOutcome, Error>] = []
  /// 每类命令消耗的假时钟秒数（模拟耗时）。
  var inspectCostSeconds: Double = 0
  var calibrationCostSeconds: Double = 0
  var terminateCostSeconds: Double = 0
  weak var clock: FakeClock?

  private func take<T>(_ queue: inout [Result<T, Error>], fallback: Result<T, Error>) -> Result<T, Error> {
    queue.isEmpty ? fallback : queue.removeFirst()
  }

  func inspect() async throws -> MemoryInspection {
    try box.withLock {
      callsStorage.append("inspect")
      clock?.advance(seconds: inspectCostSeconds)
      let result = take(&inspectResults, fallback: .success(inspection(pressured: false)))
      return try result.get()
    }
  }

  func calibrationStatus(planPath: String) async throws -> Bool {
    try box.withLock {
      callsStorage.append("calibration-status:\(planPath)")
      clock?.advance(seconds: calibrationCostSeconds)
      return try take(&calibrationResults, fallback: .success(false)).get()
    }
  }

  func approveCalibration(planPath: String) async throws -> ApproveOutcome {
    try box.withLock {
      callsStorage.append("approve-calibration:\(planPath)")
      return try take(&approveResults, fallback: .success(ApproveOutcome(status: "approved", recordPath: "/tmp/record.json"))).get()
    }
  }

  func terminateCodex(planPath: String, candidateID: String, timeoutSeconds: Int) async throws -> TerminateOutcome {
    try box.withLock {
      callsStorage.append("terminate-codex:\(planPath):\(candidateID):\(timeoutSeconds)")
      clock?.advance(seconds: terminateCostSeconds)
      return try take(&terminateResults, fallback: .success(TerminateOutcome(status: "exited", exited: true, survivorPIDs: [], recoveryRecordPath: "/tmp/recovery.json", recoveryStatus: "persisted"))).get()
    }
  }

  var calls: [String] { box.withLock { callsStorage } }
  func callCount(prefix: String) -> Int { calls.filter { $0.hasPrefix(prefix) }.count }
}

/// 构造伪 skill 目录树（SKILL.md + scripts），返回可注入 SkillLocator 的根目录。
enum SkillTree {
  /// 按真实布局创建两个 Guardian 的目录树。
  static func makeDefault() throws -> (root: URL, locator: SkillLocator) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lmc-skills-\(UUID().uuidString)", isDirectory: true)
    let storageScripts = root.appendingPathComponent(".agents/skills/mac-storage-guardian/scripts", isDirectory: true)
    try FileManager.default.createDirectory(at: storageScripts, withIntermediateDirectories: true)
    try "# s".write(to: storageScripts.deletingLastPathComponent().appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try "#!/usr/bin/env python3".write(to: storageScripts.appendingPathComponent("audit.py"), atomically: true, encoding: .utf8)
    let memoryScripts = root.appendingPathComponent(".agents/skills/mac-memory-guardian/scripts", isDirectory: true)
    try FileManager.default.createDirectory(at: memoryScripts, withIntermediateDirectories: true)
    try "# m".write(to: memoryScripts.deletingLastPathComponent().appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    for name in ["guardian_inspect.py", "apply.py"] {
      try "#!/usr/bin/env python3".write(to: memoryScripts.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    return (root, SkillLocator(root: root.appendingPathComponent(".agents/skills", isDirectory: true)))
  }
}

/// 便捷构造候选与体检。
func candidate(_ id: String, kind: MemoryCandidate.Kind = .codex, tier: MemoryCandidate.Tier, rss: Int? = 1024) -> MemoryCandidate {
  MemoryCandidate(id: id, kind: kind, tier: tier, tierRaw: tier.rawValue, reasons: ["test-reason"], rssBytes: rss, appName: kind == .app ? "App \(id)" : nil)
}

func inspection(planPath: String = "/tmp/plan-1.json", pressured: Bool = true, candidates: [MemoryCandidate] = []) -> MemoryInspection {
  MemoryInspection(planPath: planPath, policyVersion: "test-v1", mode: "fast",
                   pressure: MemoryPressure(pressured: pressured, reasons: pressured ? ["sustained-warning"] : []),
                   candidates: candidates)
}
