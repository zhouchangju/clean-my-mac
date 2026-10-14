import Testing
import Foundation
import Darwin
import CleanerDomain
import CleanerCore
@testable import CleanerMacPlatform
import CleanerTestSupport
import CSQLite

@Test func v2ScopePresetsOnlyResolveAndReportNativeVolume() throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("Downloads/keep.bin")
    let provider=StorageScopeProvider(dataRoot:fixture.root,homeRoot:fixture.root)
    let home=try provider.scope(for:.home), downloads=try provider.scope(for:.downloads)
    #expect(home.rootPath==fixture.root.path)
    #expect(downloads.rootPath==fixture.root.appendingPathComponent("Downloads").path)
    #expect(throws:CleanerError.self) { try provider.scope(for:.custom) }
    let volume=try provider.volume(at:home.rootPath)
    let native=try fixture.root.resourceValues(forKeys:[.volumeIsInternalKey,.volumeTotalCapacityKey,.volumeAvailableCapacityKey])
    #expect(volume.isInternal==native.volumeIsInternal)
    #expect(volume.capacityBytes==native.volumeTotalCapacity.map(UInt64.init))
    if native.volumeIsInternal==true { #expect(try provider.scope(for:.internalDisk).rootPath==fixture.root.path) }
    #expect(try Data(contentsOf:fixture.root.appendingPathComponent("Downloads/keep.bin"))==Data("fixture".utf8))
}

@Test func v2AnalysisProtectsButMeasuresRepositoriesAndBundles() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("repo/.git/config")
    _=try fixture.sparse("repo/src/large",size:536870912)
    _=try fixture.file("Editor.app/Contents/file",contents:Data(repeating:65,count:4096))
    _=try fixture.file(".ssh/secret")
    _=try fixture.file(".codex/sessions/secret")
    _=try fixture.file(".codex/cache/codex_apps_tools/tools")
    let index=try Fixture();defer { try? index.cleanup() }
    let store=try SQLiteScanStore(url:index.root.appendingPathComponent("index.sqlite"))
    let reader=MacFileReader(),scope=try reader.scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:store,rules:RuleEngine(homePath:scope.rootPath),analysisMode:true).scan(scope:scope)
    let rows=try await store.page(scanID:run.id,offset:0,limit:100)
    for path in ["repo/src/large","Editor.app/Contents/file"] {
        let entry=try #require(rows.first { $0.relativePath==path })
        #expect(entry.decision.disposition == .protect)
        #expect(!entry.selectable)
        #expect(entry.decision.ruleIDs.isEmpty)
        #expect(entry.measureState == .measured)
        #expect(entry.identity?.parentChain.first?.relativePath=="")
    }
    #expect(!rows.contains { $0.relativePath==".ssh/secret" || $0.relativePath==".codex/sessions/secret" })
    let sub=try reader.scope(path:fixture.root.appendingPathComponent("repo/src").path)
    let subrun=try await ScanCoordinator(store:store,rules:RuleEngine(),analysisMode:true).scan(scope:sub)
    let subrows=try await store.page(scanID:subrun.id,offset:0,limit:20)
    #expect(subrows.contains { $0.relativePath=="large" && $0.decision.disposition == .protect && !$0.selectable })
    #expect(run.state == .partial)
    #expect(try await store.dashboard(scanID:run.id).previewCandidateCount==1)
    let cacheCatalog=try await store.catalog(scanID:run.id,candidatesOnly:true)
    #expect(cacheCatalog.map(\.relativePath)==[".codex/cache/codex_apps_tools/tools"])
    #expect(rows.first { $0.relativePath==".codex" }?.measureState == .partial)
}

@Test func v2DashboardAndChildrenNeverDoubleCountTreeOrHardlinks() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let original=try fixture.file("Documents/a.txt",contents:Data(repeating:65,count:4096))
    try FileManager.default.linkItem(at:original,to:fixture.root.appendingPathComponent("Documents/link.txt"))
    _=try fixture.file("Documents/empty.txt",contents:Data())
    _=try fixture.sparse("Downloads/large",size:536870912)
    _=try fixture.file(".ssh/no-read")
    let index=try Fixture();defer { try? index.cleanup() }
    let store=try SQLiteScanStore(url:index.root.appendingPathComponent("index.sqlite"))
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:store,rules:RuleEngine(homePath:scope.rootPath),analysisMode:true).scan(scope:scope)
    let children=try await store.children(scanID:run.id,parentID:nil)
    #expect(Set(children.map(\.relativePath))==["Documents","Downloads",".ssh",".lmc-fixture-marker"])
    #expect(!children.contains { $0.relativePath=="" || $0.relativePath.contains("/") })
    let docs=try #require(children.first { $0.relativePath=="Documents" })
    let leaf=try await store.children(scanID:run.id,parentID:docs.id,sort:.logical)
    #expect(leaf.count==3)
    #expect(leaf.first?.logicalBytes?.value==4096)
    #expect(leaf.last?.logicalBytes?.value==0)
    #expect(try await store.children(scanID:run.id,parentID:docs.id,search:"a.txt").count==1)
    #expect(try await store.children(scanID:run.id,parentID:nil,category:.downloads).map(\.relativePath)==["Downloads"])
    let dash=try await store.dashboard(scanID:run.id)
    let categorizedLogical=dash.categories.reduce(UInt64(0)) { $0+$1.logicalBytes }
    let expectedLogical: UInt64 = 536875044
    #expect(categorizedLogical==expectedLogical)
    let categorizedAllocated=dash.categories.reduce(UInt64(0)) { $0+$1.allocatedBytes }
    #expect(categorizedAllocated==dash.summary.knownAllocatedBytes)
    let categorizedFiles=dash.categories.reduce(UInt64(0)) { $0+$1.fileCount }
    #expect(categorizedFiles==4)
    #expect(dash.largeFileCount==1)
    #expect(dash.previewCandidateCount==0)
    #expect(dash.summary.unknownCount==1)
    #expect(Set(dash.topFolders.map(\.relativePath))==["Documents","Downloads",".ssh"])
    #expect(dash.issues.map(\.relativePath)==[".ssh"])
    #expect(try await store.children(scanID:run.id,parentID:nil,offset:1,limit:1).count==1)
}


@Test func v2MigrationBackfillsLegacyCategoriesAndDedupe() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let file=try fixture.file("Downloads/a.txt",contents:Data(repeating:65,count:4096))
    try FileManager.default.linkItem(at:file,to:fixture.root.appendingPathComponent("Downloads/link.txt"))
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let originalStore=try SQLiteScanStore(url:database)
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:originalStore,rules:RuleEngine()).scan(scope:scope)
    let before=try await originalStore.dashboard(scanID:run.id)
    let oldDatabase=index.root.appendingPathComponent("legacy-v4.sqlite")
    let oldEntries=try await originalStore.page(scanID:run.id,offset:0,limit:1000)
    try writeLegacyV4(oldDatabase,run:run,entries:oldEntries)
    var db: OpaquePointer?
    #expect(sqlite3_open(oldDatabase.path,&db)==SQLITE_OK)
    defer { sqlite3_close(db) }
    for column in ["category","counted_logical","counted_allocated","unique_leaf","modified","preview_cache"] {
        #expect(sqlite3_exec(db,"ALTER TABLE entries DROP COLUMN \(column)",nil,nil,nil)==SQLITE_OK)
    }
    #expect(sqlite3_exec(db,"PRAGMA user_version=0",nil,nil,nil)==SQLITE_OK)
    let migrated=try SQLiteScanStore(url:oldDatabase)
    let after=try await migrated.dashboard(scanID:run.id)
    #expect(after.categories.reduce(UInt64(0)) { $0+$1.logicalBytes } == before.summary.knownLogicalBytes)
    #expect(after.categories.reduce(UInt64(0)) { $0+$1.fileCount } == 2)
    #expect(after.categories.first { $0.category == .downloads }?.logicalBytes == 4096)
    #expect(try await migrated.catalog(scanID:run.id,category:.downloads).count==2)
}

@Test func v2DefaultDiskMetadataIsReadOnly() throws {
    let provider=StorageScopeProvider()
    let snapshot=try provider.volume(at:"/System/Volumes/Data")
    let native=try URL(fileURLWithPath:"/System/Volumes/Data").resourceValues(forKeys:[.volumeIsInternalKey])
    #expect(snapshot.isInternal==native.volumeIsInternal)
    if snapshot.isInternal==true {
        let scope=try provider.scope(for:.internalDisk)
        #expect(scope.rootPath=="/System/Volumes/Data")
        #expect(scope.rootIdentity.kind == .directory)
    } else {
        #expect(throws:CleanerError.self) { try provider.scope(for:.internalDisk) }
    }
}


