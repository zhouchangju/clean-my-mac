import Foundation

/// 磁盘体检（mac-storage-guardian audit.py）解码模型。字段全部可选容错。
public struct StorageAuditReport: Sendable, Equatable {
  /// 卷摘要：内置系统盘 + 外置卷（errorText 非空 = 该卷读取失败）。
  public struct VolumeSummary: Sendable, Equatable {
    public let path: String
    public let totalBytes: Int?
    public let usedBytes: Int?
    public let availableBytes: Int?
    public let capacityPercent: Double?
    public let volumeUUID: String?
    public let filesystem: String?
    public let isWritable: Bool?
    public let busProtocol: String?
    public let isInternal: Bool?
    public let errorText: String?

    /// 计划外迁移时的目标容量事实（纯展示）。
    public var isExternalWritable: Bool { errorText == nil && isInternal == false && isWritable == true }
  }

  /// SKILL.md 语义下的候选三分类；audit.py 原始 classification 一并保留。
  public enum Category: String, Sendable, Equatable {
    case migrate = "MIGRATE"          // 冷数据迁移候选
    case keepLocal = "KEEP_LOCAL"     // 活跃/运行状态，保留本机
    case review = "REVIEW"            // 归属或一致性待人工核实
  }

  public struct AuditEntry: Sendable, Equatable {
    public let path: String
    public let scope: String?
    public let rawClassification: String?
    public let category: Category?
    public let actualBytes: Int?
    public let logicalBytes: Int?
    public let sparseCandidate: Bool?
    public let warning: String?
    public let children: [AuditEntry]
  }

  /// 权限盲区（du Operation not permitted 等）：审计不可见处，不是空目录。
  public struct PermissionGap: Sendable, Equatable {
    public let path: String
    public let detail: String
  }

  public let volumes: [VolumeSummary]
  public let scopes: [AuditEntry]
  public let permissionGaps: [PermissionGap]
  /// 展示建议（由候选推导，纯提示，本应用不执行任何迁移）。
  public let suggestions: [String]
  /// 结构化解码失败/纯文本输出时的兜底原文；nil = 解码成功。
  public let rawText: String?
  /// 运行层异常（Skill 未就绪、超时、退出码非 0、输出文件缺失等）。
  public let runError: String?

  /// 是否拿到可用结构化结果。
  public var isStructured: Bool { rawText == nil && runError == nil }
  public var internalVolume: VolumeSummary? { volumes.first }
}

/// 只读磁盘审计执行器：audit.py --output <tmp>.json（60s 超时）。
/// 边界：审计只读，不迁移任何文件；迁移需 audit→plan→确认→apply 的独立多步确认流程。
public struct StorageAuditRunner: Sendable {
  public static let defaultTimeout: TimeInterval = 60

  private let commandRunner: any CommandRunning
  private let timeout: TimeInterval
  private let skills: any SkillLocating
  private let pythonPath: String

  public init(commandRunner: any CommandRunning = ProcessCommandRunner(),
              skills: any SkillLocating = SkillLocator(),
              timeout: TimeInterval = StorageAuditRunner.defaultTimeout,
              pythonPath: String = PythonResolver.resolve()) {
    self.commandRunner = commandRunner; self.skills = skills; self.timeout = timeout; self.pythonPath = pythonPath
  }

  public func runAudit() async -> StorageAuditReport {
    guard let skill = skills.readySkill(id: SkillLocator.storageSpec.id), let skillDir = skill.skillDir else {
      return StorageAuditReport(volumes: [], scopes: [], permissionGaps: [], suggestions: [],
                                rawText: nil, runError: "未找到就绪的 mac-storage-guardian Skill（~/.agents/skills/mac-storage-guardian 缺失或不完整）")
    }
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lmc-storage-audit-\(UUID().uuidString).json", isDirectory: false)
    let script = skillDir.appendingPathComponent("scripts/audit.py").path
    let result = await commandRunner.run(pythonPath, [script, "--output", outputURL.path], timeout: timeout)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    // audit.py 会把同一 JSON 同时写文件与 stdout；优先读文件，缺失则退回 stdout。
    let text: String
    if let data = try? Data(contentsOf: outputURL), !data.isEmpty {
      text = String(decoding: data, as: UTF8.self)
    } else {
      text = result.stdout
    }
    if result.timedOut { return .runFailed("磁盘审计超时（\(Int(timeout))s）", fallback: text) }
    if let launchError = result.launchError { return .runFailed("磁盘审计无法启动：\(launchError)", fallback: text) }
    if result.exitCode != 0 {
      let stderrTail = result.stderr.split(separator: "\n").suffix(3).joined(separator: " | ")
      return .runFailed("磁盘审计退出码 \(result.exitCode)\(stderrTail.isEmpty ? "" : "：\(stderrTail)")", fallback: text)
    }
    return StorageAuditReport.parse(stdoutText: text)
  }
}

// MARK: - 解码（真实 schema 见 Tests/Fixtures/storage-audit-sample.json）

extension StorageAuditReport {
  static func runFailed(_ message: String, fallback text: String) -> StorageAuditReport {
    StorageAuditReport(volumes: [], scopes: [], permissionGaps: [], suggestions: [],
                       rawText: text.isEmpty ? nil : text, runError: message)
  }

