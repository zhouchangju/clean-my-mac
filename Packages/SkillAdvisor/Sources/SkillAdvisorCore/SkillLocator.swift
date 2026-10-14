import Foundation

/// 一个可接入体检中心的 Guardian Skill 定义（可注册更多）。
public struct SkillSpec: Sendable, Identifiable {
  public let id: String                // "mac-storage-guardian"
  public let displayName: String       // "磁盘体检（mac-storage-guardian）"
  public let requiredScripts: [String] // 相对 scripts/ 的文件名

  public init(id: String, displayName: String, requiredScripts: [String]) {
    self.id = id; self.displayName = displayName; self.requiredScripts = requiredScripts
  }
}

/// Skill 定位结果：skillDir=nil 表示目录不存在；missing 列表给出缺什么。
public struct SkillDescriptor: Sendable, Identifiable {
  public let id: String
  public let displayName: String
  public let skillDir: URL?             // nil = 未找到
  public let requiredScripts: [String]
  public let missingSkillMD: Bool
  public let missingScripts: [String]
  /// 就绪 = 目录、SKILL.md、全部必需脚本齐备。
  public var isReady: Bool { skillDir != nil && !missingSkillMD && missingScripts.isEmpty }

  public init(id: String, displayName: String, skillDir: URL?, requiredScripts: [String], missingSkillMD: Bool, missingScripts: [String]) {
    self.id = id; self.displayName = displayName; self.skillDir = skillDir
    self.requiredScripts = requiredScripts; self.missingSkillMD = missingSkillMD
    self.missingScripts = missingScripts
  }
}

public protocol SkillLocating: Sendable { func locate() -> [SkillDescriptor] }

public extension SkillLocating {
  /// 单个 Skill 快捷定位；未就绪返回 nil。
  func readySkill(id: String) -> SkillDescriptor? {
    locate().first { $0.id == id && $0.isReady }
  }
}

/// 在 ~/.agents/skills/<id> 下定位并校验注册的 Skill；只读检查，不执行任何脚本。
public struct SkillLocator: SkillLocating {
  public static let storageSpec = SkillSpec(id: "mac-storage-guardian", displayName: "磁盘体检", requiredScripts: ["audit.py"])
  public static let memorySpec = SkillSpec(id: "mac-memory-guardian", displayName: "内存体检", requiredScripts: ["guardian_inspect.py", "apply.py"])

  /// 默认注册表：两个 Guardian Skill；调用方可追加更多。
  public static let defaultRegistry: [SkillSpec] = [storageSpec, memorySpec]

  private let root: URL
  private let registry: [SkillSpec]
  private let fileExists: @Sendable (URL) -> Bool

  public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills", isDirectory: true),
              registry: [SkillSpec] = SkillLocator.defaultRegistry,
              fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
    self.root = root; self.registry = registry; self.fileExists = fileExists
  }

  public func locate() -> [SkillDescriptor] {
    registry.map { spec in
      let dir = root.appendingPathComponent(spec.id, isDirectory: true)
      guard fileExists(dir) else {
        return SkillDescriptor(id: spec.id, displayName: spec.displayName, skillDir: nil,
                               requiredScripts: spec.requiredScripts, missingSkillMD: true, missingScripts: spec.requiredScripts)
      }
      let missingMD = !fileExists(dir.appendingPathComponent("SKILL.md"))
      let missing = spec.requiredScripts.filter { !fileExists(dir.appendingPathComponent("scripts").appendingPathComponent($0)) }
      return SkillDescriptor(id: spec.id, displayName: spec.displayName, skillDir: dir,
                             requiredScripts: spec.requiredScripts, missingSkillMD: missingMD, missingScripts: missing)
    }
  }

}