@Test func v2CorruptLegacyMigrationRollsBackWithoutVersionPromotion() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("plain")
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let scan=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope)
    let oldDatabase=index.root.appendingPathComponent("legacy-v4.sqlite")
    try writeLegacyV4(oldDatabase,run:scan,entries:try await store.page(scanID:scan.id,offset:0,limit:1000))
    var db: OpaquePointer?;#expect(sqlite3_open(oldDatabase.path,&db)==SQLITE_OK)
    defer { sqlite3_close(db) }
    for column in ["category","counted_logical","counted_allocated","unique_leaf","modified","preview_cache"] {
        #expect(sqlite3_exec(db,"ALTER TABLE entries DROP COLUMN \(column)",nil,nil,nil)==SQLITE_OK)
    }
    #expect(sqlite3_exec(db,"PRAGMA user_version=0; UPDATE entries SET json='{' WHERE parent IS NULL",nil,nil,nil)==SQLITE_OK)
    #expect(throws:CleanerError.self) { try SQLiteScanStore(url:oldDatabase) }
    var version: OpaquePointer?
    #expect(sqlite3_prepare_v2(db,"PRAGMA user_version",-1,&version,nil)==SQLITE_OK)
    #expect(sqlite3_step(version)==SQLITE_ROW)
    #expect(sqlite3_column_int(version,0)==0)
    sqlite3_finalize(version)
    var columns: OpaquePointer?
    #expect(sqlite3_prepare_v2(db,"PRAGMA table_info(entries)",-1,&columns,nil)==SQLITE_OK)
    var names:Set<String>=[]
    while sqlite3_step(columns)==SQLITE_ROW { if let raw=sqlite3_column_text(columns,1) { names.insert(String(cString:raw)) } }
    sqlite3_finalize(columns)
    #expect(!names.contains("category"))
}

@Test func v2MapWeightsUseSharedInodeAttributionWithoutChangingStatSizes() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let a=try fixture.file("A/source",contents:Data(repeating:65,count:4096))
    try FileManager.default.linkItem(at:a,to:fixture.root.appendingPathComponent("A/alias"))
    _=try fixture.file("B/placeholder",contents:Data())
    try FileManager.default.linkItem(at:a,to:fixture.root.appendingPathComponent("B/alias"))
    let index=try Fixture();defer { try? index.cleanup() }
    let store=try SQLiteScanStore(url:index.root.appendingPathComponent("index.sqlite"))
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope)
    let roots=try await store.children(scanID:run.id,parentID:nil)
    let rootWeights=try await store.mapWeights(scanID:run.id,parentID:nil)
    let summary=try await store.summary(scanID:run.id)
    #expect(rootWeights.values.reduce(UInt64(0),+)==summary.knownAllocatedBytes)
    let visible=Set(roots.prefix(1).map(\.id))
    let visibleWeights=try await store.mapWeights(scanID:run.id,parentID:nil,ids:visible)
    #expect(Set(visibleWeights.keys)==visible)
    #expect(try await store.mapWeights(scanID:run.id,parentID:nil,ids:[]).isEmpty)
    for folder in roots where folder.identity?.kind == .directory {
        let leaves=try await store.children(scanID:run.id,parentID:folder.id)
        let weights=try await store.mapWeights(scanID:run.id,parentID:folder.id)
        #expect(weights.values.reduce(UInt64(0),+)==folder.allocatedBytes?.value)
        #expect(leaves.filter { $0.relativePath.hasSuffix("source") || $0.relativePath.hasSuffix("alias") }.allSatisfy { $0.logicalBytes?.value==4096 })
    }
    let all=try await store.catalog(scanID:run.id)
    let aliases=all.filter { $0.identity?.linkCount.value==3 }
    var nonzero:UInt64=0
    for leaf in aliases {
        let weights=try await store.mapWeights(scanID:run.id,parentID:leaf.parentID)
        if (weights[leaf.id] ?? 0)>0 { nonzero += 1 }
    }
    #expect(nonzero==1)
}


@Test func v2TerminalIndexMaintenancePreservesHistoryAndProtectedRuns() async throws {
    let populated=try Fixture();defer { try? populated.cleanup() }
    for i in 0..<1200 { _=try populated.file("many/\(i).txt",contents:Data("index-fixture".utf8)) }
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let original=try SQLiteScanStore(url:database,quotaBytes:64*1024*1024)
    let reader=MacFileReader(),scope=try reader.scope(path:populated.root.path)
    let old=try await ScanCoordinator(store:original,rules:RuleEngine()).scan(scope:scope)
    let snapshot=try await original.summary(scanID:old.id)
    #expect(old.state == .completed)
    let rootIdentity=try reader.identity(scope:scope,relativePath:"")
    let decision=RuleDecision(disposition:.descend,reasonCodes:[],reason:"fixture")
    var active=ScanRun(scope:scope,ruleSetVersion:"test");active.state = .running
    var pending=ScanRun(scope:scope,ruleSetVersion:"test");pending.state = .completed
    for run in [active,pending] {
        try await original.create(run)
        try await original.insert([Entry(scanID:run.id,parentID:nil,relativePath:"",identity:rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:decision)])
    }
    let budget:UInt64=256*1024
    var before=stat();#expect(lstat(database.path,&before)==0)
    #expect(UInt64(before.st_size)>budget)
    let bounded=try SQLiteScanStore(url:database,quotaBytes:budget)
    let failed=try await ScanCoordinator(store:bounded,rules:RuleEngine()).scan(scope:scope)
    #expect(failed.state == .partial)
    #expect(failed.stopReason?.contains("quotaExceeded")==true)
    let failedSummary=try await bounded.summary(scanID:failed.id)
    #expect(failedSummary.entryCount==0 && failedSummary.unknownCount>=1)
    #expect(try await bounded.dashboard(scanID:failed.id).issues.first?.decision.reasonCodes==["scanStopped"])
    #expect(try await bounded.catalog(scanID:failed.id,issuesOnly:true).count==1)
    #expect(try await bounded.retireTerminalScans(protectedScanIDs:[pending.id])==1)
    #expect(try await bounded.page(scanID:old.id,offset:0,limit:10).isEmpty)
    #expect(try await bounded.page(scanID:active.id,offset:0,limit:10).count==1)
    #expect(try await bounded.page(scanID:pending.id,offset:0,limit:10).count==1)
    let archived=try await bounded.summary(scanID:old.id)
    #expect(archived.entryCount==snapshot.entryCount && archived.knownLogicalBytes==snapshot.knownLogicalBytes && archived.knownAllocatedBytes==snapshot.knownAllocatedBytes)
    var after=stat();#expect(lstat(database.path,&after)==0)
    #expect(after.st_ino==before.st_ino && UInt64(after.st_size)<budget)
    #expect(try Data(contentsOf:populated.root.appendingPathComponent("many/0.txt"))==Data("index-fixture".utf8))
    let small=try Fixture();defer { try? small.cleanup() }
    _=try small.file("sentinel")
    let next=try await ScanCoordinator(store:bounded,rules:RuleEngine()).scan(scope:reader.scope(path:small.root.path))
    #expect(next.state == .completed && next.stopReason==nil)
    #expect(try await bounded.summary(scanID:next.id).entryCount==3)
    let reopened=try SQLiteScanStore(url:database,quotaBytes:budget)
    #expect(try await reopened.summary(scanID:old.id).entryCount==snapshot.entryCount)
}

@Test func v2IndexMaintenanceRejectsReplacedOrHardlinkedIndex() async throws {
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let saved=index.root.appendingPathComponent("saved.sqlite")
    try FileManager.default.moveItem(at:database,to:saved)
    try Data("replacement".utf8).write(to:database)
    await #expect(throws:CleanerError.self) { try await store.retireTerminalScans(protectedScanIDs:[]) }
    #expect(try Data(contentsOf:database)==Data("replacement".utf8))
    #expect(throws:CleanerError.self) { try SQLiteScanStore(url:database) }
    try FileManager.default.removeItem(at:database)
    try FileManager.default.moveItem(at:saved,to:database)
    try FileManager.default.linkItem(at:database,to:index.root.appendingPathComponent("alias.sqlite"))
    #expect(throws:CleanerError.self) { try SQLiteScanStore(url:database) }
    await #expect(throws:CleanerError.self) { try await store.retireTerminalScans(protectedScanIDs:[]) }
}

