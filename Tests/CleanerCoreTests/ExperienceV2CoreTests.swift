import Foundation
import Testing
import CleanerDomain
import CleanerCore

@Test func dataAliasPreservesRulesAndSensitiveBoundaries() {
    let r = RuleEngine(homePath: "/Users/test")
    #expect(RuleEngine.normalizeMacDataPath("/System/Volumes/Data/Users/test") == "/Users/test")
    #expect(RuleEngine.normalizeMacDataPath("/System/Volumes/DataOther/Users/test") == "/System/Volumes/DataOther/Users/test")
    #expect(r.shouldDescend(relativePath: "", absolutePath: "/System/Volumes/Data"))
    #expect(r.measurementAllowed(absolutePath: "/System/Volumes/Data/Applications/Demo.app/Contents"))
    #expect(r.decide(relativePath: "Applications/Demo.app/file", identity: identity(), absolutePath: "/System/Volumes/Data/Applications/Demo.app/file").disposition == .protect)
    for path in ["/System/Volumes/Data/Users/test/.ssh", "/System/Volumes/Data/Users/test/.codex/sessions", "/System/Volumes/Data/Users/test/.codex/plugins", "/Users/other/.codex", "/Users/other/.claude", "/Users/test/Library/CloudStorage", "/Users/test/Library/Application Support/LocalMacCleaner"] {
        #expect(!r.measurementAllowed(absolutePath: path))
        #expect(r.protectionReason(absolutePath: path) != nil)
    }
    #expect(r.allowedChildNames(absolutePath: "/System/Volumes/Data/Users/test/.codex") == ["cache"])
    #expect(r.allowedChildNames(absolutePath: "/System/Volumes/Data/Users/test/.codex/cache") == ["codex_apps_tools", "codex_apps_server_info"])
    let candidate = r.decide(relativePath: "Users/test/.codex/cache/codex_apps_tools/data", identity: identity(), absolutePath: "/System/Volumes/Data/Users/test/.codex/cache/codex_apps_tools/data")
    #expect(candidate.ruleIDs == ["RULE-AI-01"])
    #expect(candidate.capability == .previewOnly)
}
@Test func categoryClassificationNeverConfersDeletionCapability() {
    let plain = RuleDecision(disposition: .review, reasonCodes: ["noRule"], reason: "read only")
    let cases: [(String, StorageCategory)] = [("Downloads/example.dmg", .downloads), ("Pictures/example.heic", .media), ("Documents/book.pdf", .documents), ("Applications/Demo.app/Contents/binary", .applications), ("project/node_modules/file.js", .developer), ("Library/Caches/tool/file", .cache), ("Models/model.gguf", .other)]
    for (path, expected) in cases {
        #expect(StorageClassifier.category(relativePath: path, identity: identity(), decision: plain) == expected)
        #expect(plain.capability == .previewOnly)
    }
}
@Test func insightCardsComeOnlyFromMeasuredFindings() {
    let empty = StorageDashboard(summary: ScanSummary(logical: 0, allocated: 0, unknown: 0, count: 1), categories: [], topFolders: [], largeFileCount: 0, previewCandidateCount: 0, previewCandidateBytes: 0, issues: [])
    #expect(StorageInsights.make(dashboard: empty).isEmpty)
    let discovered = StorageDashboard(summary: ScanSummary(logical: 900, allocated: 800, unknown: 2, count: 9), categories: [CategorySummary(category: .downloads, allocatedBytes: 400, logicalBytes: 500, fileCount: 3)], topFolders: [], largeFileCount: 1, previewCandidateCount: 2, previewCandidateBytes: 300, issues: [])
    let insights = StorageInsights.make(dashboard: discovered)
    #expect(insights.map(\.kind) == [.candidates, .largeFiles, .downloads, .coverage])
    #expect(insights.first?.summary.contains("规则尚未准入") == true)
    #expect(insights.last?.issuesOnly == true)
    #expect(insights[1].largeOnly)
    #expect(insights[2].category == .downloads)
}

@Test func exportRedactsDataRootUserAndPrivateNames() throws {
    let scope = ScanScope(rootPath: "/System/Volumes/Data", rootIdentity: identity(kind: .directory))
    let decision = RuleDecision(disposition: .protect, reasonCodes: ["protected"], reason: "protected")
    let entry = Entry(scanID: UUID(), parentID: nil, relativePath: "Users/test-user/Documents/secret-credentials.txt", identity: identity(), logicalBytes: 1, allocatedBytes: 1, measureState: .measured, decision: decision)
    let redacted = String(decoding: try Export.report(entries: [entry], scope: scope), as: UTF8.self)
    #expect(!redacted.contains("test-user")); #expect(!redacted.contains("secret-credentials")); #expect(redacted.contains("<user>")); #expect(redacted.contains("<private>"))
    let explicit = String(decoding: try Export.report(entries: [entry], includeFullPaths: true, scope: scope), as: UTF8.self)
    #expect(explicit.contains("/System/Volumes/Data/Users/test-user/Documents/secret-credentials.txt"))
}
