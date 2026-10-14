import Foundation
import CleanerDomain

public struct Rule: Codable, Sendable {
    public let id: String
    public let version: String
    public let enabled: Bool
    public let category: String
    public let sourceRefs: [String]
    public let roots: [[String]]
    public let matcher: String
    public let exclusions: [String]
    public let ownerDetection: String
    public let activityCheck: String
    public let minAge: Decimal64?
    public let disposition: Disposition
    public let capability: Capability
    public let reason: String
    public let rebuildCost: String
    public let admissionEvidence: String?
}
public struct RuleSet: Codable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let rules: [Rule]
    public static func load(_ data: Data) throws -> Self {
        let r = try Codec.decoder().decode(Self.self, from: data)
        guard r.schemaVersion == 1, !r.version.isEmpty, Set(r.rules.map(\.id)).count == r.rules.count else { throw CleanerError(.invalidInput, "不支持的规则版本或重复ID") }
        for rule in r.rules {
            guard !rule.id.isEmpty, !rule.version.isEmpty, !rule.roots.isEmpty,
                  ["exactRelativePath", "segmentGlob", "extensionSet"].contains(rule.matcher),
                  !rule.sourceRefs.isEmpty, !rule.ownerDetection.isEmpty, !rule.activityCheck.isEmpty,
                  rule.capability == .previewOnly, // Admission is a compiled safety gate, not a JSON toggle.
                  rule.roots.allSatisfy({ !$0.isEmpty && $0.allSatisfy(validSegment) }),
                  rule.exclusions.allSatisfy({ validSegment($0) }) else { throw CleanerError(.invalidInput, "规则语义校验失败：\(rule.id)") }
        }
        return r
    }
    private static func validSegment(_ s: String) -> Bool { !s.isEmpty && s != "." && s != ".." && !s.contains("/") && !s.contains("\0") && !s.contains("**") && !s.contains("$") }
}
public struct RuleEngine: Sendable {
    public let version: String
    public let ruleSet: RuleSet?
    public let ignores: [IgnoreEntry]
    public let homePath: String
    public init(ignores: [IgnoreEntry] = [], homePath: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.ignores = ignores; self.homePath = homePath
        // Immutable built-in seed rules; all cache capabilities remain previewOnly until AC-09.
        self.ruleSet = try? RuleSet.load(Self.seedData); version = "seed-1"
    }
    public init(data: Data, previous: RuleEngine? = nil, ignores: [IgnoreEntry] = [], homePath: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        let loaded = try? RuleSet.load(data)
        ruleSet = loaded ?? previous?.ruleSet; version = loaded?.version ?? previous?.version ?? "invalid"
        self.ignores = ignores; self.homePath = homePath
    }
    public static let seedData: Data = Data(#"""
    {"schemaVersion":1,"version":"seed-1","rules":[
    {"id":"RULE-DEV-01","version":"1","enabled":true,"category":"开发产物","sourceRefs":["Apple Xcode"],"roots":[["Library","Developer","Xcode","DerivedData"]],"matcher":"exactRelativePath","exclusions":["Archives","dSYM"],"ownerDetection":"Xcode","activityCheck":"processCoverage","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"仅项目 Build/Intermediates.noindex；重建与活动覆盖尚待准入","rebuildCost":"重新编译","admissionEvidence":null},
    {"id":"RULE-DEV-02","version":"1","enabled":true,"category":"开发缓存","sourceRefs":["https://docs.npmjs.com/cli/cache/"],"roots":[[".npm","_cacache","tmp"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"npm/node","activityCheck":"processCoverage","minAge":"604800","disposition":"candidate","capability":"previewOnly","reason":"npm 临时缓存，至少7天；活动覆盖尚待准入","rebuildCost":"再次获取缓存","admissionEvidence":null},
    {"id":"RULE-AI-01","version":"1","enabled":true,"category":"AI 缓存","sourceRefs":["local design"],"roots":[[".codex","cache","codex_apps_tools"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"Codex","activityCheck":"unknown","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"仅精确缓存路径，无法确认活动与再生成","rebuildCost":"未知","admissionEvidence":null},
    {"id":"RULE-AI-02","version":"1","enabled":true,"category":"AI 缓存","sourceRefs":["local design"],"roots":[[".codex","cache","codex_apps_server_info"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"Codex","activityCheck":"unknown","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"仅精确缓存路径，无法确认活动与再生成","rebuildCost":"未知","admissionEvidence":null},
    {"id":"RULE-DEV-03","version":"1","enabled":true,"category":"开发缓存","sourceRefs":["Apple Xcode"],"roots":[["Library","Developer","Xcode","iOS DeviceSupport"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"Xcode","activityCheck":"unknown","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"设备符号缓存按 iOS 版本堆积，连接设备可重新拷贝；活动与准入待验证","rebuildCost":"连接对应版本设备时重新生成","admissionEvidence":null},
    {"id":"RULE-DEV-04","version":"1","enabled":true,"category":"开发产物","sourceRefs":["Apple Xcode"],"roots":[["Library","Developer","Xcode","Archives"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"Xcode","activityCheck":"processCoverage","minAge":null,"disposition":"review","capability":"previewOnly","reason":"用户归档工作产物，仅登记待人工复查；当前受硬保护表 Archives 段整体覆盖，不会产生候选","rebuildCost":"不可重建（用户导出产物）","admissionEvidence":null},
    {"id":"RULE-DEV-05","version":"1","enabled":true,"category":"开发缓存","sourceRefs":["Apple CoreSimulator"],"roots":[["Library","Developer","CoreSimulator","Caches"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"CoreSimulator","activityCheck":"processCoverage","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"模拟器运行时缓存，可重建；活动与准入待验证","rebuildCost":"模拟器启动时重建","admissionEvidence":null},
    {"id":"RULE-DEV-06","version":"1","enabled":true,"category":"设计缓存","sourceRefs":["Sketch"],"roots":[["Library","Caches","com.bohemiancoding.sketch3"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"Sketch","activityCheck":"processCoverage","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"Sketch 素材与缩略图缓存，可重建；活动与准入待验证","rebuildCost":"Sketch 启动时重建","admissionEvidence":null},
    {"id":"RULE-MOB-01","version":"1","enabled":true,"category":"移动设备缓存","sourceRefs":["Apple iTunes"],"roots":[["Pictures","iPod Photo Cache"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"iTunes","activityCheck":"unknown","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"iPod/iPhone 照片同步缓存，重新同步可重建；活动与准入待验证","rebuildCost":"重新同步照片时重建","admissionEvidence":null},
    {"id":"RULE-MOB-02","version":"1","enabled":true,"category":"移动设备缓存","sourceRefs":["Apple iTunes"],"roots":[["Library","iTunes","iPhone Software Updates","*.ipsw"],["Library","iTunes","iPad Software Updates","*.ipsw"],["Library","iTunes","iPod Software Updates","*.ipsw"]],"matcher":"extensionSet","exclusions":[],"ownerDetection":"iTunes","activityCheck":"unknown","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"iOS 固件 ipsw 下载残留，可重新下载；extensionSet 语义待引擎实现，当前不产生候选","rebuildCost":"重新下载固件","admissionEvidence":null},
    {"id":"RULE-NET-01","version":"1","enabled":true,"category":"浏览器缓存","sourceRefs":["Apple Safari"],"roots":[["Library","Caches","com.apple.Safari"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"Safari","activityCheck":"processCoverage","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"Safari 网页缓存，可重建；目录受 TCC 保护，无完全磁盘访问时仅能展示；活动与准入待验证","rebuildCost":"Safari 重建缓存","admissionEvidence":null},
    {"id":"RULE-NET-02","version":"1","enabled":true,"category":"浏览器缓存","sourceRefs":["Google Chrome"],"roots":[["Library","Caches","Google","Chrome","*","Cache"]],"matcher":"segmentGlob","exclusions":[],"ownerDetection":"Chrome","activityCheck":"processCoverage","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"Chrome 各配置档的 Cache 目录，可重建；单层 segmentGlob 语义待引擎实现，当前不产生候选","rebuildCost":"Chrome 重建缓存","admissionEvidence":null},
    {"id":"RULE-MAIL-01","version":"1","enabled":true,"category":"邮件缓存","sourceRefs":["Apple Mail"],"roots":[["Library","Containers","com.apple.mail","Data","Library","Mail Downloads"]],"matcher":"exactRelativePath","exclusions":[],"ownerDetection":"Mail","activityCheck":"processCoverage","minAge":null,"disposition":"candidate","capability":"previewOnly","reason":"邮件附件预览下载缓存，重新打开邮件可再获取；目录受 TCC 保护；活动与准入待验证","rebuildCost":"重新打开邮件时下载","admissionEvidence":null}
    ]}
    """#.utf8)
    public static func normalizeMacDataPath(_ path: String) -> String {
        let data = "/System/Volumes/Data"
        if path == data { return "/" }
        if path.hasPrefix(data + "/") { return String(path.dropFirst(data.count)) }
        return path
    }
    private func relativeToHome(_ absolutePath: String) -> [String]? {
        let canonical = Self.normalizeMacDataPath(absolutePath)
        let home = Self.normalizeMacDataPath(homePath)
        guard canonical.hasPrefix(home + "/") else { return nil }
        return String(canonical.dropFirst(home.count + 1)).split(separator: "/").map(String.init)
    }
    public func protectionReason(absolutePath: String) -> String? {
        protectionReasonCanonical(absolutePath: Self.normalizeMacDataPath(absolutePath))
    }
    private func protectionReasonCanonical(absolutePath: String) -> String? {
        let parts = absolutePath.split(separator: "/").map(String.init)
        let forbidden: Set<String> = [".ssh", ".gnupg", "Keychains", ".git", "Mobile Documents", "CloudStorage", "Backups.backupdb", "LocalMacCleaner", "Archives", "sessions", "credentials", "secrets", "auth.json"]
        if parts.contains(where: { forbidden.contains($0) || $0.hasSuffix(".app") || $0.hasSuffix(".photoslibrary") || $0.hasSuffix(".backupbundle") || $0.hasSuffix(".keychain-db") }) { return "凭据、备份、资料库、应用或本应用状态已保护" }
        // iOS 设备本地备份（~/Library/Application Support/MobileSync/Backup）：与 Backups.backupdb 同级保护；按相邻段对匹配，任意深度生效。
        if let i = parts.firstIndex(of: "MobileSync"), i + 1 < parts.count, parts[i + 1] == "Backup" { return "iOS 设备备份已保护" }
        if parts.contains(where: { $0 == ".codex" || $0 == ".claude" }), relativeToHome(absolutePath) == nil { return "非已验证的AI工具根已保护，不深入配置或会话" }
        if absolutePath == "/" || absolutePath == homePath || absolutePath.hasPrefix("/System/") || absolutePath == "/System" || absolutePath.hasPrefix("/Library/") || absolutePath.hasPrefix("/Applications/") || absolutePath.hasPrefix("/usr/") || absolutePath.hasPrefix("/bin/") || absolutePath.hasPrefix("/sbin/") || absolutePath.hasPrefix("/private/var/db/") { return "根目录或系统范围已保护" }
        if let p = relativeToHome(absolutePath), p.first == ".codex" {
            let allowed = [[".codex", "cache", "codex_apps_tools"], [".codex", "cache", "codex_apps_server_info"]]
            if !allowed.contains(where: { p.starts(with: $0) }) { return "AI 容器仅允许精确缓存；会话、配置和凭据已保护" }
        }
        if let p = relativeToHome(absolutePath), p.first == ".claude" {
            if !p.starts(with: [".claude", "telemetry"]) { return "AI 容器非缓存子树已保护" }
        }
        return nil
    }
    public func shouldDescend(relativePath: String, absolutePath: String) -> Bool {
        if Self.normalizeMacDataPath(absolutePath) == Self.normalizeMacDataPath(homePath) || Self.normalizeMacDataPath(absolutePath) == "/" { return true }
        // Containers may only be traversed towards the two allowed descendants.
        if let p = relativeToHome(absolutePath), [[".codex"], [".codex", "cache"], [".claude"]].contains(p) { return true }
        return protectionReason(absolutePath: absolutePath) == nil
    }
    /// Read-only analysis may measure protected apps/repositories, never granting selection.
    /// Credentials, private AI siblings, cloud domains and this app state remain excluded.
    public func measurementAllowed(absolutePath: String) -> Bool {
        let path = Self.normalizeMacDataPath(absolutePath)
        let parts = path.split(separator: "/").map(String.init)
        let never: Set<String> = [".ssh", ".gnupg", "Keychains", ".git", "CloudStorage", "Mobile Documents", "LocalMacCleaner", "sessions", "credentials", "secrets", "auth.json", "Backups.backupdb"]
        if parts.contains(where: { never.contains($0) || $0.hasSuffix(".keychain-db") || $0.hasSuffix(".backupbundle") }) { return false }
        if parts.contains(where: { $0 == ".codex" || $0 == ".claude" }), relativeToHome(absolutePath) == nil { return false }
        if let p = relativeToHome(absolutePath), p.first == ".codex" || p.first == ".claude" {
            return shouldDescend(relativePath: "", absolutePath: absolutePath)
        }
        if path == "/" || path == Self.normalizeMacDataPath(homePath) { return true }
        if path == "/Library" || path.hasPrefix("/Library/") || path == "/Applications" || path.hasPrefix("/Applications/") || path == "/usr" || path.hasPrefix("/usr/local/") || path == "/usr/local" { return true }
        if path == "/System" || path.hasPrefix("/System/") || path == "/bin" || path.hasPrefix("/bin/") || path == "/sbin" || path.hasPrefix("/sbin/") || path.hasPrefix("/private/var/db/") || path == "/private/var/db" { return false }
        return true
    }
    public func allowedChildNames(absolutePath: String) -> Set<String>? {
        guard let p = relativeToHome(absolutePath) else { return nil }
        if p == [".codex"] { return ["cache"] }
        if p == [".codex", "cache"] { return ["codex_apps_tools", "codex_apps_server_info"] }
        if p == [".claude"] { return ["telemetry"] }
        return nil
    }
    public func decide(relativePath: String, identity: FileIdentity?, absolutePath: String, now: Date = Date()) -> RuleDecision {
        func protect(_ reason: String, _ code: String = "protected") -> RuleDecision { RuleDecision(disposition: .protect, reasonCodes: [code], reason: reason) }
        if let reason = protectionReason(absolutePath: absolutePath) { return protect(reason) }
        guard let i = identity else { return protect("无法核实文件身份", "identityUnknown") }
        if i.kind == .symlink { return protect("符号链接不遍历、不执行", "symlink") }
        if i.kind == .directory { return RuleDecision(disposition: .descend, reasonCodes: ["containerOnly"], reason: "目录仅作展示与选择容器") }
        if i.kind != .regular { return protect("不是普通文件", "unsupportedKind") }
        if i.linkCount.value > 1 { return protect("硬链接共享对象，不允许操作", "hardLink") }
        for ignore in ignores where ignore.enabled {
            let matches: Bool
            switch ignore.scopeKind {
            case .exactPath: matches = absolutePath == ignore.matchValue
            case .subtree: matches = absolutePath == ignore.matchValue || absolutePath.hasPrefix(ignore.matchValue + "/")
            case .appID, .ruleID: matches = false
            }
            if matches { return RuleDecision(disposition: .ignore, reasonCodes: ["userIgnore"], reason: "用户忽略") }
        }
        guard let ruleSet else { return RuleDecision(disposition: .review, reasonCodes: ["invalidRules"], reason: "规则集不可用；仅空间分析") }
        if let home = relativeToHome(absolutePath) {
            for rule in ruleSet.rules where rule.enabled {
                var matches = rule.roots.contains { home.starts(with: $0) }
                if rule.id == "RULE-DEV-01" {
                    // Root + project + Build + Intermediates.noindex + at least one leaf.
                    matches = home.count >= 8 && home.starts(with: ["Library", "Developer", "Xcode", "DerivedData"]) && home[5] == "Build" && home[6] == "Intermediates.noindex"
                }
                if matches && !home.contains(where: { rule.exclusions.contains($0) || $0.hasSuffix(".dSYM") }) {
                    if let age = rule.minAge, let ns = Double(i.mtimeNs) {
                        guard now.timeIntervalSince1970 - ns / 1e9 >= Double(age.value) else { continue }
                    }
                    if ignores.contains(where: { $0.enabled && (($0.scopeKind == .ruleID && $0.matchValue == rule.id) || ($0.scopeKind == .appID && $0.matchValue == rule.ownerDetection)) }) { return RuleDecision(disposition: .ignore, reasonCodes: ["userIgnore"], reason: "用户忽略规则或应用") }
                    return RuleDecision(ruleIDs: [rule.id], category: rule.category, disposition: rule.disposition, capability: .previewOnly, reasonCodes: ["admissionPending"], reason: rule.reason, owner: rule.ownerDetection, rebuildCost: rule.rebuildCost)
                }
            }
        }
        if i.size.value >= 512 * 1024 * 1024 {
            return RuleDecision(ruleIDs: ["RULE-USER-01"], category: "大文件", disposition: .review, capability: .trashEligible, reasonCodes: ["manualReview"], reason: "用户文件，需明确选择；仅可移入废纸篓", owner: "用户", activity: .unknown, rebuildCost: "用户自行核对")
        }
        return RuleDecision(disposition: .review, reasonCodes: ["noRule"], reason: "无准入规则，仅显示空间占用")
    }
}
