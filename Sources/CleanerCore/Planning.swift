import Foundation
import CryptoKit
import CleanerDomain

public enum Planner {
    public static func canonicalPayload(_ plan: CleanupPlan) throws -> Data {
        let encoded = try Codec.encoder().encode(plan)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { throw CleanerError(.invalidPlan, "无法规范化计划") }
        object.removeValue(forKey: "hash")
        // Explicit nulls for optional values, independent of synthesized Codable omission.
        if var items = object["items"] as? [[String: Any]] {
            for n in items.indices { if items[n]["estimate"] == nil { items[n]["estimate"] = NSNull() } }
            object["items"] = items
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    public static func hash(_ plan: CleanupPlan) throws -> String { SHA256.hash(data: try canonicalPayload(plan)).map { String(format: "%02x", $0) }.joined() }
    public static func make(run: ScanRun, entries: [Entry], selection: Selection, action: CleanupAction, ignoreRevision: UInt64, now: Date = Date()) throws -> CleanupPlan {
        guard selection.scanID == run.id, !selection.ids.isEmpty, run.state == .completed || run.state == .partial || run.state == .cancelled else { throw CleanerError(.invalidPlan, "需扫描结束并明确选择文件") }
        let selected = entries.filter { selection.ids.contains($0.id) }
        guard selected.count == selection.ids.count, Set(selected.map(\.id)).count == selected.count else { throw CleanerError(.invalidPlan, "选择与扫描结果不一致") }
        for entry in selected {
            guard entry.scanID == run.id, entry.selectable, entry.identity?.kind == .regular, entry.identity?.linkCount.value == 1, validRelativePath(entry.relativePath) else { throw CleanerError(.protected, "受保护或不可操作项：\(entry.relativePath)") }
            if action == .purge && entry.decision.capability != .purgeEligible { throw CleanerError(.protected, "永久动作要求已准入缓存规则") }
        }
        var plan = CleanupPlan(scanID: run.id, scopeID: run.scope.id, ruleSetVersion: run.ruleSetVersion, ignoreRevision: ignoreRevision, selectionRevision: selection.revision, action: action, items: try selected.map { try PlanItem(entry: $0, rootID: run.scope.id, action: action) }, createdAt: now)
        plan.hash = try hash(plan); return plan
    }
    public static func validate(plan: CleanupPlan, run: ScanRun, selectionRevision: UInt64, ignoreRevision: UInt64, now: Date = Date()) throws {
        guard plan.schemaVersion == 1, !plan.items.isEmpty, plan.hash == (try hash(plan)), plan.scopeID == run.scope.id, plan.scanID == run.id,
              Set(plan.items.map(\.id)).count == plan.items.count,
              plan.items.allSatisfy({ $0.rootID == run.scope.id && $0.approvedAction == plan.action && validRelativePath($0.sourceRelativePath) && $0.identity.kind == .regular && $0.identity.linkCount.value == 1 }) else { throw CleanerError(.invalidPlan, "计划内容无效或已变化") }
        guard now < plan.expiresAt, now >= plan.createdAt else { throw CleanerError(.planExpired, "计划已过期，需重新预览") }
        guard plan.ruleSetVersion == run.ruleSetVersion, plan.selectionRevision.value == selectionRevision, plan.ignoreRevision.value == ignoreRevision else { throw CleanerError(.rulesChanged, "选择、规则或忽略已变化") }
    }
    public static func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
@MainActor public final class IgnoreStore {
    public private(set) var entries: [IgnoreEntry]
    public private(set) var revision: UInt64
    private let url: URL
    private struct Saved: Codable { let revision: Decimal64; let entries: [IgnoreEntry] }
    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let saved = try Codec.decoder().decode(Saved.self, from: Data(contentsOf: url)); entries = saved.entries; revision = saved.revision.value
        } else { entries = []; revision = 0 }
    }
    public func add(_ entry: IgnoreEntry) throws { try save(entries + [entry]) }
    public func remove(_ id: UUID) throws { try save(entries.filter { $0.id != id }) }
    private func save(_ next: [IgnoreEntry]) throws {
        let increment = revision.addingReportingOverflow(1)
        guard !increment.overflow else { throw CleanerError(.invalidInput, "忽略版本溢出") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Codec.encoder().encode(Saved(revision: Decimal64(increment.partialValue), entries: next)).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        entries = next; revision = increment.partialValue
    }
}
public enum Export {
    private static func redactedRelativePath(_ path: String) -> String {
        var segments = path.split(separator: "/").map(String.init)
        let user = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        for index in segments.indices {
            if index > 0 && segments[index - 1] == "Users" { segments[index] = "<user>" }
            else if !user.isEmpty { segments[index] = segments[index].replacingOccurrences(of: user, with: "<user>") }
            if ["secret", "password", "credential", "token", "api_key", "id_rsa", "auth.json"].contains(where: { segments[index].lowercased().contains($0) }) { segments[index] = "<private>" }
        }
        return segments.joined(separator: "/")
    }
    public static func report(entries: [Entry], includeFullPaths: Bool = false, scope: ScanScope) throws -> Data {
        struct Row: Encodable { let path: String; let logicalBytes: Decimal64?; let allocatedBytes: Decimal64?; let state: MeasureState; let reasons: [String] }
        return try Codec.encoder().encode(entries.map { Row(path: includeFullPaths ? URL(fileURLWithPath: scope.rootPath).appendingPathComponent($0.relativePath).path : redactedRelativePath($0.relativePath), logicalBytes: $0.logicalBytes, allocatedBytes: $0.allocatedBytes, state: $0.measureState, reasons: $0.decision.reasonCodes) })
    }
}
