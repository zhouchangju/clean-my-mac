import Testing
import Foundation
import Darwin
import CleanerDomain
import CleanerCore
import CleanerMacPlatform
import CleanerTestSupport

@Test func anchoredMetadataRejectsLinksAndEscape() throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    let canonical = fixture.root.resolvingSymlinksInPath()
    _ = try fixture.file("sub/a", contents:Data(repeating:65,count:4096))
    try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("link").path, withDestinationPath: "/etc")
    let reader = MacFileReader(); let scope = try reader.scope(path:canonical.path)
    let identity = try reader.identity(scope:scope,relativePath:"sub/a")
    #expect(identity.size.value == 4096)
    #expect(identity.parentChain.count == 2)
    #expect(try reader.identity(scope:scope,relativePath:"link").kind == .symlink)
    #expect(throws: CleanerError.self) { try reader.identity(scope:scope,relativePath:"link/passwd") }
    #expect(throws: CleanerError.self) { try reader.identity(scope:scope,relativePath:"../outside") }
    #expect(throws: CleanerError.self) { try reader.scope(path:canonical.appendingPathComponent("link").path) }
}

@Test func scanUsesRealMetadataDeduplicatesAndPreservesProtection() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    let root = fixture.root.resolvingSymlinksInPath()
    let file = try fixture.file("sub/a", contents:Data(repeating:65,count:4096))
    try FileManager.default.linkItem(at:file,to:fixture.root.appendingPathComponent("hard"))
    _ = try fixture.sparse("large",size:512*1024*1024)
    _ = try fixture.file(".ssh/secret")
    _ = try fixture.file(".codex/auth.json")
    _ = try fixture.file(".codex/cache/codex_apps_tools/tool")
    let dbFixture = try Fixture(); defer { try? dbFixture.cleanup() }
    let store = try SQLiteScanStore(url: dbFixture.root.appendingPathComponent("index.sqlite"))
    let reader = MacFileReader(); let scope = try reader.scope(path:root.path)
    let coordinator = ScanCoordinator(store:store,rules:RuleEngine(homePath:scope.rootPath))
    let run = try await coordinator.scan(scope:scope)
    let entries = try await store.page(scanID:run.id,offset:0,limit:1000)
    #expect(entries.contains { $0.relativePath == "sub/a" })
    #expect(!entries.contains { $0.relativePath == ".ssh/secret" })
    #expect(!entries.contains { $0.relativePath == ".codex/auth.json" })
    #expect(entries.contains { $0.relativePath == ".codex/cache/codex_apps_tools/tool" })
    let summary = try await store.summary(scanID:run.id)
    let counted = entries.filter { $0.identity?.kind != .directory }.reduce(into: [String:Entry]()) { result,e in if let i=e.identity { result["\(i.device.value):\(i.inode.value)"]=e } }
    #expect(summary.knownLogicalBytes == counted.values.reduce(0) { $0 + ($1.logicalBytes?.value ?? 0) })
    #expect(summary.knownAllocatedBytes == counted.values.reduce(0) { $0 + ($1.allocatedBytes?.value ?? 0) })
    #expect(run.state == .partial)
    #expect(summary.unknownCount > 0)
    #expect(try Data(contentsOf:file) == Data(repeating:65,count:4096))
    let sparse = try #require(entries.first { $0.relativePath == "large" })
    #expect(sparse.logicalBytes?.value == 536870912)
    var s = stat(); #expect(lstat(root.appendingPathComponent("large").path,&s)==0)
    #expect(sparse.allocatedBytes?.value == UInt64(s.st_blocks)*512)
    let large = try await store.page(scanID:run.id,offset:0,limit:20,largeOnly:true)
    #expect(large.map(\.relativePath) == ["large"])
    var permissions = stat(); #expect(lstat(dbFixture.root.appendingPathComponent("index.sqlite").path,&permissions)==0)
    #expect(permissions.st_mode & 0o777 == 0o600)
}

@Test func quotaStopsScanAndKeepsPartialIndex() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    _ = try fixture.file("leaf")
    let dbFixture = try Fixture(); defer { try? dbFixture.cleanup() }
    let store = try SQLiteScanStore(url:dbFixture.root.appendingPathComponent("index.sqlite"),quotaBytes:1)
    let reader = MacFileReader()
    let run = try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:reader.scope(path:fixture.root.resolvingSymlinksInPath().path))
    #expect(run.state == .partial)
    #expect(run.issueCount > 0)
}