@Test func v2StoppedRunJSONRemainsBackwardCompatible() throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let run=ScanRun(scope:try MacFileReader().scope(path:fixture.root.path),ruleSetVersion:"test")
    var object=try #require(JSONSerialization.jsonObject(with:Codec.encoder().encode(run)) as? [String:Any])
    object.removeValue(forKey:"stopReason")
    let oldJSON=try JSONSerialization.data(withJSONObject:object)
    #expect(try Codec.decoder().decode(ScanRun.self,from:oldJSON).stopReason==nil)
}


@Test func v2FreelistOnlyMaintenanceReusesSpaceWithoutRetiringProtectedRuns() async throws {
    let target=try Fixture();defer { try? target.cleanup() }
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let scope=try MacFileReader().scope(path:target.root.path)
    var run=ScanRun(scope:scope,ruleSetVersion:"test");run.state = .running
    try await store.create(run)
    try await store.insert([Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"fixture"))])
    var db:OpaquePointer?;#expect(sqlite3_open(database.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"CREATE TABLE own_test_growth(bytes BLOB); INSERT INTO own_test_growth VALUES(zeroblob(524288)); DROP TABLE own_test_growth",nil,nil,nil)==SQLITE_OK)
    sqlite3_close(db)
    var before=stat();#expect(lstat(database.path,&before)==0)
    #expect(before.st_size>131072)
    let bounded=try SQLiteScanStore(url:database,quotaBytes:131072)
    #expect(try await bounded.retireTerminalScans(protectedScanIDs:[run.id])==0)
    #expect(try await bounded.page(scanID:run.id,offset:0,limit:10).count==1)
    var after=stat();#expect(lstat(database.path,&after)==0)
    #expect(after.st_size<131072 && after.st_ino==before.st_ino)
}

@Test(.enabled(if:getuid() != 0)) func v2ReadableBranchesContinuePastPermissionGapWithoutStopBanner() async throws {
    let fixture=try Fixture()
    let denied=fixture.root.appendingPathComponent("denied")
    defer { try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:denied.path);try? fixture.cleanup() }
    _=try fixture.file("denied/secret")
    _=try fixture.file("readable.txt",contents:Data(repeating:65,count:4096))
    try FileManager.default.setAttributes([.posixPermissions:0o000],ofItemAtPath:denied.path)
    let index=try Fixture();defer { try? index.cleanup() }
    let store=try SQLiteScanStore(url:index.root.appendingPathComponent("index.sqlite"))
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope)
    #expect(run.state == .partial && run.stopReason==nil)
    let rows=try await store.page(scanID:run.id,offset:0,limit:20)
    #expect(rows.contains { $0.relativePath=="readable.txt" && $0.logicalBytes?.value==4096 })
    #expect(rows.contains { $0.relativePath=="denied" && $0.measureState == .permissionDenied })
    #expect(!rows.contains { $0.relativePath=="denied/secret" })
    #expect(try await store.dashboard(scanID:run.id).issues.allSatisfy { !$0.decision.reasonCodes.contains("scanStopped") })
}

@Test func v2SQLiteFullStopsWithConcreteReasonAndGlobalGap() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    for i in 0..<1200 { _=try fixture.file("new/\(i)") }
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database,maxPageCount:32)
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope)
    #expect(run.state == .partial)
    #expect(run.stopReason?.contains("SQLite 13")==true)
    #expect(run.stopReason?.contains("full")==true)
    let summary=try await store.summary(scanID:run.id)
    #expect(summary.unknownCount>=1)
    #expect(try await store.dashboard(scanID:run.id).issues.contains { $0.decision.reasonCodes==["scanStopped"] })
    #expect(try Data(contentsOf:fixture.root.appendingPathComponent("new/0"))==Data("fixture".utf8))
}


@Test func v2IssuePagingOnlyCountsSyntheticRowsThatMatchFilters() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let index=try Fixture();defer { try? index.cleanup() }
    let store=try SQLiteScanStore(url:index.root.appendingPathComponent("index.sqlite"))
    _=try fixture.file("gap/marker")
    let scope=try MacFileReader().scope(path:fixture.root.path)
    var run=ScanRun(scope:scope,ruleSetVersion:"test");run.state = .partial;run.stopReason="quotaExceeded: index full"
    try await store.create(run)
    let decision=RuleDecision(disposition:.protect,reasonCodes:["permissionDenied"],reason:"fixture gap")
    let root=Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:decision)
    let directory=Entry(scanID:run.id,parentID:root.id,relativePath:"gap",identity:try MacFileReader().identity(scope:scope,relativePath:"gap"),logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:decision)
    let a=Entry(scanID:run.id,parentID:directory.id,relativePath:"gap/a.txt",identity:nil,logicalBytes:nil,allocatedBytes:nil,measureState:.permissionDenied,decision:decision)
    let b=Entry(scanID:run.id,parentID:directory.id,relativePath:"gap/b.txt",identity:nil,logicalBytes:nil,allocatedBytes:nil,measureState:.permissionDenied,decision:decision)
    try await store.insert([root,directory,a,b])
    var unfiltered:[UUID]=[]
    var searched:[UUID]=[]
    var categorized:[UUID]=[]
    for offset in 0...2 {
        unfiltered += try await store.catalog(scanID:run.id,offset:offset,limit:1,issuesOnly:true).map(\.id)
        searched += try await store.catalog(scanID:run.id,offset:offset,limit:1,search:"gap/",issuesOnly:true).map(\.id)
        categorized += try await store.catalog(scanID:run.id,offset:offset,limit:1,category:.documents,issuesOnly:true).map(\.id)
    }
    #expect(unfiltered==[run.id,a.id,b.id])
    #expect(searched==[a.id,b.id])
    #expect(categorized==[a.id,b.id])
    #expect(Set(searched).count==searched.count)
    #expect(Set(categorized).count==categorized.count)
    #expect(try await store.catalog(scanID:run.id,offset:1,limit:1,largeOnly:true,issuesOnly:true).isEmpty)
    #expect(try await store.catalog(scanID:run.id,offset:1,limit:1,candidatesOnly:true,issuesOnly:true).isEmpty)
}

