import Foundation

/// JSON integers are always decimal strings, never floating point JSON numbers.
public struct Decimal64: Codable, Sendable, Hashable, Comparable {
    public let value: UInt64
    public init(_ value: UInt64) { self.value = value }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard !s.isEmpty, s.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let n = UInt64(s), String(n) == s else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "invalid decimal UInt64")
        }
        value = n
    }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(String(value)) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}
public enum FileKind: String, Codable, Sendable { case regular, directory, symlink, other }
public enum MeasureState: String, Codable, Sendable { case measured, partial, permissionDenied, cancelled, unsupported, unknown }
public enum ScanState: String, Codable, Sendable { case idle, preparing, running, completed, partial, cancelled, failed }
public enum Disposition: String, Codable, Sendable { case protect, ignore, descend, review, candidate }
public enum Capability: String, Codable, Sendable { case previewOnly, trashEligible, purgeEligible }
public enum Activity: String, Codable, Sendable { case active, inactive, unknown }
public enum CleanupAction: String, Codable, Sendable { case trash, purge }
public enum ItemState: String, Codable, Sendable { case pending, prechecked, staged, trashed, purged, rejected, restored, restoreConflict, interruptedUnknown }
public enum TransactionState: String, Codable, Sendable { case prepared, executing, completed, partial, cancelled, needsRecovery }
public enum ErrorCode: String, Codable, Sendable {
    case invalidInput, permissionDenied, scopeEscape, unsupportedVolume, protected, activeOwner, activityUnknown
    case identityChanged, planExpired, rulesChanged, insufficientJournalSpace, stagingMismatch, restoreConflict, interruptedUnknown
    case executionDisabled, invalidPlan, alreadyRunning, quotaExceeded
}
public struct CleanerError: Error, Codable, Sendable, CustomStringConvertible {
    public let code: ErrorCode
    public let message: String
    public init(_ code: ErrorCode, _ message: String) { self.code = code; self.message = message }
    public var description: String { "\(code.rawValue): \(message)" }
}
public struct AncestorIdentity: Codable, Sendable, Equatable {
    public let relativePath: String
    public let device: Decimal64
    public let inode: Decimal64
    public init(relativePath: String, device: UInt64, inode: UInt64) {
        self.relativePath = relativePath; self.device = Decimal64(device); self.inode = Decimal64(inode)
    }
}
public struct FileIdentity: Codable, Sendable, Equatable {
    public let volumeID: String
    public let device: Decimal64
    public let inode: Decimal64
    public let kind: FileKind
    public let size: Decimal64
    public let mtimeNs: String
    public let ctimeNs: String
    public let linkCount: Decimal64
    public let ownerUID: Decimal64
    public let parentChain: [AncestorIdentity]
    public init(volumeID: String, device: UInt64, inode: UInt64, kind: FileKind, size: UInt64, mtimeNs: String, ctimeNs: String, linkCount: UInt64, ownerUID: UInt64, parentChain: [AncestorIdentity]) {
        self.volumeID = volumeID; self.device = Decimal64(device); self.inode = Decimal64(inode); self.kind = kind
        self.size = Decimal64(size); self.mtimeNs = mtimeNs; self.ctimeNs = ctimeNs; self.linkCount = Decimal64(linkCount)
        self.ownerUID = Decimal64(ownerUID); self.parentChain = parentChain
    }
    public func sameObject(as other: Self) -> Bool { device == other.device && inode == other.inode && kind == other.kind }
}
public struct ScanScope: Codable, Sendable, Identifiable {
    public let id: UUID
    public let rootPath: String
    public let rootIdentity: FileIdentity
    public let policyVersion: String
    public let includeHidden: Bool
    public let createdAt: Date
    public init(id: UUID = UUID(), rootPath: String, rootIdentity: FileIdentity, includeHidden: Bool = true) {
        self.id = id; self.rootPath = rootPath; self.rootIdentity = rootIdentity; policyVersion = "1"; self.includeHidden = includeHidden; createdAt = Date()
    }
}
public struct RuleDecision: Codable, Sendable, Equatable {
    public let ruleIDs: [String]
    public let category: String
    public let disposition: Disposition
    public let capability: Capability
    public let reasonCodes: [String]
    public let reason: String
    public let owner: String
    public let activity: Activity
    public let rebuildCost: String
    public init(ruleIDs: [String] = [], category: String = "空间占用", disposition: Disposition, capability: Capability = .previewOnly, reasonCodes: [String], reason: String, owner: String = "未知", activity: Activity = .unknown, rebuildCost: String = "未知") {
        self.ruleIDs = ruleIDs; self.category = category; self.disposition = disposition; self.capability = capability
        self.reasonCodes = reasonCodes; self.reason = reason; self.owner = owner; self.activity = activity; self.rebuildCost = rebuildCost
    }
}
public struct Entry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let scanID: UUID
    public let parentID: UUID?
    public let relativePath: String
    public let identity: FileIdentity?
    public let logicalBytes: Decimal64?
    public let allocatedBytes: Decimal64?
    public let measureState: MeasureState
    public let decision: RuleDecision
    public var selectable: Bool { identity?.kind == .regular && identity?.linkCount.value == 1 && (decision.disposition == .candidate || decision.disposition == .review) && decision.capability != .previewOnly }
    public init(id: UUID = UUID(), scanID: UUID, parentID: UUID?, relativePath: String, identity: FileIdentity?, logicalBytes: UInt64?, allocatedBytes: UInt64?, measureState: MeasureState, decision: RuleDecision) {
        self.id = id; self.scanID = scanID; self.parentID = parentID; self.relativePath = relativePath; self.identity = identity
        self.logicalBytes = logicalBytes.map(Decimal64.init); self.allocatedBytes = allocatedBytes.map(Decimal64.init)
        self.measureState = measureState; self.decision = decision
    }
}
public struct ScanRun: Codable, Sendable, Identifiable {
    public let id: UUID
    public let scope: ScanScope
    public let ruleSetVersion: String
    public var state: ScanState
    public var processedCount: UInt64
    public var issueCount: UInt64
    public let startedAt: Date
    public var finishedAt: Date?
    public var stopReason: String?
    public init(id: UUID = UUID(), scope: ScanScope, ruleSetVersion: String) {
        self.id = id; self.scope = scope; self.ruleSetVersion = ruleSetVersion; state = .preparing
        processedCount = 0; issueCount = 0; startedAt = Date(); finishedAt = nil; stopReason = nil
    }
}
public struct ScanSummary: Sendable {
    public let knownLogicalBytes: UInt64
    public let knownAllocatedBytes: UInt64
    public let unknownCount: UInt64
    public let entryCount: UInt64
    public init(logical: UInt64, allocated: UInt64, unknown: UInt64, count: UInt64) {
        knownLogicalBytes = logical; knownAllocatedBytes = allocated; unknownCount = unknown; entryCount = count
    }
}
public struct Selection: Sendable {
    public let scanID: UUID
    public private(set) var ids: Set<UUID> = []
    public private(set) var revision: UInt64 = 0
    public init(scanID: UUID) { self.scanID = scanID }
    public mutating func set(_ entry: Entry, selected: Bool) throws {
        guard entry.scanID == scanID, entry.selectable else { throw CleanerError(.protected, "此项不可选择") }
        if selected { ids.insert(entry.id) } else { ids.remove(entry.id) }; revision += 1
    }
    public mutating func clear() { ids.removeAll(); revision += 1 }
}
public struct IgnoreEntry: Codable, Sendable, Identifiable {
    public enum ScopeKind: String, Codable, Sendable { case exactPath, subtree, appID, ruleID }
    public let id: UUID
    public let scopeKind: ScopeKind
    public let matchValue: String
    public let createdAt: Date
    public let enabled: Bool
    public init(scopeKind: ScopeKind, matchValue: String, enabled: Bool = true) {
        id = UUID(); self.scopeKind = scopeKind; self.matchValue = matchValue; createdAt = Date(); self.enabled = enabled
    }
}
public struct PlanItem: Codable, Sendable, Identifiable {
    public var id: UUID { candidateID }
    public let candidateID: UUID
    public let sourceRelativePath: String
    public let rootID: UUID
    public let identity: FileIdentity
    public let ruleIDs: [String]
    public let approvedAction: CleanupAction
    public let estimate: Decimal64?
    public init(entry: Entry, rootID: UUID, action: CleanupAction) throws {
        guard let identity = entry.identity else { throw CleanerError(.invalidPlan, "缺少文件身份") }
        candidateID = entry.id; sourceRelativePath = entry.relativePath; self.rootID = rootID; self.identity = identity
        ruleIDs = entry.decision.ruleIDs; approvedAction = action; estimate = action == .purge ? entry.allocatedBytes : nil
    }
}
public struct CleanupPlan: Codable, Sendable, Identifiable {
    public let id: UUID
    public let schemaVersion: Int
    public let scanID: UUID
    public let scopeID: UUID
    public let ruleSetVersion: String
    public let ignoreRevision: Decimal64
    public let selectionRevision: Decimal64
    public let action: CleanupAction
    public let items: [PlanItem]
    public var hash: String
    public let createdAt: Date
    public let expiresAt: Date
    public init(id: UUID = UUID(), scanID: UUID, scopeID: UUID, ruleSetVersion: String, ignoreRevision: UInt64, selectionRevision: UInt64, action: CleanupAction, items: [PlanItem], createdAt: Date) {
        self.id = id; schemaVersion = 1; self.scanID = scanID; self.scopeID = scopeID; self.ruleSetVersion = ruleSetVersion
        self.ignoreRevision = Decimal64(ignoreRevision); self.selectionRevision = Decimal64(selectionRevision); self.action = action
        self.items = items.sorted { $0.candidateID.uuidString < $1.candidateID.uuidString }; hash = ""
        self.createdAt = createdAt; expiresAt = createdAt.addingTimeInterval(600)
    }
}
public struct ItemReceipt: Codable, Sendable, Identifiable {
    public let id: UUID
    public let originalPath: String
    public var stagedPath: String?
    public var trashPath: String?
    public var state: ItemState
    public let identityBefore: FileIdentity
    public var error: String?
    public var updatedAt: Date
    public init(item: PlanItem, originalPath: String) {
        id = item.id; self.originalPath = originalPath; identityBefore = item.identity; state = .pending; updatedAt = Date()
    }
}
public struct Transaction: Codable, Sendable, Identifiable {
    public let id: UUID
    public let planID: UUID
    public let planHash: String
    public let action: CleanupAction
    public var state: TransactionState
    public var items: [ItemReceipt]
    public let createdAt: Date
    public var volumeSampleBefore: Decimal64?
    public var volumeSampleAfter: Decimal64?
    public init(plan: CleanupPlan, scope: ScanScope) {
        id = UUID(); planID = plan.id; planHash = plan.hash; action = plan.action; state = .prepared; createdAt = Date()
        items = plan.items.map { ItemReceipt(item: $0, originalPath: URL(fileURLWithPath: scope.rootPath).appendingPathComponent($0.sourceRelativePath).path) }
    }
}
public enum Codec {
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; e.dateEncodingStrategy = .iso8601; return e }
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
public protocol FileSystemReader: Sendable {
    func scope(path: String) throws -> ScanScope
    func identity(scope: ScanScope, relativePath: String) throws -> FileIdentity
}
public protocol ScanStore: Actor {
    func create(_ run: ScanRun) throws
    func insert(_ entries: [Entry]) throws
    func update(_ run: ScanRun) throws
    func page(scanID: UUID, offset: Int, limit: Int, parentID: UUID?, search: String, candidatesOnly: Bool, largeOnly: Bool) throws -> [Entry]
    func entries(scanID: UUID, ids: Set<UUID>) throws -> [Entry]
    func summary(scanID: UUID) throws -> ScanSummary
}
