import Foundation
import Testing
import CleanerDomain
@testable import CleanerCore
import CleanerTestSupport

@Test func decimalCodecRejectsLossyOrInvalid() throws {
    let max = try Codec.decoder().decode(Decimal64.self, from: Data("\"18446744073709551615\"".utf8))
    #expect(max.value == UInt64.max)
    for raw in ["123", "\"18446744073709551616\"", "\"-1\"", "\"01\"", "\"1.1\""] {
        #expect(throws: (any Error).self) { try Codec.decoder().decode(Decimal64.self, from: Data(raw.utf8)) }
    }
}
@Test func seedRulesAreStrictAndBadRevisionKeepsPrevious() throws {
    // T4 扩充：4 条原种子 + 9 条新规则（DEV-03..06 / MOB-01..02 / NET-01..02 / MAIL-01）= 13。
    let old = RuleEngine(); #expect(old.ruleSet?.rules.count == 13)
    for mutation in ["enabled", "schemaVersion", "matcher", "roots"] {
        var json = try JSONSerialization.jsonObject(with: RuleEngine.seedData) as! [String: Any]
        var rules = json["rules"] as! [[String: Any]]
        switch mutation {
        case "enabled": rules[0]["enabled"] = "false"
        case "schemaVersion": json["schemaVersion"] = 99
        case "matcher": rules[0]["matcher"] = "regex"
        default: rules[0]["roots"] = [[".."]]
        }
        json["rules"] = rules
        let bytes = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try RuleSet.load(bytes) }
        #expect(RuleEngine(data: bytes, previous: old).version == old.version)
        #expect(RuleEngine(data: bytes).ruleSet == nil)
    }
}
func identity(size: UInt64 = 512 * 1024 * 1024, links: UInt64 = 1, kind: FileKind = .regular) -> FileIdentity {
    FileIdentity(volumeID: "test", device: 1, inode: 2, kind: kind, size: size, mtimeNs: "1", ctimeNs: "1", linkCount: links, ownerUID: 501, parentChain: [])
}
@Test func protectionAndThresholdIndependentTable() {
    let r = RuleEngine(homePath: "/fixture")
    let cases: [(String, Disposition)] = [("/fixture/.ssh/cache", .protect), ("/fixture/.codex/sessions/cache", .protect), ("/fixture/.codex/cache/codex_apps_tools", .candidate), ("/fixture/Library/Developer/Xcode/DerivedData/p/Build/Intermediates.noindex/a.o", .candidate), ("/fixture/Library/Developer/Xcode/Archives/a.o", .protect), ("/fixture/data.bin", .review)]
    for (path, expected) in cases { #expect(r.decide(relativePath: path, identity: identity(), absolutePath: path).disposition == expected) }
    for size in [UInt64(536870911), 536870912, 536870913] {
        let d = r.decide(relativePath: "file", identity: identity(size: size), absolutePath: "/fixture/file")
        #expect(d.capability == (size >= 536870912 ? .trashEligible : .previewOnly))
    }
    #expect(r.decide(relativePath: "data", identity: identity(links: 2), absolutePath: "/fixture/data").disposition == .protect)
    #expect(!r.shouldDescend(relativePath: ".ssh", absolutePath: "/fixture/.ssh"))
    #expect(r.allowedChildNames(absolutePath: "/fixture/.codex") == ["cache"])
}
/// T4 新增种子规则与备份保护：加载即严格校验；decide 对代表路径给出预期 disposition。
/// 注意：当前 decide 仅实现 roots 前缀匹配，segmentGlob/extensionSet 规则在引擎补齐语义前保持休眠（回落 noRule=review，fail-closed）。
@Test func t4SeedRulesDecideAndMobileSyncProtection() throws {
    let r = RuleEngine(homePath: "/fixture")
    let rules = try #require(r.ruleSet?.rules)
    let t4 = ["RULE-DEV-03", "RULE-DEV-04", "RULE-DEV-05", "RULE-DEV-06", "RULE-MOB-01", "RULE-MOB-02", "RULE-NET-01", "RULE-NET-02", "RULE-MAIL-01"]
    #expect(Set(rules.map(\.id)).isSuperset(of: t4))
    #expect(rules.allSatisfy { $0.capability == .previewOnly && $0.enabled })
    #expect(rules.first { $0.id == "RULE-DEV-04" }?.disposition == .review)
    #expect(rules.first { $0.id == "RULE-NET-02" }?.matcher == "segmentGlob"); #expect(rules.first { $0.id == "RULE-MOB-02" }?.matcher == "extensionSet")
    let small = identity(size: 4096) // 低于大文件阈值，避免 RULE-USER-01 干扰
    let cases: [(String, Disposition, String?)] = [
        ("/fixture/Library/Developer/Xcode/iOS DeviceSupport/17.0 (21A328)/Symbols/usr/lib/a.dylib", .candidate, "RULE-DEV-03"),
        ("/fixture/Library/Developer/Xcode/Archives/2026-10-01/App.xcarchive/Info.plist", .protect, nil), // DEV-04 被硬保护表 Archives 段覆盖（预期休眠）
        ("/fixture/Library/Developer/CoreSimulator/Caches/dyld/a", .candidate, "RULE-DEV-05"),
        ("/fixture/Library/Caches/com.bohemiancoding.sketch3/thumb.png", .candidate, "RULE-DEV-06"),
        ("/fixture/Pictures/iPod Photo Cache/F00/IMG_0001.ithmb", .candidate, "RULE-MOB-01"),
        ("/fixture/Library/Caches/com.apple.Safari/Cache.db", .candidate, "RULE-NET-01"),
        ("/fixture/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/x/a.pdf", .candidate, "RULE-MAIL-01"),
        ("/fixture/Library/Caches/Google/Chrome/Default/Cache/f_000001", .review, nil),            // NET-02 segmentGlob 休眠 → noRule
        ("/fixture/Library/iTunes/iPhone Software Updates/iPhone16,1_18.0.ipsw", .review, nil),  // MOB-02 extensionSet 休眠 → noRule
        ("/fixture/Library/Application Support/MobileSync/Backup/00008030-ABC/Manifest.db", .protect, nil), // 新增备份保护
        ("/System/Volumes/Data/fixture/Library/Application Support/MobileSync/Backup/x/Info.plist", .protect, nil), // Data 卷前缀同样生效
    ]
    for (path, expected, ruleID) in cases {
        let d = r.decide(relativePath: path, identity: small, absolutePath: path)
        #expect(d.disposition == expected, "\(path)")
        if let ruleID { #expect(d.ruleIDs == [ruleID], "\(path)") } else { #expect(d.ruleIDs.isEmpty, "\(path)") }
    }
    #expect(r.protectionReason(absolutePath: "/fixture/Library/Application Support/MobileSync/Backup") == "iOS 设备备份已保护")
    #expect(r.protectionReason(absolutePath: "/fixture/Library/Application Support/MobileSync") == nil)      // 仅 Backup 子树受保护
    #expect(r.protectionReason(absolutePath: "/fixture/Documents/MobileSync/notes.txt") == nil)                // 单独 MobileSync 段不触发
    #expect(!r.shouldDescend(relativePath: "", absolutePath: "/fixture/Library/Application Support/MobileSync/Backup"))
}
@Test func planSelectionTTLAndHash() throws {
    let scope = ScanScope(rootPath: "/fixture", rootIdentity: identity(kind: .directory))
    var run = ScanRun(scope: scope, ruleSetVersion: "1"); run.state = .completed
    let entry = Entry(scanID: run.id, parentID: nil, relativePath: "big", identity: identity(), logicalBytes: 536870912, allocatedBytes: 4096, measureState: .measured, decision: RuleDecision(disposition: .review, capability: .trashEligible, reasonCodes: ["manual"], reason: "manual"))
    var selection = Selection(scanID: run.id); #expect(selection.ids.isEmpty)
    try selection.set(entry, selected: true); try selection.set(entry, selected: true); #expect(selection.ids.count == 1)
    let clock = Date(timeIntervalSince1970: 1000000000)
    let plan = try Planner.make(run: run, entries: [entry], selection: selection, action: .trash, ignoreRevision: 0, now: clock)
    #expect(plan.items[0].estimate == nil)
    #expect(throws: (any Error).self) { try Planner.make(run: run, entries: [entry], selection: selection, action: .purge, ignoreRevision: 0, now: clock) }
    try Planner.validate(plan: plan, run: run, selectionRevision: selection.revision, ignoreRevision: 0, now: clock.addingTimeInterval(599))
    #expect(throws: (any Error).self) { try Planner.validate(plan: plan, run: run, selectionRevision: selection.revision, ignoreRevision: 0, now: clock.addingTimeInterval(600)) }
    #expect(throws: (any Error).self) { try Planner.validate(plan: plan, run: run, selectionRevision: selection.revision, ignoreRevision: 1, now: clock) }
    var bad = plan; bad.hash = "tampered"
    #expect(throws: (any Error).self) { try Planner.validate(plan: bad, run: run, selectionRevision: selection.revision, ignoreRevision: 0, now: clock) }
    #expect(!Planner.validRelativePath("../secret")); #expect(!Planner.validRelativePath("/secret"))
    let protected = Entry(scanID: run.id, parentID: nil, relativePath: ".ssh/key", identity: identity(), logicalBytes: 1, allocatedBytes: 1, measureState: .measured, decision: RuleDecision(disposition: .protect, reasonCodes: ["protected"], reason: "protected"))
    #expect(throws: (any Error).self) { try selection.set(protected, selected: true) }
}
@Test @MainActor func ignorePersistence() throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    let url = fixture.root.appendingPathComponent("state/ignore.json")
    let store = try IgnoreStore(url: url); let item = IgnoreEntry(scopeKind: .subtree, matchValue: "/fixture/data")
    try store.add(item); #expect(store.revision == 1)
    let reopened = try IgnoreStore(url: url); #expect(reopened.entries.count == 1)
    try reopened.remove(item.id); #expect(reopened.revision == 2)
}

@Test func canonicalPlanIndependentVector() throws {
    func uuid(_ suffix: String) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-00000000000" + suffix)! }
    let e = Entry(id: uuid("3"), scanID: uuid("2"), parentID: nil, relativePath: "big", identity: identity(), logicalBytes: 536870912, allocatedBytes: 4096, measureState: .measured, decision: RuleDecision(disposition: .review, capability: .trashEligible, reasonCodes: ["manual"], reason: "manual"))
    let p = CleanupPlan(id: uuid("4"), scanID: uuid("2"), scopeID: uuid("1"), ruleSetVersion: "1", ignoreRevision: 0, selectionRevision: 1, action: .trash, items: [try PlanItem(entry: e, rootID: uuid("1"), action: .trash)], createdAt: Date(timeIntervalSince1970: 1000000000))
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("TestSupport")
    let expected = try Data(contentsOf: root.appendingPathComponent("plan-vector-v1.json"))
    let expectedHash = try String(contentsOf: root.appendingPathComponent("plan-vector-v1.sha256"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(try Planner.canonicalPayload(p) == expected)
    #expect(try Planner.hash(p) == expectedHash)
}
