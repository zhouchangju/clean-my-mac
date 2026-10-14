import Foundation

/// AI Runtime 目录：受支持的 runtime 清单与静态知识（集中一处，便于漂移维护）。
public enum AIRuntimeCatalog {
    /// 单个 runtime 的静态描述（检测逻辑由此驱动）。
    public struct Spec: Sendable {
        public let id: String
        public let displayName: String
        public let kind: AIRuntime.Kind
        public let commandName: String            // 可执行文件名
        public let extraSearchPaths: [String]     // 已知安装位（可含 ~ 前缀，按 HOME 展开）
        public let analyzable: Bool               // 是否已适配非交互分析
        public init(id: String, displayName: String, kind: AIRuntime.Kind, commandName: String, extraSearchPaths: [String], analyzable: Bool) {
            self.id = id; self.displayName = displayName; self.kind = kind; self.commandName = commandName
            self.extraSearchPaths = extraSearchPaths; self.analyzable = analyzable
        }
    }

    /// 受支持清单（顺序即展示顺序）。
    public static let all: [Spec] = [
        Spec(id: "codex", displayName: "Codex CLI", kind: .cliAgent, commandName: "codex",
             extraSearchPaths: ["~/.local/bin", "~/.codex/bin"], analyzable: true),
        Spec(id: "opencode", displayName: "OpenCode", kind: .cliAgent, commandName: "opencode",
             extraSearchPaths: ["~/.opencode/bin"], analyzable: true),
        Spec(id: "droid", displayName: "Droid", kind: .cliAgent, commandName: "droid",
             extraSearchPaths: ["~/.local/bin"], analyzable: false),
        Spec(id: "ollama", displayName: "Ollama", kind: .localServer, commandName: "ollama",
             extraSearchPaths: ["/opt/homebrew/bin"], analyzable: false),
        Spec(id: "claude", displayName: "Claude Code", kind: .cliAgent, commandName: "claude",
             extraSearchPaths: ["~/.local/bin"], analyzable: false),
    ]

    public static func spec(id: String) -> Spec? { all.first { $0.id == id } }
    public static var ids: [String] { all.map(\.id) }
}

/// 检测到的 AI Runtime（id 固定为目录内的受支持 id）。
public struct AIRuntime: Sendable, Identifiable, Codable, Equatable {
    public enum Kind: String, Codable, Sendable { case cliAgent, localServer }
    public let id: String              // "codex" / "opencode" / "droid" / "ollama" / "claude"
    public let kind: Kind
    public let displayName: String     // 中文展示名
    public let executablePath: String? // nil = 未检测到
    public let version: String?        // `--version` 首行（≤60 字符），探测失败为 nil
    public let canRunAnalysis: Bool    // 仅 codex/opencode 检测到后为 true
    public init(id: String, kind: Kind, displayName: String, executablePath: String?, version: String?, canRunAnalysis: Bool) {
        self.id = id; self.kind = kind; self.displayName = displayName; self.executablePath = executablePath
        self.version = version; self.canRunAnalysis = canRunAnalysis
    }
    public var isInstalled: Bool { executablePath != nil }
}

/// UserDefaults 键集中定义，避免魔法字符串。
public enum AIRuntimePreferenceKey {
    public static let defaultRuntime = "com.localmaccleaner.air.defaultRuntime"
}

/// 默认 Runtime 偏好读写（fail-closed：非法值一律返回 nil / 拒绝写入）。
public enum RuntimePreferences {
    /// 读取默认 runtime id；值缺失、非字符串或不在受支持目录内 → nil。
    public static func readDefault(defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: AIRuntimePreferenceKey.defaultRuntime), AIRuntimeCatalog.spec(id: raw) != nil else { return nil }
        return raw
    }

    /// 写入默认 runtime id（须为受支持 id）；返回是否写入成功。传 nil 清除。
    @discardableResult
    public static func writeDefault(_ id: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let id else { defaults.removeObject(forKey: AIRuntimePreferenceKey.defaultRuntime); return true }
        guard AIRuntimeCatalog.spec(id: id) != nil else { return false }
        defaults.set(id, forKey: AIRuntimePreferenceKey.defaultRuntime); return true
    }
}