@Test func v2CountersAppendBatchesRollbackAndMigrateExactly() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let doc=try fixture.file("Documents/a.txt",contents:Data(repeating:65,count:4096))
    _=try fixture.file("Downloads/placeholder",contents:Data())
    try FileManager.default.linkItem(at:doc,to:fixture.root.appendingPathComponent("Downloads/alias.txt"))
    _=try fixture.sparse("Downloads/large",size:536870912)
    _=try fixture.file("Caches/cache.bin",contents:Data("fixture".utf8))
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let reader=MacFileReader(),scope=try reader.scope(path:fixture.root.path)
    let run=ScanRun(scope:scope,ruleSetVersion:"test")
    try await store.create(run)
    func entry(_ path:String,_ parent:UUID?,decision:RuleDecision=RuleDecision(disposition:.review,reasonCodes:[],reason:"fixture")) throws -> Entry {
        let metadata=try reader.metadata(scope:scope,relativePath:path)
        return Entry(scanID:run.id,parentID:parent,relativePath:path,identity:metadata.identity,logicalBytes:metadata.identity.kind == .directory ? nil:metadata.identity.size.value,allocatedBytes:metadata.identity.kind == .directory ? nil:metadata.allocated,measureState:.measured,decision:decision)
    }
    let root=try entry("",nil),documents=try entry("Documents",root.id),downloads=try entry("Downloads",root.id),cache=try entry("Caches",root.id)
    try await store.insert([root,documents,downloads,cache])
    #expect(try await store.summary(scanID:run.id).entryCount==4)
    let a=try entry("Documents/a.txt",documents.id),alias=try entry("Downloads/alias.txt",downloads.id)
    try await store.insert([a,alias])
    let middle=try await store.dashboard(scanID:run.id)
    #expect(middle.summary.knownLogicalBytes==4096 && middle.summary.entryCount==6)
    #expect(middle.categories.reduce(UInt64(0)) { $0+$1.fileCount }==1)
    let large=try entry("Downloads/large",downloads.id)
    let cached=try entry("Caches/cache.bin",cache.id,decision:RuleDecision(ruleIDs:["RULE-DEV-01"],disposition:.candidate,reasonCodes:[],reason:"fixture preview"))
    let gap=Entry(scanID:run.id,parentID:root.id,relativePath:"gap",identity:nil,logicalBytes:nil,allocatedBytes:nil,measureState:.permissionDenied,decision:RuleDecision(disposition:.protect,reasonCodes:["permissionDenied"],reason:"fixture gap"))
    try await store.insert([large,cached,gap])
    let expectedLogical:UInt64=536875015
    let expectedAllocated=try reader.metadata(scope:scope,relativePath:"Documents/a.txt").allocated + reader.metadata(scope:scope,relativePath:"Downloads/large").allocated + reader.metadata(scope:scope,relativePath:"Caches/cache.bin").allocated
    let snapshot=try await store.dashboard(scanID:run.id)
    #expect(snapshot.summary.entryCount==9 && snapshot.summary.unknownCount==1)
    #expect(snapshot.summary.knownLogicalBytes==expectedLogical && snapshot.summary.knownAllocatedBytes==expectedAllocated)
    #expect(snapshot.categories.reduce(UInt64(0)) { $0+$1.fileCount }==3)
    #expect(snapshot.largeFileCount==1 && snapshot.previewCandidateCount==1 && snapshot.previewCandidateBytes==cached.allocatedBytes?.value)
    #expect(snapshot.categories.first { $0.category == .documents }?.logicalBytes==4096)
    #expect(snapshot.categories.first { $0.category == .downloads }?.logicalBytes==536870912)
    #expect(snapshot.categories.first { $0.category == .cache }?.logicalBytes==7)
    #expect(snapshot.topFolders.allSatisfy { $0.identity?.parentChain.isEmpty==true })
    #expect(try await store.entries(scanID:run.id,ids:[cached.id]).first?.identity?.parentChain.count==2)
    await #expect(throws:CleanerError.self) { try await store.insert([try entry("Downloads/placeholder",downloads.id),a]) }
    let rolledBack=try await store.dashboard(scanID:run.id)
    #expect(rolledBack.summary.entryCount==9 && rolledBack.summary.knownLogicalBytes==expectedLogical)
    #expect(rolledBack.categories.reduce(UInt64(0)) { $0+$1.fileCount }==3)
    let oldDatabase=index.root.appendingPathComponent("legacy-v4.sqlite")
    try writeLegacyV4(oldDatabase,run:run,entries:[root,documents,downloads,cache,a,alias,large,cached,gap])
    var db:OpaquePointer?;#expect(sqlite3_open(oldDatabase.path,&db)==SQLITE_OK)
    #expect(sqlite3_exec(db,"DROP TABLE scan_totals;DROP TABLE category_totals;DROP INDEX entry_issues;DROP INDEX entry_topfolders;PRAGMA user_version=3",nil,nil,nil)==SQLITE_OK)
    sqlite3_close(db)
    let migrated=try SQLiteScanStore(url:oldDatabase)
    let rebuilt=try await migrated.dashboard(scanID:run.id)
    #expect(rebuilt.summary.entryCount==9 && rebuilt.summary.knownLogicalBytes==expectedLogical && rebuilt.summary.unknownCount==1)
    #expect(rebuilt.largeFileCount==1 && rebuilt.previewCandidateCount==1 && rebuilt.previewCandidateBytes==snapshot.previewCandidateBytes)
    #expect(rebuilt.categories.reduce(UInt64(0)) { $0+$1.fileCount }==3)
}

@Test func v2CounterMigrationRejectsBadTypedRowsAndRollsBack() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("plain")
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let scan=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:MacFileReader().scope(path:fixture.root.path))
    let oldDatabase=index.root.appendingPathComponent("legacy-v4.sqlite")
    try writeLegacyV4(oldDatabase,run:scan,entries:try await store.page(scanID:scan.id,offset:0,limit:1000))
    var db:OpaquePointer?;#expect(sqlite3_open(oldDatabase.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db,"DROP TABLE scan_totals;DROP TABLE category_totals;PRAGMA user_version=3;UPDATE entries SET counted_allocated=-1 WHERE kind='regular'",nil,nil,nil)==SQLITE_OK)
    #expect(throws:CleanerError.self) { try SQLiteScanStore(url:oldDatabase) }
    var stmt:OpaquePointer?;#expect(sqlite3_prepare_v2(db,"PRAGMA user_version",-1,&stmt,nil)==SQLITE_OK)
    #expect(sqlite3_step(stmt)==SQLITE_ROW && sqlite3_column_int(stmt,0)==3);sqlite3_finalize(stmt)
    #expect(sqlite3_prepare_v2(db,"SELECT count(*) FROM sqlite_master WHERE name='scan_totals'",-1,&stmt,nil)==SQLITE_OK)
    #expect(sqlite3_step(stmt)==SQLITE_ROW && sqlite3_column_int(stmt,0)==0);sqlite3_finalize(stmt)
}

private actor V2DashboardBenchmarkRecorder {
    var callbackCount=0
    var queryMilliseconds:Double=0
    var maximumMilliseconds:Double=0
    func record(_ duration:Duration) { let c=duration.components;let ms=Double(c.seconds)*1000+Double(c.attoseconds)/1e15;callbackCount+=1;queryMilliseconds+=ms;maximumMilliseconds=max(maximumMilliseconds,ms) }
    func values() -> (Int,Double,Double) { (callbackCount,queryMilliseconds,maximumMilliseconds) }
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["LMC_DASHBOARD_BENCHMARK"]=="1")) func v2FiftyThousandFilesWithRealDashboardProgress() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let attrs=try FileManager.default.attributesOfFileSystem(forPath:fixture.root.path)
    try #require((attrs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0 >= 2*1024*1024*1024)
    let payload=Data(repeating:65,count:1024)
    var expectedAllocated:UInt64=0
    for folder in 0..<100 {
        for file in 0..<500 {
            let url=try fixture.file("d\(folder)/f\(file)",contents:payload)
            var st=stat();try #require(lstat(url.path,&st)==0);expectedAllocated+=UInt64(st.st_blocks)*512
        }
    }
    var marker=stat();try #require(lstat(fixture.root.appendingPathComponent(".lmc-fixture-marker").path,&marker)==0)
    expectedAllocated+=UInt64(marker.st_blocks)*512
    try #require(expectedAllocated<=512*1024*1024)
    let scope=try MacFileReader().scope(path:fixture.root.path)
    for trial in 1...3 {
        let index=try Fixture();defer { try? index.cleanup() }
        let database=index.root.appendingPathComponent("index.sqlite")
        let store=try SQLiteScanStore(url:database)
        let recorder=V2DashboardBenchmarkRecorder()
        let start=ContinuousClock.now
        let run=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope) { progress in
            let queryStart=ContinuousClock.now
            let dashboard=try? await store.dashboard(scanID:progress.id)
            let rows=try? await store.children(scanID:progress.id,parentID:nil,limit:100)
            if let dashboard {
                #expect(dashboard.categories.reduce(UInt64(0)) { $0+$1.logicalBytes }==dashboard.summary.knownLogicalBytes)
                #expect(dashboard.categories.reduce(UInt64(0)) { $0+$1.allocatedBytes }==dashboard.summary.knownAllocatedBytes)
            } else { Issue.record("真实dashboard callback查询失败") }
            #expect(rows != nil)
            await recorder.record(queryStart.duration(to:.now))
        }
        let elapsed=start.duration(to:.now)
        let final=try await store.dashboard(scanID:run.id)
        let timing=await recorder.values()
        var usage=rusage();getrusage(RUSAGE_SELF,&usage)
        var databaseStat=stat();try #require(lstat(database.path,&databaseStat)==0)
        print("LMC_DASHBOARD_BENCH trial=\(trial) wall=\(elapsed) callbacks=\(timing.0) dashboardPlusChildrenMs=\(timing.1) callbackMaxMs=\(timing.2) rssPeakBytes=\(usage.ru_maxrss) dbBytes=\(databaseStat.st_size) knownAllocated=\(final.summary.knownAllocatedBytes) condition=uncontrolled-warm-contended mainThreadBusy=UNVERIFIED")
        #expect(run.state == .completed && run.stopReason==nil)
        #expect(final.summary.entryCount==50102 && final.summary.knownLogicalBytes==51200036 && final.summary.knownAllocatedBytes==expectedAllocated)
        #expect(timing.0>=2)
        #expect(databaseStat.st_size<250*1024*1024)
        #expect(usage.ru_maxrss<=500*1024*1024)
        if trial==3 {
            var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
            for (name,query) in [
                ("issues","EXPLAIN QUERY PLAN SELECT json FROM entries WHERE scan=? AND unknown=1 ORDER BY path LIMIT 25"),
                ("folders","EXPLAIN QUERY PLAN SELECT json FROM entries WHERE scan=? AND kind='directory' AND parent=(SELECT id FROM entries WHERE scan=? AND parent IS NULL) ORDER BY aggregate_allocated DESC,path LIMIT 20"),
                ("category","EXPLAIN QUERY PLAN SELECT category,allocated,logical,file_count FROM category_totals WHERE scan=?"),
                ("counts","EXPLAIN QUERY PLAN SELECT large_count,preview_count,preview_bytes FROM scan_totals WHERE scan=?")
            ] {
                var stmt:OpaquePointer?;try #require(sqlite3_prepare_v2(db,query,-1,&stmt,nil)==SQLITE_OK)
                for n in 1...sqlite3_bind_parameter_count(stmt) { sqlite3_bind_text(stmt,n,run.id.uuidString,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
                var lines:[String]=[];var status=sqlite3_step(stmt)
                while status==SQLITE_ROW { if let raw=sqlite3_column_text(stmt,3) { lines.append(String(cString:raw)) };status=sqlite3_step(stmt) }
                sqlite3_finalize(stmt);#expect(status==SQLITE_DONE)
                print("LMC_DASHBOARD_QUERY_PLAN \(name): \(lines.joined(separator:" | "))")
                #expect(!lines.contains { $0.contains("TEMP B-TREE") })
            }
            var sizes:OpaquePointer?
            if sqlite3_prepare_v2(db,"SELECT name,sum(pgsize) FROM dbstat WHERE name IN ('entry_issues','entry_topfolders','scan_totals','category_totals','sqlite_autoindex_scan_totals_1','sqlite_autoindex_category_totals_1') GROUP BY name",-1,&sizes,nil)==SQLITE_OK {
                while sqlite3_step(sizes)==SQLITE_ROW { if let raw=sqlite3_column_text(sizes,0) { print("LMC_DASHBOARD_INDEX_BYTES \(String(cString:raw))=\(sqlite3_column_int64(sizes,1))") } }
                sqlite3_finalize(sizes)
            } else { print("LMC_DASHBOARD_INDEX_BYTES UNVERIFIED dbstat unavailable") }
        }
    }
}


