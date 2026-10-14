import Foundation
import CleanerDomain
import CleanerCore

public actor ScanCoordinator {
    private let store: SQLiteScanStore
    private let rules: RuleEngine
    private let reader: MacFileReader
    private let analysisMode: Bool
    private var active = false
    private var cancelled = false
    public init(store: SQLiteScanStore, rules: RuleEngine, reader: MacFileReader = MacFileReader(), analysisMode: Bool = false) { self.store = store; self.rules = rules; self.reader = reader; self.analysisMode = analysisMode }
    public func cancel() { cancelled = true }
    public func scan(scope: ScanScope, progress: @Sendable (ScanRun) async -> Void = { _ in }) async throws -> ScanRun {
        guard !active else { throw CleanerError(.alreadyRunning, "已有扫描运行") }
        active = true; cancelled = false
        defer { active = false }
        var run = ScanRun(scope: scope, ruleSetVersion: rules.version)
        try await store.create(run)
        run.state = .running
        await progress(run)
        var batch: [Entry] = []
        var frames: [(path: String, id: UUID, cursor: DirectoryCursor, protected: Bool)] = []
        var lastCommit = ContinuousClock.now
        var lastProgress = lastCommit
        var stoppedForQuota = false
        do {
            let rootMetadata = try reader.metadata(scope: scope, relativePath: "")
            var rootDecision = rules.decide(relativePath: "", identity: rootMetadata.identity, absolutePath: scope.rootPath)
            var rootCursor: DirectoryCursor?
            var rootState: MeasureState = .measured
            var rootProtected = false
            if rules.shouldDescend(relativePath: "", absolutePath: scope.rootPath) || (analysisMode && rules.measurementAllowed(absolutePath:scope.rootPath)) {
                do {
                    if try reader.repositoryAncestor(scope:scope) || reader.isRepository(scope:scope,relativePath:"") {
                        rootProtected = true
                        rootDecision = RuleDecision(disposition:.protect,reasonCodes:["codeRepository"],reason:analysisMode ? "代码仓库仅计量，不允许清理" : "代码仓库整树已保护，未深入")
                        if analysisMode { rootCursor = try reader.directory(scope:scope,relativePath:"") }
                        else { rootState = .unsupported; run.issueCount += 1 }
                    } else {
                        rootProtected = scope.rootPath.split(separator:"/").contains { $0.hasSuffix(".app") }
                        rootCursor = try reader.directory(scope: scope, relativePath: "")
                    }
                }
                catch { rootState = .permissionDenied; run.issueCount += 1;run.stopReason=String(describing:error) }
            } else { rootState = .unsupported; run.issueCount += 1 }
            if rootState == .measured && rules.allowedChildNames(absolutePath:scope.rootPath) != nil {
                rootState = .partial; run.issueCount += 1
            }
            let root = Entry(scanID: run.id, parentID: nil, relativePath: "", identity: rootMetadata.identity, logicalBytes: nil, allocatedBytes: nil, measureState: rootState, decision: rootDecision)
            run.processedCount += 1
            try await store.insert([root])
            try await store.update(run)
            if let rootCursor { frames.append(("",root.id,rootCursor,rootProtected)) }
            while !frames.isEmpty {
                if cancelled || Task.isCancelled { break }
                let index = frames.count - 1
                let frame = frames[index]
                let name: String?
                do { name = try frame.cursor.next() }
                catch {
                    run.issueCount += 1
                    batch.append(Entry(scanID:run.id,parentID:frame.id,relativePath:frame.path.isEmpty ? "[不可读]" : frame.path + "/[不可读]",identity:nil,logicalBytes:nil,allocatedBytes:nil,measureState:.permissionDenied,decision:RuleDecision(disposition:.protect,reasonCodes:["enumerationDenied"],reason:"目录枚举不完整")))
                    frames.removeLast(); continue
                }
                guard let name else { frames.removeLast(); continue }
                if !scope.includeHidden && name.hasPrefix(".") { continue }
                if let allowed = rules.allowedChildNames(absolutePath: URL(fileURLWithPath:scope.rootPath).appendingPathComponent(frame.path).path), !allowed.contains(name) { continue }
                let path = frame.path.isEmpty ? name : frame.path + "/" + name
                let absolute = URL(fileURLWithPath: scope.rootPath).appendingPathComponent(path).path
                var identity: FileIdentity?
                var allocated: UInt64?
                var state: MeasureState = .measured
                var cursor: DirectoryCursor?
                var repository = false
                do {
                    let metadata = try reader.metadata(scope:scope,relativePath:path)
                    identity = metadata.identity; allocated = metadata.allocated
                    if metadata.identity.kind == .directory {
                        if (rules.shouldDescend(relativePath:path,absolutePath:absolute) || (analysisMode && rules.measurementAllowed(absolutePath:absolute))) && frames.count < 128 {
                            do {
                                repository = try reader.isRepository(scope:scope,relativePath:path)
                                if repository && !analysisMode { state = .unsupported }
                                else { cursor = try reader.directory(scope:scope,relativePath:path) }
                            }
                            catch { state = .permissionDenied }
                        } else { state = .unsupported }
                        allocated = nil
                    } else if metadata.identity.kind == .symlink || metadata.identity.kind == .other { state = .unsupported }
                } catch let error as CleanerError { state = error.code == .permissionDenied ? .permissionDenied : .unsupported }
                catch { state = .unknown }
                if state == .measured && identity?.kind == .directory && rules.allowedChildNames(absolutePath:absolute) != nil { state = .partial }
                if state != .measured { run.issueCount += 1 }
                let inherited = analysisMode && (frame.protected || repository || absolute.split(separator:"/").contains { $0.hasSuffix(".app") })
                let decision = inherited ? RuleDecision(disposition:.protect,reasonCodes:["protectedMeasurement"],reason:"受保护范围仅计量，不允许清理") : (repository ? RuleDecision(disposition:.protect,reasonCodes:["codeRepository"],reason:"代码仓库整树已保护，未深入") : rules.decide(relativePath:path,identity:identity,absolutePath:absolute))
                let entry = Entry(scanID:run.id,parentID:frame.id,relativePath:path,identity:identity,logicalBytes:identity?.kind == .directory ? nil : identity?.size.value,allocatedBytes:allocated,measureState:state,decision:decision)
                batch.append(entry); run.processedCount += 1
                if let cursor { frames.append((path,entry.id,cursor,inherited)) }
                let now = ContinuousClock.now
                if batch.count >= 200 || lastCommit.duration(to:now) >= .milliseconds(200) {
                    try await store.insert(batch); batch.removeAll(keepingCapacity:true)
                    try await store.update(run); lastCommit = now
                    if lastProgress.duration(to:now) >= .milliseconds(200) { await progress(run); lastProgress = now }
                }
                if run.processedCount % 32 == 0 { await Task.yield() }
            }
        } catch let error as CleanerError {
            run.issueCount += 1;run.stopReason=error.description
            if error.code == .quotaExceeded { stoppedForQuota = true; batch.removeAll() }
            else { run.state = .failed }
        } catch { run.issueCount += 1; run.state = .failed;run.stopReason=String(describing:error) }
        frames.removeAll()
        if !batch.isEmpty {
            do { try await store.insert(batch) } catch { run.issueCount += 1; stoppedForQuota = true;run.stopReason=String(describing:error) }
        }
        if cancelled || Task.isCancelled { run.state = .cancelled;run.stopReason="扫描已取消，剩余范围未计量" }
        else if run.state != .failed { run.state = stoppedForQuota || run.issueCount > 0 ? .partial : .completed }
        run.finishedAt = Date()
        try await store.update(run)
        await progress(run)
        return run
    }
}
