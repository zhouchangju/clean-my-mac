import Foundation
import Darwin
import CleanerDomain
import CleanerCore

public struct PreflightResult: Sendable, Identifiable {
    public var id: UUID { itemID }
    public let itemID: UUID
    public let accepted: Bool
    public let reason: String
    public let code: ErrorCode?
}
public struct MacPreflight: Sendable {
    public init() {}
    public func validate(plan: CleanupPlan, run: ScanRun, selectionRevision: UInt64, ignoreRevision: UInt64, now: Date = Date()) throws -> [PreflightResult] {
        try Planner.validate(plan: plan, run: run, selectionRevision: selectionRevision, ignoreRevision: ignoreRevision, now: now)
        let reader = MacFileReader()
        guard try !reader.repositoryAncestor(scope: run.scope) else { throw CleanerError(.protected, "扫描范围位于代码仓库中，禁止执行") }
        return plan.items.map { item in
            do {
                guard item.identity.ownerUID.value == UInt64(getuid()) else { throw CleanerError(.protected, "文件所有权不符") }
                for ancestor in [""] + item.identity.parentChain.map(\.relativePath) {
                    if try reader.isRepository(scope: run.scope, relativePath: ancestor) { throw CleanerError(.protected, "代码仓库整体保护") }
                }
                let current = try reader.identity(scope: run.scope, relativePath: item.sourceRelativePath)
                guard current == item.identity else { throw CleanerError(.identityChanged, "文件或祖先目录在扫描后变化") }
                let url = URL(fileURLWithPath: run.scope.rootPath).appendingPathComponent(item.sourceRelativePath)
                let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsReadOnlyKey])
                guard values.volumeIsInternal == true, values.volumeIsLocal == true, values.volumeIsReadOnly == false else { throw CleanerError(.unsupportedVolume, "执行仅支持可写内置本地卷") }
                guard values.isUbiquitousItem == false else { throw CleanerError(.protected, "云文件或状态未知") }
                let decision = RuleEngine().decide(relativePath: item.sourceRelativePath, identity: current, absolutePath: url.path)
                guard decision.disposition != .protect && decision.disposition != .ignore else { throw CleanerError(.protected, decision.reason) }
                if plan.action == .purge && decision.capability != .purgeEligible { throw CleanerError(.protected, "规则尚未准入永久动作") }
                // Current process activity coverage cannot establish inactivity. Never infer safety.
                switch ApplicationActivityProvider.evaluate(owner: decision.owner) {
                case .active: throw CleanerError(.activeOwner, "应用正在使用")
                case .unknown: throw CleanerError(.activityUnknown, "使用状态未能确认，执行已拒绝")
                case .inactive: break
                }
                return PreflightResult(itemID: item.id, accepted: true, reason: "预检通过", code: nil)
            } catch {
                let e = error as? CleanerError
                return PreflightResult(itemID: item.id, accepted: false, reason: e?.message ?? error.localizedDescription, code: e?.code ?? .identityChanged)
            }
        }
    }
}