@Test func v2FutureIndexVersionIsRejectedWithoutAnyMutation() throws {
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    _=try SQLiteScanStore(url:database)
    var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    try #require(sqlite3_exec(db,"PRAGMA journal_mode=WAL;CREATE TABLE future_business_marker(key TEXT PRIMARY KEY,value TEXT NOT NULL);INSERT INTO future_business_marker VALUES('sentinel','must-remain');PRAGMA user_version=6",nil,nil,nil)==SQLITE_OK)
    func textRows(_ query:String) throws -> [String] {
        var stmt:OpaquePointer?;try #require(sqlite3_prepare_v2(db,query,-1,&stmt,nil)==SQLITE_OK);defer { sqlite3_finalize(stmt) }
        var results:[String]=[];var status=sqlite3_step(stmt)
        while status==SQLITE_ROW {
            let row=(0..<sqlite3_column_count(stmt)).map { i in sqlite3_column_text(stmt,i).map { String(cString:$0) } ?? "<NULL>" }.joined(separator:"|")
            results.append(row);status=sqlite3_step(stmt)
        }
        try #require(status==SQLITE_DONE);return results
    }
    let schema=try textRows("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name")
    let sentinel=try textRows("SELECT key,value FROM future_business_marker")
    #expect(try textRows("PRAGMA journal_mode")==["wal"])
    try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:index.root.path)
    try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:database.path)
    do { _=try SQLiteScanStore(url:database);Issue.record("未来schema不能打开或降级") }
    catch let error as CleanerError { #expect(error.code == .invalidInput && error.message.contains("升级")) }
    #expect(try textRows("PRAGMA user_version")==["6"])
    #expect(try textRows("PRAGMA journal_mode")==["wal"])
    #expect(try textRows("SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name")==schema)
    #expect(try textRows("SELECT key,value FROM future_business_marker")==sentinel)
    var parent=stat(),file=stat();#expect(lstat(index.root.path,&parent)==0 && lstat(database.path,&file)==0)
    #expect(parent.st_mode & 0o777==0o755 && file.st_mode & 0o777==0o644)
}