@Test func cancellationStopsAndRejectsConcurrentRun() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    for i in 0..<500 { _ = try fixture.file("files/\(i)") }
    let dbFixture = try Fixture(); defer { try? dbFixture.cleanup() }
    let store = try SQLiteScanStore(url:dbFixture.root.appendingPathComponent("index.sqlite"))
    let reader = MacFileReader(), scope = try reader.scope(path:fixture.root.path)
    let coordinator = ScanCoordinator(store:store,rules:RuleEngine())
    let started = ContinuousClock.now
    let run = try await coordinator.scan(scope:scope) { event in
        if event.state == .running {
            do { _ = try await coordinator.scan(scope:scope); Issue.record("并发扫描不应成功") }
            catch let error as CleanerError { #expect(error.code == .alreadyRunning) }
            catch { Issue.record("意外错误 \(error)") }
            await coordinator.cancel()
        }
    }
    #expect(run.state == .cancelled)
    #expect(started.duration(to:.now) < .seconds(2))
    #expect(try await store.summary(scanID:run.id).entryCount == 1)
    let next = try await coordinator.scan(scope:scope)
    #expect(next.state == .completed)
    #expect(try await store.run(id:run.id)?.state == .cancelled)
    #expect(try await store.summary(scanID:next.id).entryCount == 503)
}

@Test func integerOverflowRejectedWithoutPartialBatch() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    let store = try SQLiteScanStore(url:fixture.root.appendingPathComponent("index.sqlite"))
    let reader = MacFileReader(), scope = try reader.scope(path:fixture.root.path)
    let run = ScanRun(scope:scope,ruleSetVersion:"test")
    try await store.create(run)
    let identity = FileIdentity(volumeID:"test",device:1,inode:1,kind:.regular,size:UInt64.max,mtimeNs:"0",ctimeNs:"0",linkCount:1,ownerUID:0,parentChain:[])
    let entry = Entry(scanID:run.id,parentID:nil,relativePath:"overflow",identity:identity,logicalBytes:UInt64.max,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.review,reasonCodes:[],reason:"fixture"))
    await #expect(throws:CleanerError.self) { try await store.insert([entry]) }
    #expect(try await store.summary(scanID:run.id).entryCount == 0)
}

@Test func repositoryRootsAndWorktreesAreProtectedWithoutContentReads() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    _ = try fixture.file("repo/.git/config")
    _ = try fixture.sparse("repo/source.bin",size:536870912)
    _ = try fixture.file("worktree/.git",contents:Data("gitdir: external-secret-do-not-open".utf8))
    _ = try fixture.sparse("worktree/source.bin",size:536870912)
    let dbFixture = try Fixture(); defer { try? dbFixture.cleanup() }
    let store = try SQLiteScanStore(url:dbFixture.root.appendingPathComponent("index.sqlite"))
    let reader = MacFileReader(), scope = try reader.scope(path:fixture.root.path)
    #expect(try reader.isRepository(scope:scope,relativePath:"repo"))
    #expect(try reader.isRepository(scope:scope,relativePath:"worktree"))
    let coordinator = ScanCoordinator(store:store,rules:RuleEngine())
    let run = try await coordinator.scan(scope:scope)
    let rows = try await store.page(scanID:run.id,offset:0,limit:100)
    #expect(!rows.contains { $0.relativePath.hasSuffix("source.bin") })
    #expect(rows.filter { $0.relativePath == "repo" || $0.relativePath == "worktree" }.allSatisfy { $0.decision.disposition == .protect && $0.measureState == .unsupported })
    let selected = try reader.scope(path:fixture.root.appendingPathComponent("repo").path)
    let protectedRun = try await coordinator.scan(scope:selected)
    #expect(protectedRun.state == .partial)
    #expect(try await store.summary(scanID:protectedRun.id).entryCount == 1)
}


@Test func selectingRepositoryDescendantCannotBypassProtection() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    _ = try fixture.file("repo/.git/config")
    _ = try fixture.sparse("repo/src/source.bin",size:536870912)
    _ = try fixture.file("worktree/.git",contents:Data("gitdir: must-not-read".utf8))
    _ = try fixture.sparse("worktree/src/source.bin",size:536870912)
    let dbFixture = try Fixture(); defer { try? dbFixture.cleanup() }
    let reader = MacFileReader()
    let store = try SQLiteScanStore(url:dbFixture.root.appendingPathComponent("index.sqlite"))
    let coordinator = ScanCoordinator(store:store,rules:RuleEngine())
    for root in ["repo/src","worktree/src"] {
        let scope = try reader.scope(path:fixture.root.appendingPathComponent(root).path)
        #expect(try reader.repositoryAncestor(scope:scope))
        #expect(try !reader.isRepository(scope:scope,relativePath:""))
        let run = try await coordinator.scan(scope:scope)
        let entries = try await store.page(scanID:run.id,offset:0,limit:10)
        #expect(entries.count == 1)
        #expect(entries.first?.decision.disposition == .protect)
        #expect(entries.first?.measureState == .unsupported)
        #expect(run.state == .partial)
        #expect(try await store.page(scanID:run.id,offset:0,limit:10,candidatesOnly:true).isEmpty)
    }
    #expect(try !reader.repositoryAncestor(scope:reader.scope(path:fixture.root.path)))
}