  /// 容错解码：schema_version/internal/scopes 全部可缺；关键字段全缺或非 JSON → rawText 兜底。
  public static func parse(stdoutText: String) -> StorageAuditReport {
    guard let root = LenientJSON.parse(stdoutText), let dict = LenientJSON.object(root) else {
      return StorageAuditReport(volumes: [], scopes: [], permissionGaps: [], suggestions: [],
                                rawText: stdoutText, runError: nil)
    }
    var volumes: [VolumeSummary] = []
    if let internalDict = dict["internal"] as? [String: Any] { volumes.append(Self.volume(internalDict)) }
    volumes += LenientJSON.objects(dict, "external_volumes").map(Self.volume)

    let scopes = LenientJSON.objects(dict, "scopes").map(Self.entry)
    var gaps: [PermissionGap] = []
    for scope in scopes {
      if let warning = scope.warning, !warning.isEmpty { gaps.append(PermissionGap(path: scope.path, detail: warning)) }
      for child in scope.children where !(child.warning ?? "").isEmpty {
        gaps.append(PermissionGap(path: child.path, detail: child.warning!))
      }
    }
    return StorageAuditReport(volumes: volumes, scopes: scopes, permissionGaps: gaps,
                              suggestions: Self.suggestions(scopes: scopes, gaps: gaps, volumes: volumes),
                              rawText: nil, runError: nil)
  }

  private static func volume(_ d: [String: Any]) -> VolumeSummary {
    VolumeSummary(path: LenientJSON.string(d, "path") ?? "",
                  totalBytes: LenientJSON.int(d, "total_bytes"),
                  usedBytes: LenientJSON.int(d, "used_bytes"),
                  availableBytes: LenientJSON.int(d, "available_bytes"),
                  capacityPercent: LenientJSON.double(d, "capacity_percent"),
                  volumeUUID: LenientJSON.string(d, "volume_uuid"),
                  filesystem: LenientJSON.string(d, "filesystem"),
                  isWritable: LenientJSON.bool(d, "writable"),
                  busProtocol: LenientJSON.string(d, "protocol"),
                  isInternal: LenientJSON.bool(d, "internal"),
                  errorText: LenientJSON.string(d, "error"))
  }

  private static func entry(_ d: [String: Any]) -> AuditEntry {
    let rawClassification = LenientJSON.string(d, "classification")
    return AuditEntry(path: LenientJSON.string(d, "path") ?? "",
               scope: LenientJSON.string(d, "scope"),
               rawClassification: rawClassification,
               category: rawClassification == nil ? nil : category(for: rawClassification),
               actualBytes: LenientJSON.int(d, "actual_bytes"),
               logicalBytes: LenientJSON.int(d, "logical_bytes"),
               sparseCandidate: LenientJSON.bool(d, "sparse_candidate"),
               warning: LenientJSON.string(d, "warning"),
               children: LenientJSON.objects(d, "children").map(entry))
  }

  /// audit.py 原始 classification → 三分类；未知值按待复查处理（宁可误报也不放行）。
  public static func category(for rawClassification: String?) -> Category {
    Category(rawClassification) ?? .review
  }

  /// 展示建议（纯提示，不执行）。
  private static func suggestions(scopes: [AuditEntry], gaps: [PermissionGap], volumes: [VolumeSummary]) -> [String] {
    var lines: [String] = []
    for scope in scopes where scope.category == .migrate {
      let size = ByteCountFormatter.string(fromByteCount: Int64(scope.actualBytes ?? 0), countStyle: .file)
      lines.append("「\(scope.scope ?? scope.path)」（\(size)）为冷数据迁移候选：如确认不常用，可走 audit → plan → 确认计划 → apply 的独立迁移流程")
    }
    for scope in scopes where scope.category == .review {
      lines.append("「\(scope.scope ?? scope.path)」标记待复查（\(scope.rawClassification ?? "REVIEW")）：归属与一致性需人工核实，不建议直接迁移")
    }
    for scope in scopes where (scope.sparseCandidate ?? false) {
      lines.append("「\(scope.scope ?? scope.path)」疑似稀疏文件（表观占用远大于实际分配）：迁移前需单独评估，勿按表观体积决策")
    }
    if !gaps.isEmpty {
      lines.append("存在 \(gaps.count) 处权限盲区：审计无法读取的目录不代表为空，统计可能低估")
    }
    if let external = volumes.first(where: { $0.isExternalWritable }) {
      let free = ByteCountFormatter.string(fromByteCount: Int64(external.availableBytes ?? 0), countStyle: .file)
      lines.append("检测到可写外置卷 \(external.path)（可用 \(free)）：迁移目标容量事实，仅供参考")
    }
    return lines
  }
}

extension StorageAuditReport.Category {
  /// audit.py 真实取值：MIGRATION_CANDIDATE / REVIEW_REBUILDABLE / REVIEW_APP_DATA /
  /// REVIEW_PROJECTS / REVIEW_ARCHIVE_SELECTED；另接受 SKILL.md 语义的 MIGRATE/KEEP_LOCAL/REVIEW。
  init?(_ raw: String?) {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case "MIGRATION_CANDIDATE", "MIGRATE": self = .migrate
    case "KEEP_LOCAL": self = .keepLocal
    case "REVIEW", "REVIEW_REBUILDABLE", "REVIEW_APP_DATA", "REVIEW_PROJECTS", "REVIEW_ARCHIVE_SELECTED": self = .review
    default: return nil // 未知分类由调用方降级为 review 展示
    }
  }
}