/// Independent genuine v4 fixture, rather than relabeling compact v5 tables as an old database.
private func writeLegacyV4(_ database:URL,run:ScanRun,entries:[Entry]) throws {
    var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    let schema="""
    CREATE TABLE scans(id TEXT PRIMARY KEY,json TEXT NOT NULL,summary TEXT);
    CREATE TABLE entries(id TEXT PRIMARY KEY,scan TEXT NOT NULL,parent TEXT,path TEXT NOT NULL,json TEXT NOT NULL,kind TEXT,logical INTEGER,allocated INTEGER,unknown INTEGER NOT NULL,candidate INTEGER NOT NULL,aggregate_logical INTEGER NOT NULL DEFAULT 0,aggregate_allocated INTEGER NOT NULL DEFAULT 0,aggregate_unknown INTEGER NOT NULL DEFAULT 0,category TEXT NOT NULL DEFAULT 'other',counted_logical INTEGER NOT NULL DEFAULT 0,counted_allocated INTEGER NOT NULL DEFAULT 0,unique_leaf INTEGER NOT NULL DEFAULT 0,modified INTEGER NOT NULL DEFAULT 0,preview_cache INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX entry_parent ON entries(scan,parent);CREATE INDEX entry_allocated ON entries(scan,allocated);
    CREATE TABLE measured(scan TEXT,device TEXT,inode TEXT,PRIMARY KEY(scan,device,inode));
    PRAGMA user_version=4;
    """
    try #require(sqlite3_exec(db,schema,nil,nil,nil)==SQLITE_OK)
    let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
    func exec(_ query:String,_ values:[String?])throws {
        var stmt:OpaquePointer?;try #require(sqlite3_prepare_v2(db,query,-1,&stmt,nil)==SQLITE_OK);defer { sqlite3_finalize(stmt) }
        for (i,v) in values.enumerated() { if let v { sqlite3_bind_text(stmt,Int32(i+1),v,-1,transient) } else { sqlite3_bind_null(stmt,Int32(i+1)) } }
        try #require(sqlite3_step(stmt)==SQLITE_DONE)
    }
    try exec("INSERT INTO scans(id,json) VALUES(?,?)",[run.id.uuidString,String(decoding:try Codec.encoder().encode(run),as:UTF8.self)])
    var seen:Set<String>=[]
    for e in entries.sorted(by:{ ($0.relativePath.split(separator:"/").count,$0.relativePath) < ($1.relativePath.split(separator:"/").count,$1.relativePath) }) {
        let fi=e.identity.map { i in FileIdentity(volumeID:i.volumeID,device:i.device.value,inode:i.inode.value,kind:i.kind,size:i.size.value,mtimeNs:i.mtimeNs,ctimeNs:i.ctimeNs,linkCount:i.linkCount.value,ownerUID:i.ownerUID.value,parentChain:[]) }
        let raw=Entry(id:e.id,scanID:e.scanID,parentID:e.parentID,relativePath:e.relativePath,identity:fi,logicalBytes:fi?.kind == .directory ? nil:e.logicalBytes?.value,allocatedBytes:fi?.kind == .directory ? nil:e.allocatedBytes?.value,measureState:e.measureState,decision:e.decision)
        let key=fi.map { "\($0.device.value):\($0.inode.value)" }
        let unique=fi?.kind != .directory && key != nil && seen.insert(key!).inserted
        if let fi,unique { try exec("INSERT INTO measured VALUES(?,?,?)",[run.id.uuidString,String(fi.device.value),String(fi.inode.value)]) }
        let logical=unique ? raw.logicalBytes?.value ?? 0:0,allocated=unique ? raw.allocatedBytes?.value ?? 0:0
        let category=StorageClassifier.category(relativePath:e.relativePath,identity:fi,decision:e.decision)
        let preview=e.decision.disposition == .candidate && e.decision.ruleIDs.contains { $0.hasPrefix("RULE-DEV-") || $0.hasPrefix("RULE-AI-") }
        try exec("INSERT INTO entries(id,scan,parent,path,json,kind,logical,allocated,unknown,candidate,category,counted_logical,counted_allocated,unique_leaf,modified,preview_cache) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",[e.id.uuidString,run.id.uuidString,e.parentID?.uuidString,e.relativePath,String(decoding:try Codec.encoder().encode(raw),as:UTF8.self),fi?.kind.rawValue,raw.logicalBytes.map { String($0.value) },raw.allocatedBytes.map { String($0.value) },e.measureState == .measured ? "0":"1",preview ? "1":"0",category.rawValue,String(logical),String(allocated),unique ? "1":"0",fi?.mtimeNs ?? "0",preview ? "1":"0"])
        if let parent=e.parentID {
            try exec("WITH RECURSIVE a(id,parent) AS (SELECT id,parent FROM entries WHERE id=? UNION ALL SELECT e.id,e.parent FROM entries e JOIN a ON e.id=a.parent) UPDATE entries SET aggregate_logical=aggregate_logical+?,aggregate_allocated=aggregate_allocated+?,aggregate_unknown=aggregate_unknown+? WHERE id IN (SELECT id FROM a)",[parent.uuidString,String(logical),String(allocated),e.measureState == .measured ? "0":"1"])
        }
    }
    try #require(sqlite3_exec(db,"""
    CREATE TABLE scan_totals(scan TEXT PRIMARY KEY,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,unknown INTEGER NOT NULL,entry_count INTEGER NOT NULL,large_count INTEGER NOT NULL,preview_count INTEGER NOT NULL,preview_bytes INTEGER NOT NULL);
    CREATE TABLE category_totals(scan TEXT NOT NULL,category TEXT NOT NULL,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,file_count INTEGER NOT NULL,PRIMARY KEY(scan,category));
    INSERT INTO scan_totals SELECT scan,sum(counted_logical),sum(counted_allocated),sum(unknown),count(*),sum(CASE WHEN kind='regular' AND logical>=536870912 THEN 1 ELSE 0 END),sum(preview_cache),sum(CASE WHEN preview_cache=1 THEN counted_allocated ELSE 0 END) FROM entries GROUP BY scan;
    INSERT INTO category_totals SELECT scan,category,sum(counted_logical),sum(counted_allocated),sum(unique_leaf) FROM entries GROUP BY scan,category;
    CREATE INDEX entry_issues ON entries(scan,unknown,path) WHERE unknown=1;
    CREATE INDEX entry_topfolders ON entries(scan,parent,kind,aggregate_allocated DESC,path) WHERE kind='directory';
    """,nil,nil,nil)==SQLITE_OK)

}


@Test func compact5MetadataVectorIsExactAndCorruptionFailsClosed() throws {
    let expected=FileIdentity(volumeID:"卷-✓",device:UInt64.max,inode:UInt64.max-1,kind:.symlink,size:UInt64.max-2,mtimeNs:String(Int64.min),ctimeNs:"1844674407370955161500",linkCount:UInt64.max-3,ownerUID:UInt64.max-4,parentChain:[])
    let encoded=try CompactMetadataCodec.encode(identity:expected,state:.unsupported,volume:7)
    let result=try CompactMetadataCodec.decode(encoded) { id in #expect(id==7);return "卷-✓" }
    #expect(result.0==expected && result.1 == .unsupported)
    var corrupt=encoded;corrupt[corrupt.count-1]^=1
    #expect(throws:(any Error).self) { try CompactMetadataCodec.decode(corrupt) { _ in "卷-✓" } }
    let malformed=Data([0xC5,1,0,0,0,0,0])
    #expect(throws:(any Error).self) { try CompactMetadataCodec.decode(malformed) { _ in "卷-✓" } }
    let nilRecord=try CompactMetadataCodec.encode(identity:nil,state:.permissionDenied,volume:0)
    #expect(try CompactMetadataCodec.decode(nilRecord) { _ in "must-not-resolve" }.0==nil)
}

@Test func compact5RollbackCannotLeaveDictionaryOrParentCacheReferences() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("a")
    let index=try Fixture();defer { try? index.cleanup() }
    let store=try SQLiteScanStore(url:index.root.appendingPathComponent("index.sqlite"))
    let reader=MacFileReader(),scope=try reader.scope(path:fixture.root.path)
    let run=ScanRun(scope:scope,ruleSetVersion:"test");try await store.create(run)
    let root=Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"original"))
    try await store.insert([root])
    let native=try reader.identity(scope:scope,relativePath:"a")
    let custom=FileIdentity(volumeID:"new-volume-only-in-failed-batch",device:native.device.value,inode:native.inode.value,kind:native.kind,size:native.size.value,mtimeNs:native.mtimeNs,ctimeNs:native.ctimeNs,linkCount:native.linkCount.value,ownerUID:native.ownerUID.value,parentChain:native.parentChain)
    let decision=RuleDecision(disposition:.review,reasonCodes:["new-batch"],reason:"new decision only in failed batch")
    let row=Entry(scanID:run.id,parentID:root.id,relativePath:"a",identity:custom,logicalBytes:7,allocatedBytes:4096,measureState:.measured,decision:decision)
    await #expect(throws:CleanerError.self) { try await store.insert([row,root]) }
    #expect(try await store.summary(scanID:run.id).entryCount==1)
    try await store.insert([row])
    let decoded=try #require(try await store.entries(scanID:run.id,ids:[row.id]).first)
    #expect(decoded.identity==custom && decoded.decision==decision)
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["LMC_COMPACT_CAPACITY"]=="1")) func compact5MillionMetadataCapacityAndQueryExperiment() async throws {
    let marker=try Fixture();defer { try? marker.cleanup() }
    let scope=try MacFileReader().scope(path:marker.root.path)
    let count=Int(ProcessInfo.processInfo.environment["LMC_COMPACT_COUNT"] ?? "1000000") ?? 1_000_000
    let shape:SyntheticStorageCorpus.Shape=ProcessInfo.processInfo.environment["LMC_COMPACT_SHAPE"]=="random" ? .longRandom:.typical
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    // A measurement-only explicit cap, never the app default; report actual footprint against the unchanged250MiB design budget.
    let store=try SQLiteScanStore(url:database,quotaBytes:2*1024*1024*1024)
    let run=ScanRun(scope:scope,ruleSetVersion:"metadata-capacity-only");try await store.create(run)
    var batch:[Entry]=[],samples:[Entry]=[];var parents:[UUID]=[]
    var expectedLogical:UInt64=0,expectedAllocated:UInt64=0,expectedCount:UInt64=0,pathChars:UInt64=0,directoryCount:UInt64=0
    let start=ContinuousClock.now
    for e in SyntheticStorageCorpus(scope:scope,scanID:run.id,count:count,shape:shape) {
        expectedCount+=1;expectedLogical+=e.logicalBytes?.value ?? 0;expectedAllocated+=e.allocatedBytes?.value ?? 0;pathChars+=UInt64(e.relativePath.count);if e.identity?.kind == .directory { directoryCount+=1 }
        if expectedCount % 100003==0 || expectedCount<=10 { samples.append(e) }
        if e.identity?.kind == .directory,parents.count<10 { parents.append(e.id) }
        batch.append(e)
        if batch.count==200 { try await store.insert(batch);batch.removeAll(keepingCapacity:true) }
    }
    if !batch.isEmpty { try await store.insert(batch) }
    let write=start.duration(to:.now)
    var st=stat();try #require(lstat(database.path,&st)==0)
    var usage=rusage();getrusage(RUSAGE_SELF,&usage)
    let summary=try await store.summary(scanID:run.id)
    #expect(summary.entryCount==expectedCount && summary.knownLogicalBytes==expectedLogical && summary.knownAllocatedBytes==expectedAllocated)
    for expected in samples {
        let actual=try #require(try await store.entries(scanID:run.id,ids:[expected.id]).first)
        #expect(actual.id==expected.id && actual.scanID==expected.scanID && actual.parentID==expected.parentID && actual.relativePath.utf8.elementsEqual(expected.relativePath.utf8))
        #expect(actual.identity==expected.identity && actual.decision==expected.decision)
        if actual.identity?.kind != .directory { #expect(actual.logicalBytes==expected.logicalBytes && actual.allocatedBytes==expected.allocatedBytes) }
    }
    let dashboardStart=ContinuousClock.now;_=try await store.dashboard(scanID:run.id);let dashboard=dashboardStart.duration(to:.now)
    let parent=try #require(parents.last)
    let childStart=ContinuousClock.now;let children=try await store.children(scanID:run.id,parentID:parent,limit:100);let child=childStart.duration(to:.now)
    #expect(!children.isEmpty)
    var dictionary:OpaquePointer?;try #require(sqlite3_open(database.path,&dictionary)==SQLITE_OK)
    var decisionCountStmt:OpaquePointer?;try #require(sqlite3_prepare_v2(dictionary,"SELECT count(*) FROM decisions",-1,&decisionCountStmt,nil)==SQLITE_OK)
    try #require(sqlite3_step(decisionCountStmt)==SQLITE_ROW);let decisionCount=sqlite3_column_int64(decisionCountStmt,0);sqlite3_finalize(decisionCountStmt);sqlite3_close(dictionary)
    print("LMC_COMPACT_CAPACITY schema=5 shape=\(shape.rawValue) count=\(count) dbBytes=\(st.st_size) bytesPerEntry=\(Double(st.st_size)/Double(count)) write=\(write) rssPeakBytes=\(usage.ru_maxrss) dashboard=\(dashboard) children=\(child) experiment=metadata-only-not-filesystem-scan defaultBudgetBytes=262144000 pathMean=\(Double(pathChars)/Double(count)) directoryCount=\(directoryCount) decisionCount=\(decisionCount)")
    for sort in [StorageSort.allocated,.logical,.modified] {
        let queryStart=ContinuousClock.now;let rows=try await store.catalog(scanID:run.id,limit:100,sort:sort);let duration=queryStart.duration(to:.now)
        #expect(rows.count==100)
        #expect(Set(rows.map(\.id)).count==100)
        print("LMC_COMPACT_QUERY sort=\(sort.rawValue) wall=\(duration)")
    }
    let searchSample=try #require(samples.first { $0.identity?.kind == .regular })
    let basename=String(try #require(searchSample.relativePath.split(separator:"/").last))
    let fullParent=searchSample.relativePath.components(separatedBy:"/").dropLast().joined(separator:"/")+"/"
    for search in [basename,fullParent] {
        let queryStart=ContinuousClock.now;let rows=try await store.catalog(scanID:run.id,limit:100,search:search);let duration=queryStart.duration(to:.now)
        #expect(!rows.isEmpty && rows.allSatisfy { $0.relativePath.contains(search) })
        print("LMC_COMPACT_QUERY searchKind=\(search.contains("/") ? "full-path":"basename") wall=\(duration) rows=\(rows.count)")
    }
    var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    var sizes:OpaquePointer?
    if sqlite3_prepare_v2(db,"SELECT name,sum(pgsize),sum(payload),sum(unused) FROM dbstat GROUP BY name",-1,&sizes,nil)==SQLITE_OK {
        while sqlite3_step(sizes)==SQLITE_ROW { if let raw=sqlite3_column_text(sizes,0) { print("LMC_COMPACT_DBSIZE \(String(cString:raw)) physical=\(sqlite3_column_int64(sizes,1)) payload=\(sqlite3_column_int64(sizes,2)) unused=\(sqlite3_column_int64(sizes,3))") } };sqlite3_finalize(sizes)
    }
}


@Test func compact5MigrationPreservesFixedPlanHashAndFixturePreflightIdentity() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.sparse("nested/large",size:536870912)
    let reader=MacFileReader(),scope=try reader.scope(path:fixture.root.path)
    var run=ScanRun(scope:scope,ruleSetVersion:"test");run.state = .completed
    let root=Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"root"))
    let directory=Entry(scanID:run.id,parentID:root.id,relativePath:"nested",identity:try reader.identity(scope:scope,relativePath:"nested"),logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"directory"))
    let metadata=try reader.metadata(scope:scope,relativePath:"nested/large")
    let original=Entry(scanID:run.id,parentID:directory.id,relativePath:"nested/large",identity:metadata.identity,logicalBytes:metadata.identity.size.value,allocatedBytes:metadata.allocated,measureState:.measured,decision:RuleDecision(ruleIDs:["RULE-USER-01"],disposition:.review,capability:.trashEligible,reasonCodes:["manualReview"],reason:"用户选择"))
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("legacy-plan.sqlite")
    try writeLegacyV4(database,run:run,entries:[root,directory,original])
    let migrated=try SQLiteScanStore(url:database)
    let decoded=try #require(try await migrated.entries(scanID:run.id,ids:[original.id]).first)
    #expect(decoded.identity==original.identity)
    let planID=UUID(uuidString:"11111111-2222-3333-4444-555555555555")!
    let date=Date(timeIntervalSince1970:1_700_000_000)
    func plan(_ entry:Entry)throws->CleanupPlan { var result=CleanupPlan(id:planID,scanID:run.id,scopeID:scope.id,ruleSetVersion:"test",ignoreRevision:0,selectionRevision:1,action:.trash,items:[try PlanItem(entry:entry,rootID:scope.id,action:.trash)],createdAt:date);result.hash=try Planner.hash(result);return result }
    let before=try plan(original),after=try plan(decoded)
    #expect(before.hash==after.hash)
    #expect(try Planner.canonicalPayload(before)==Planner.canonicalPayload(after))
    try FileManager.default.moveItem(at:fixture.root.appendingPathComponent("nested/large"),to:fixture.root.appendingPathComponent("nested/held"))
    _=try fixture.file("nested/large",contents:Data("replacement must survive".utf8))
    let current=try reader.identity(scope:scope,relativePath:"nested/large")
    #expect(!current.sameObject(as:try #require(decoded.identity)))
    let rejected=try MacPreflight().validate(plan:after,run:run,selectionRevision:1,ignoreRevision:0,now:date)
    #expect(rejected.count==1 && rejected.first?.accepted==false && rejected.first?.code == .identityChanged)
    #expect(try Data(contentsOf:fixture.root.appendingPathComponent("nested/large"))==Data("replacement must survive".utf8))
}

@Test func compact5CorruptParentCycleSearchTerminatesAndRejectsEntry() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("cycleA/cycleB/leaf")
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope)
    var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    try #require(sqlite3_exec(db,"UPDATE entry_nodes SET parent=(SELECT rid FROM entry_nodes WHERE path='cycleB') WHERE path='cycleA'",nil,nil,nil)==SQLITE_OK)
    let start=ContinuousClock.now
    await #expect(throws:CleanerError.self) { try await store.catalog(scanID:run.id,search:"cycleA") }
    #expect(start.duration(to:.now) < .seconds(2))
}


@Test func compact5WarmCacheExternalParentCycleRejectsWholeInsertBatch() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("warmA/warmB/original")
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let reader=MacFileReader(),scope=try reader.scope(path:fixture.root.path)
    let run=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope)
    let rows=try await store.page(scanID:run.id,offset:0,limit:30)
    let parent=try #require(rows.first { $0.relativePath=="warmA/warmB" })
    let before=try await store.summary(scanID:run.id)
    var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    try #require(sqlite3_exec(db,"UPDATE entry_nodes SET parent=(SELECT rid FROM entry_nodes WHERE path='warmB') WHERE path='warmA'",nil,nil,nil)==SQLITE_OK)
    let identity=try reader.identity(scope:scope,relativePath:"warmA/warmB/original")
    let new=Entry(scanID:run.id,parentID:parent.id,relativePath:"warmA/warmB/new",identity:identity,logicalBytes:7,allocatedBytes:4096,measureState:.measured,decision:RuleDecision(disposition:.review,reasonCodes:[],reason:"fixture"))
    let start=ContinuousClock.now
    await #expect(throws:CleanerError.self) { try await store.insert([new]) }
    #expect(start.duration(to:.now) < .seconds(2))
    let after=try await store.summary(scanID:run.id)
    #expect(after.entryCount==before.entryCount && after.knownLogicalBytes==before.knownLogicalBytes)
    var count:OpaquePointer?;try #require(sqlite3_prepare_v2(db,"SELECT count(*) FROM entry_nodes WHERE path='new'",-1,&count,nil)==SQLITE_OK)
    #expect(sqlite3_step(count)==SQLITE_ROW && sqlite3_column_int(count,0)==0);sqlite3_finalize(count)
}


@Test func latestRetainedTerminalSnapshotExcludesActiveAndArchivedScopes() async throws {
    let one=try Fixture();defer { try? one.cleanup() }
    let two=try Fixture();defer { try? two.cleanup() }
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    #expect(try await store.latestRetainedTerminalRun()==nil)
    let reader=MacFileReader(),scope1=try reader.scope(path:one.root.path),scope2=try reader.scope(path:two.root.path)
    func retained(_ id:String,_ scope:ScanScope,_ state:ScanState,_ finish:TimeInterval?) async throws -> ScanRun {
        var run=ScanRun(id:UUID(uuidString:id)!,scope:scope,ruleSetVersion:"test");run.state=state;run.finishedAt=finish.map(Date.init(timeIntervalSince1970:))
        try await store.create(run)
        try await store.insert([Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"fixture"))])
        return run
    }
    let completed=try await retained("00000000-0000-0000-0000-000000000001",scope1,.completed,2_000_000_001)
    let partial=try await retained("00000000-0000-0000-0000-000000000002",scope2,.partial,2_000_000_002)
    let failed=try await retained("00000000-0000-0000-0000-000000000003",scope1,.failed,2_000_000_003)
    let cancelled=try await retained("00000000-0000-0000-0000-000000000004",scope2,.cancelled,2_000_000_003)
    let active=try await retained("00000000-0000-0000-0000-000000000005",scope1,.running,2_000_000_100)
    let preparing=try await retained("00000000-0000-0000-0000-000000000006",scope2,.preparing,2_000_000_101)
    #expect(try await store.latestRetainedTerminalRun()?.id==cancelled.id)
    #expect(try await store.retireTerminalScans(protectedScanIDs:[completed.id,partial.id,failed.id,active.id,preparing.id])==1)
    #expect(try await store.latestRetainedTerminalRun()?.id==failed.id)
    #expect(try await store.run(id:cancelled.id)?.state == .cancelled)
    #expect(try await store.retireTerminalScans(protectedScanIDs:[active.id,preparing.id])==3)
    #expect(try await store.latestRetainedTerminalRun()==nil)
    #expect(try await store.page(scanID:active.id,offset:0,limit:10).count==1)
    #expect(try await store.page(scanID:preparing.id,offset:0,limit:10).count==1)
}

@Test func latestRetainedTerminalSnapshotRejectsCorruptCandidateInsteadOfFallback() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let scope=try MacFileReader().scope(path:fixture.root.path)
    var valid=ScanRun(scope:scope,ruleSetVersion:"test");valid.state = .completed;valid.finishedAt=Date(timeIntervalSince1970:2_000_000_001)
    var corrupt=ScanRun(scope:scope,ruleSetVersion:"test");corrupt.state = .partial;corrupt.finishedAt=Date(timeIntervalSince1970:2_000_000_002)
    for run in [valid,corrupt] {
        try await store.create(run)
        try await store.insert([Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"fixture"))])
    }
    #expect(try await store.latestRetainedTerminalRun()?.id==corrupt.id)
    var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    var stmt:OpaquePointer?;try #require(sqlite3_prepare_v2(db,"UPDATE scans SET json='{' WHERE id=?",-1,&stmt,nil)==SQLITE_OK)
    sqlite3_bind_text(stmt,1,corrupt.id.uuidString,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))
    try #require(sqlite3_step(stmt)==SQLITE_DONE);sqlite3_finalize(stmt)
    await #expect(throws:CleanerError.self) { try await store.latestRetainedTerminalRun() }
    #expect(try await store.run(id:valid.id)?.state == .completed)
}


@Test func sharedIndexResourceBudgetAndReserveArithmeticAreExplicit() throws {
    #expect(IndexResourcePolicy.defaultMaxBytes==1_073_741_824)
    #expect(IndexResourcePolicy.defaultMinimumAvailableBytes==1_073_741_824)
    #expect(try IndexResourcePolicy.availableBytes(blocks:262144,blockSize:4096)==1_073_741_824)
    #expect(throws:CleanerError.self) { try IndexResourcePolicy.availableBytes(blocks:UInt64.max,blockSize:2) }
    #expect(throws:CleanerError.self) { try IndexResourcePolicy.availableBytes(blocks:1,blockSize:0) }
}

@Test func unavailableIndexReserveRejectsBatchWithoutChangingRowsCountersOrTargets() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    _=try fixture.file("sentinel",contents:Data("must remain".utf8))
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database,minimumAvailableBytes:UInt64.max)
    let scope=try MacFileReader().scope(path:fixture.root.path)
    let run=ScanRun(scope:scope,ruleSetVersion:"reserve-fixture")
    try await store.create(run)
    let root=Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"fixture"))
    let before=try await store.summary(scanID:run.id)
    await #expect(throws:CleanerError.self) { try await store.insert([root]) }
    let after=try await store.summary(scanID:run.id)
    #expect(before.entryCount==0 && after.entryCount==0 && after.knownLogicalBytes==before.knownLogicalBytes && after.knownAllocatedBytes==before.knownAllocatedBytes)
    #expect(try await store.page(scanID:run.id,offset:0,limit:10).isEmpty)
    #expect(try Data(contentsOf:fixture.root.appendingPathComponent("sentinel"))==Data("must remain".utf8))
    let stopped=try await ScanCoordinator(store:store,rules:RuleEngine()).scan(scope:scope)
    #expect(stopped.state == .partial && stopped.stopReason?.contains("余量")==true)
    #expect(try await store.summary(scanID:stopped.id).unknownCount>=1)
    #expect(try await store.dashboard(scanID:stopped.id).issues.contains { $0.decision.reasonCodes.contains("scanStopped") })
    let explicitFixtureOverride=try SQLiteScanStore(url:database,quotaBytes:131072,minimumAvailableBytes:0)
    try await explicitFixtureOverride.insert([root])
    #expect(try await explicitFixtureOverride.summary(scanID:run.id).entryCount==1)
}


#if DEBUG
@Test func commitReserveFailureRollsBackEveryIndexEffectAndAllowsExactRetry() async throws {
    let fixture=try Fixture();defer { try? fixture.cleanup() }
    let file=try fixture.file("new-file",contents:Data("sentinel intact".utf8))
    let index=try Fixture();defer { try? index.cleanup() }
    let database=index.root.appendingPathComponent("index.sqlite")
    let store=try SQLiteScanStore(url:database)
    let reader=MacFileReader(),scope=try reader.scope(path:fixture.root.path)
    let run=ScanRun(scope:scope,ruleSetVersion:"commit-reserve")
    try await store.create(run)
    let root=Entry(scanID:run.id,parentID:nil,relativePath:"",identity:scope.rootIdentity,logicalBytes:nil,allocatedBytes:nil,measureState:.measured,decision:RuleDecision(disposition:.descend,reasonCodes:[],reason:"original root"))
    try await store.insert([root])
    let metadata=try reader.metadata(scope:scope,relativePath:"new-file")
    let fi=metadata.identity
    let uniqueVolume="new volume only in rollback fixture"
    let identity=FileIdentity(volumeID:uniqueVolume,device:fi.device.value,inode:fi.inode.value,kind:fi.kind,size:fi.size.value,mtimeNs:fi.mtimeNs,ctimeNs:fi.ctimeNs,linkCount:fi.linkCount.value,ownerUID:fi.ownerUID.value,parentChain:fi.parentChain)
    let decision=RuleDecision(ruleIDs:["RULE-DEV-01"],disposition:.candidate,reasonCodes:["newReserveDecision"],reason:"new decision only in rollback fixture")
    let entry=Entry(scanID:run.id,parentID:root.id,relativePath:"new-file",identity:identity,logicalBytes:fi.size.value,allocatedBytes:metadata.allocated,measureState:.measured,decision:decision)
    let before=try await store.dashboard(scanID:run.id)
    // The first check is native available unchanged; the second is capped at zero after writes and counters.
    await store.setReserveCeilingsForTesting([UInt64.max,0])
    await #expect(throws:CleanerError.self) { try await store.insert([entry]) }
    let after=try await store.dashboard(scanID:run.id)
    #expect(after.summary.entryCount==before.summary.entryCount && after.summary.knownLogicalBytes==before.summary.knownLogicalBytes && after.summary.knownAllocatedBytes==before.summary.knownAllocatedBytes)
    #expect(after.previewCandidateCount==0 && after.previewCandidateBytes==0)
    #expect(after.categories.reduce(UInt64(0)) { $0+$1.fileCount }==0)
    let rootAfter=try #require(try await store.entries(scanID:run.id,ids:[root.id]).first)
    #expect(rootAfter.logicalBytes?.value==0 && rootAfter.allocatedBytes?.value==0)
    var db:OpaquePointer?;try #require(sqlite3_open(database.path,&db)==SQLITE_OK);defer { sqlite3_close(db) }
    func scalar(_ sql:String)throws->Int64 {
        var stmt:OpaquePointer?;try #require(sqlite3_prepare_v2(db,sql,-1,&stmt,nil)==SQLITE_OK);defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_step(stmt)==SQLITE_ROW);let value=sqlite3_column_int64(stmt,0);try #require(sqlite3_step(stmt)==SQLITE_DONE);return value
    }
    #expect(try scalar("SELECT count(*) FROM entry_nodes")==1)
    #expect(try scalar("SELECT count(*) FROM inode_seen")==0)
    #expect(try scalar("SELECT count(*) FROM decisions")==1)
    #expect(try scalar("SELECT count(*) FROM volumes")==1)
    #expect(try scalar("SELECT sum(file_count) FROM category_totals")==0)
    #expect(try Data(contentsOf:file)==Data("sentinel intact".utf8))
    await store.setReserveCeilingsForTesting([])
    try await store.insert([entry])
    let exact=try #require(try await store.entries(scanID:run.id,ids:[entry.id]).first)
    #expect(exact.identity==identity && exact.decision==decision)
    let retried=try await store.dashboard(scanID:run.id)
    #expect(retried.summary.entryCount==2 && retried.summary.knownLogicalBytes==fi.size.value && retried.summary.knownAllocatedBytes==metadata.allocated)
    #expect(retried.previewCandidateCount==1 && retried.previewCandidateBytes==metadata.allocated)
    #expect(try scalar("SELECT count(*) FROM inode_seen")==1)
    #expect(try Data(contentsOf:file)==Data("sentinel intact".utf8))
}
#endif
