import Foundation
import CleanerDomain

/// Storage grouping is metadata classification, not a deletion rule or safety assertion.
public enum StorageClassifier {
    public static func category(relativePath: String, identity: FileIdentity?, decision: RuleDecision) -> StorageCategory {
        let parts = relativePath.split(separator: "/").map(String.init)
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        if decision.ruleIDs.contains(where: { $0.hasPrefix("RULE-DEV") || $0.hasPrefix("RULE-AI") }) { return .cache }
        if parts.contains("Downloads") { return .downloads }
        if parts.contains(where: { $0.hasSuffix(".app") }) || parts.contains("Application Support") || parts.first == "Applications" { return .applications }
        if parts.contains("Caches") || parts.contains("Intermediates.noindex") || parts.contains("_cacache") { return .cache }
        if parts.contains(where: { ["node_modules", "DerivedData", "git", "build", ".build", ".gradle"].contains($0) }) || ["swift", "cpp", "h", "py", "js", "ts", "tsx", "o"].contains(ext) { return .developer }
        if ["jpg", "jpeg", "png", "heic", "gif", "mov", "mp4", "mkv", "mp3", "wav", "m4a", "webp"].contains(ext) { return .media }
        if ["pdf", "txt", "md", "docx", "xlsx", "pages", "key", "epub", "pptx"].contains(ext) { return .documents }
        return .other
    }
}
public struct StorageInsight: Sendable, Identifiable {
    public enum Kind: String, Sendable { case candidates, largeFiles, downloads, coverage }
    public var id: String { kind.rawValue }
    public let kind: Kind
    public let title: String
    public let summary: String
    public let actionTitle: String
    public let category: StorageCategory?
    public let largeOnly: Bool
    public let candidatesOnly: Bool
    public let issuesOnly: Bool
}
public enum StorageInsights {
    public static func make(dashboard: StorageDashboard) -> [StorageInsight] {
        var result: [StorageInsight] = []
        if dashboard.previewCandidateCount > 0 {
            result.append(StorageInsight(kind: .candidates, title: "审阅缓存与开发产物", summary: "发现\(dashboard.previewCandidateCount)个规则匹配文件。规则尚未准入，先核对用途、所属工具和重建成本。占用不是可释放量。", actionTitle: "查看匹配项", category: nil, largeOnly: false, candidatesOnly: true, issuesOnly: false))
        }
        if dashboard.largeFileCount > 0 {
            result.append(StorageInsight(kind: .largeFiles, title: "从大文件开始整理", summary: "发现\(dashboard.largeFileCount)个至少512 MiB的普通文件。是否保留由你决定，年龄和大小不能证明它无用。", actionTitle: "审阅大文件", category: nil, largeOnly: true, candidatesOnly: false, issuesOnly: false))
        }
        if let downloads = dashboard.categories.first(where: { $0.category == .downloads }), downloads.fileCount > 0 {
            result.append(StorageInsight(kind: .downloads, title: "检查下载内容", summary: "\(downloads.fileCount)个下载目录文件已计量。优先核对安装包和已用完的资料；不自动勾选。", actionTitle: "查看下载内容", category: .downloads, largeOnly: false, candidatesOnly: false, issuesOnly: false))
        }
        if dashboard.summary.unknownCount > 0 {
            result.append(StorageInsight(kind: .coverage, title: "查看未覆盖范围", summary: "\(dashboard.summary.unknownCount)处项目未能完整计量，包括保护、权限或边界。已知占用是下界，不能把未知当0。", actionTitle: "查看覆盖问题", category: nil, largeOnly: false, candidatesOnly: false, issuesOnly: true))
        }
        return result
    }
}
