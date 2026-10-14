import Foundation
import Darwin
import CSQLite
import CleanerDomain
import CleanerCore

public actor SQLiteScanStore: ScanStore {
    private let handle: SQLiteHandle
    private let compact: CompactIndexAdapter
    private var db: OpaquePointer { handle.pointer }
    private let url: URL
    private let quotaBytes: UInt64
    private let minimumAvailableBytes: UInt64
    #if DEBUG
    private var reserveCeilingsForTesting:[UInt64]=[]
    /// Internal fault injection only: native statfs must succeed; ceilings can never increase available space.
    func setReserveCeilingsForTesting(_ ceilings:[UInt64]) { reserveCeilingsForTesting=ceilings }
    #endif
    private let indexDevice: dev_t
    private let indexInode: UInt64
    private let parentDevice: dev_t
    private let parentInode: UInt64
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    /// maxPageCount optionally imposes an additional native SQLite growth cap; it never raises the byte quota.
    public init(url: URL, quotaBytes: UInt64 = IndexResourcePolicy.defaultMaxBytes, maxPageCount: UInt32? = nil, minimumAvailableBytes: UInt64 = IndexResourcePolicy.defaultMinimumAvailableBytes) throws {
        self.url = url; self.quotaBytes = quotaBytes;self.minimumAvailableBytes = minimumAvailableBytes
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let parentPath=url.deletingLastPathComponent().path
        guard let resolved=realpath(parentPath,nil) else { throw CleanerError(.permissionDenied,"索引父目录不可定位") }
        let canonicalParent=String(cString:resolved);free(resolved)
        guard canonicalParent==parentPath else { throw CleanerError(.scopeEscape,"索引父目录包含路径别名，拒绝维护") }
        let parentAnchor=open(parentPath,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentAnchor >= 0 else { throw CleanerError(.permissionDenied,"索引父目录不可打开") }
        defer { close(parentAnchor) }
        var parentStat=stat()
        guard fstat(parentAnchor,&parentStat)==0,parentStat.st_uid==getuid() else { throw CleanerError(.protected,"索引父目录不是当前用户拥有") }
        parentDevice=parentStat.st_dev;parentInode=parentStat.st_ino
        // Never follow a pre-existing index symlink.
        var s = stat()
        if lstat(url.path, &s) == 0 && s.st_mode & S_IFMT != S_IFREG { throw CleanerError(.invalidInput, "索引路径不是普通文件") }
        let anchor=open(url.path,O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard anchor >= 0 else { throw CleanerError(.permissionDenied,"无法固定索引身份") }
        defer { close(anchor) }
        var anchored=stat()
        guard fstat(anchor,&anchored)==0,anchored.st_mode & S_IFMT == S_IFREG,anchored.st_uid==getuid(),anchored.st_nlink==1 else { throw CleanerError(.protected,"索引不是当前用户拥有的普通文件") }
        indexDevice=anchored.st_dev;indexInode=anchored.st_ino
        // Probe unknown versions through a read-only connection before permissions, journal mode or DDL.
        var probe:OpaquePointer?
        guard sqlite3_open_v2(url.path,&probe,SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW,nil)==SQLITE_OK,let probe else { if let probe { sqlite3_close(probe) };throw CleanerError(.invalidInput,"索引版本无法只读核验") }
        do { _=try supportedIndexVersion(probe) }
        catch { sqlite3_close(probe);throw error }
        sqlite3_close(probe)
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK, let connection else { if let connection { sqlite3_close(connection) }; throw CleanerError(.quotaExceeded, "索引无法创建") }
        handle = SQLiteHandle(connection)
        var opened=stat()
        guard lstat(url.path,&opened)==0,opened.st_dev==anchored.st_dev,opened.st_ino==anchored.st_ino else { throw CleanerError(.identityChanged,"打开时索引身份改变") }
        let oldVersion=try supportedIndexVersion(connection)
        compact=CompactIndexAdapter(connection)
        guard fchmod(parentAnchor,0o700)==0,fchmod(anchor,0o600)==0 else { throw CleanerError(.permissionDenied,"无法保护索引权限") }
        if oldVersion<5 {
        let schema = """
        PRAGMA journal_mode=DELETE;
        PRAGMA synchronous=FULL;
        CREATE TABLE IF NOT EXISTS scans(id TEXT PRIMARY KEY,json TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS entries(id TEXT PRIMARY KEY,scan TEXT NOT NULL,parent TEXT,path TEXT NOT NULL,json TEXT NOT NULL,kind TEXT,logical INTEGER,allocated INTEGER,unknown INTEGER NOT NULL,candidate INTEGER NOT NULL,aggregate_logical INTEGER NOT NULL DEFAULT 0,aggregate_allocated INTEGER NOT NULL DEFAULT 0,aggregate_unknown INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS entry_parent ON entries(scan,parent);
        CREATE INDEX IF NOT EXISTS entry_allocated ON entries(scan,allocated);
        CREATE TABLE IF NOT EXISTS measured(scan TEXT,device TEXT,inode TEXT,PRIMARY KEY(scan,device,inode));
        """
        guard sqlite3_exec(connection, schema, nil, nil, nil) == SQLITE_OK else { throw CleanerError(.invalidInput, "索引结构初始化失败") }
        var columns: Set<String> = []
        var info: OpaquePointer?
        sqlite3_prepare_v2(connection,"PRAGMA table_info(entries)",-1,&info,nil)
        while sqlite3_step(info) == SQLITE_ROW { if let name=sqlite3_column_text(info,1) { columns.insert(String(cString:name)) } }
        sqlite3_finalize(info)
        guard sqlite3_exec(connection,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"无法开始索引升级") }
        var migrationCommitted = false
        defer { if !migrationCommitted { sqlite3_exec(connection,"ROLLBACK",nil,nil,nil) } }
        var scanColumns: OpaquePointer?
        guard sqlite3_prepare_v2(connection,"PRAGMA table_info(scans)",-1,&scanColumns,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"无法检查扫描记录结构") }
        var hasSummary=false
        var scanColumnStatus=sqlite3_step(scanColumns)
        while scanColumnStatus==SQLITE_ROW {
            if let name=sqlite3_column_text(scanColumns,1),String(cString:name)=="summary" { hasSummary=true }
            scanColumnStatus=sqlite3_step(scanColumns)
        }
        sqlite3_finalize(scanColumns)
        guard scanColumnStatus==SQLITE_DONE else { throw CleanerError(.invalidInput,"扫描记录结构检查未完成") }
        if !hasSummary {
            guard sqlite3_exec(connection,"ALTER TABLE scans ADD COLUMN summary TEXT",nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"摘要结构升级失败") }
        }
        let newFields=[("category","TEXT NOT NULL DEFAULT 'other'"),("counted_logical","INTEGER NOT NULL DEFAULT 0"),("counted_allocated","INTEGER NOT NULL DEFAULT 0"),("unique_leaf","INTEGER NOT NULL DEFAULT 0"),("modified","INTEGER NOT NULL DEFAULT 0"),("preview_cache","INTEGER NOT NULL DEFAULT 0")]
        for (name,type) in newFields where !columns.contains(name) {
            guard sqlite3_exec(connection,"ALTER TABLE entries ADD COLUMN \(name) \(type)",nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"索引升级失败") }
        }
        if oldVersion < 2 {
            var rows: OpaquePointer?
            guard sqlite3_prepare_v2(connection,"SELECT id,json,CASE WHEN kind IS NOT NULL AND kind!='directory' THEN row_number() OVER (PARTITION BY scan,json_extract(json,'$.identity.device'),json_extract(json,'$.identity.inode') ORDER BY rowid) ELSE 0 END FROM entries",-1,&rows,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"旧索引查询失败") }
            var migrationStatus=sqlite3_step(rows)
            while migrationStatus==SQLITE_ROW {
                guard let raw=sqlite3_column_text(rows,1),let id=sqlite3_column_text(rows,0),let entry=try? Codec.decoder().decode(Entry.self,from:Data(String(cString:raw).utf8)) else { sqlite3_finalize(rows); throw CleanerError(.invalidInput,"旧索引损坏") }
                var update: OpaquePointer?
                sqlite3_prepare_v2(connection,"UPDATE entries SET category=?,counted_logical=?,counted_allocated=?,unique_leaf=?,modified=?,preview_cache=? WHERE id=?",-1,&update,nil)
                let unique=sqlite3_column_int64(rows,2)==1
                let values: [String] = [StorageClassifier.category(relativePath:entry.relativePath,identity:entry.identity,decision:entry.decision).rawValue,String(unique ? entry.logicalBytes?.value ?? 0 : 0),String(unique ? entry.allocatedBytes?.value ?? 0 : 0),unique ? "1":"0",String(Int64(entry.identity?.mtimeNs ?? "0") ?? 0),Self.cacheCandidate(entry) ? "1":"0",String(cString:id)]
                for (i,value) in values.enumerated() { sqlite3_bind_text(update,Int32(i+1),value,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
                guard sqlite3_step(update)==SQLITE_DONE else { sqlite3_finalize(update);sqlite3_finalize(rows);throw CleanerError(.invalidInput,"旧索引迁移失败") }
                sqlite3_finalize(update)
                migrationStatus=sqlite3_step(rows)
            }
            sqlite3_finalize(rows)
            guard migrationStatus==SQLITE_DONE else { throw CleanerError(.invalidInput,"旧索引查询未完成，已回滚升级") }
        }
        let counterSchema="""
        CREATE TABLE IF NOT EXISTS scan_totals(scan TEXT PRIMARY KEY,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,unknown INTEGER NOT NULL,entry_count INTEGER NOT NULL,large_count INTEGER NOT NULL,preview_count INTEGER NOT NULL,preview_bytes INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS category_totals(scan TEXT NOT NULL,category TEXT NOT NULL,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,file_count INTEGER NOT NULL,PRIMARY KEY(scan,category));
        CREATE INDEX IF NOT EXISTS entry_issues ON entries(scan,unknown,path) WHERE unknown=1;
        CREATE INDEX IF NOT EXISTS entry_topfolders ON entries(scan,parent,kind,aggregate_allocated DESC,path) WHERE kind='directory';
        """
        guard sqlite3_exec(connection,counterSchema,nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"增量统计结构初始化失败") }
        if oldVersion < 4 {
            guard sqlite3_exec(connection,"DELETE FROM scan_totals; DELETE FROM category_totals",nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"增量统计重建失败") }
            var totals:[String:StoreScanCounter]=[:]
            var categories:[String:[StorageCategory:StoreCategoryCounter]]=[:]
            var scans:OpaquePointer?
            guard sqlite3_prepare_v2(connection,"SELECT id FROM scans WHERE summary IS NULL OR EXISTS(SELECT 1 FROM entries WHERE entries.scan=scans.id)",-1,&scans,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"扫描统计迁移查询失败") }
            var scanStatus=sqlite3_step(scans)
            while scanStatus==SQLITE_ROW {
                guard let raw=sqlite3_column_text(scans,0),UUID(uuidString:String(cString:raw)) != nil else { sqlite3_finalize(scans);throw CleanerError(.invalidInput,"扫描统计ID损坏") }
                let id=String(cString:raw);totals[id]=StoreScanCounter();categories[id]=[:]
                scanStatus=sqlite3_step(scans)
            }
            sqlite3_finalize(scans)
            guard scanStatus==SQLITE_DONE else { throw CleanerError(.invalidInput,"扫描统计迁移未完成") }
            var rows:OpaquePointer?
            guard sqlite3_prepare_v2(connection,"SELECT scan,category,counted_logical,counted_allocated,unique_leaf,unknown,kind,logical,preview_cache FROM entries",-1,&rows,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"旧统计查询失败") }
            var status=sqlite3_step(rows)
            do {
                while status==SQLITE_ROW {
                    guard let scanRaw=sqlite3_column_text(rows,0),let catRaw=sqlite3_column_text(rows,1),let category=StorageCategory(rawValue:String(cString:catRaw)) else { throw CleanerError(.invalidInput,"旧统计分类损坏") }
                    let scan=String(cString:scanRaw)
                    guard totals[scan] != nil else { throw CleanerError(.invalidInput,"统计引用缺失扫描") }
                    let logical=try nonnegativeSQLiteInteger(rows,2),allocated=try nonnegativeSQLiteInteger(rows,3),unique=try nonnegativeSQLiteInteger(rows,4),unknown=try nonnegativeSQLiteInteger(rows,5),preview=try nonnegativeSQLiteInteger(rows,8)
                    guard unique<=1,unknown<=1,preview<=1 else { throw CleanerError(.invalidInput,"旧统计Boolean损坏") }
                    let kind=sqlite3_column_text(rows,6).map { String(cString:$0) }
                    let rawLogical=sqlite3_column_type(rows,7)==SQLITE_NULL ? 0 : try nonnegativeSQLiteInteger(rows,7)
                    let large:Int64 = kind=="regular" && rawLogical>=536870912 ? 1:0
                    let delta=StoreScanCounter(logical:logical,allocated:allocated,unknown:unknown,entryCount:1,largeCount:large,previewCount:preview,previewBytes:preview==1 ? allocated:0)
                    try totals[scan]!.add(delta)
                    var counter=categories[scan]?[category] ?? StoreCategoryCounter()
                    try counter.add(StoreCategoryCounter(logical:logical,allocated:allocated,fileCount:unique))
                    categories[scan,default:[:]][category]=counter
                    status=sqlite3_step(rows)
                }
            } catch { sqlite3_finalize(rows);throw error }
            sqlite3_finalize(rows)
            guard status==SQLITE_DONE else { throw CleanerError(.invalidInput,"旧统计读取未完成，已回滚升级") }
            for (scan,total) in totals {
                try writeNativeCounter(connection,"INSERT INTO scan_totals VALUES(?,?,?,?,?,?,?,?)",[scan]+total.values)
                for category in StorageCategory.allCases {
                    let counter=categories[scan]?[category] ?? StoreCategoryCounter()
                    try writeNativeCounter(connection,"INSERT INTO category_totals VALUES(?,?,?,?,?)",[scan,category.rawValue]+counter.values)
                }
            }
        }
        var sourceStat=stat()
        guard fstat(anchor,&sourceStat)==0 else { throw CleanerError(.permissionDenied,"无法核验迁移源大小") }
        let available=try url.deletingLastPathComponent().resourceValues(forKeys:[.volumeAvailableCapacityKey]).volumeAvailableCapacity
        guard let available,available>=0,UInt64(available)>=UInt64(max(0,sourceStat.st_size))*3+64*1024*1024 else { throw CleanerError(.quotaExceeded,"紧凑迁移临时空间不足，已回滚旧索引") }
        try compact.migrateLegacy()
        guard sqlite3_exec(connection,"PRAGMA user_version=5; COMMIT",nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"索引升级提交失败") }
        migrationCommitted = true
        if sourceStat.st_size>0 {
            guard sqlite3_exec(connection,"VACUUM",nil,nil,nil)==SQLITE_OK else { throw CleanerError(.quotaExceeded,"紧凑迁移已提交，压缩索引失败；停止扫描并保留可重试索引") }
            var after=stat();guard lstat(url.path,&after)==0,after.st_dev==anchored.st_dev,after.st_ino==anchored.st_ino else { throw CleanerError(.identityChanged,"迁移压缩后的索引身份改变") }
        }
        }
        try compact.installFunctions()
        if let maxPageCount {
            guard maxPageCount > 0,sqlite3_exec(connection,"PRAGMA max_page_count=\(maxPageCount)",nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"SQLite页数限制无效") }
        }
    }
    private static func cacheCandidate(_ e: Entry) -> Bool {
        e.decision.disposition == .candidate && e.decision.ruleIDs.contains { $0.hasPrefix("RULE-DEV-") || $0.hasPrefix("RULE-AI-") }
    }
    private func sql(_ query: String, values: [String?] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else { throw CleanerError(.invalidInput, "索引查询失败") }
        for (i, value) in values.enumerated() { if let value { sqlite3_bind_text(statement, Int32(i + 1), value, -1, transient) } else { sqlite3_bind_null(statement, Int32(i + 1)) } }
        return statement
    }
    private func execute(_ query: String, _ values: [String?] = []) throws {
        let statement = try sql(query, values: values); defer { sqlite3_finalize(statement) }
        let status=sqlite3_step(statement)
        guard status == SQLITE_DONE else { throw CleanerError(.quotaExceeded, "索引写入失败（SQLite \(status)：\(String(cString:sqlite3_errmsg(db)))），操作已停止") }
    }
    private func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try Codec.encoder().encode(value), as: UTF8.self) }
    public func run(id: UUID) throws -> ScanRun? {
        let statement = try sql("SELECT json FROM scans WHERE id=?", values:[id.uuidString]); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement,0) else { return nil }
        return try Codec.decoder().decode(ScanRun.self,from:Data(String(cString:value).utf8))
    }
    /// Restores a retained result snapshot only. Never resumes I/O, selection or execution.
    public func latestRetainedTerminalRun() throws -> ScanRun? {
        let statement=try sql("SELECT id,json FROM scans WHERE EXISTS(SELECT 1 FROM entry_nodes n WHERE n.scan=scans.sid)")
        defer { sqlite3_finalize(statement) }
        var latest:ScanRun?
        var status=sqlite3_step(statement)
        while status==SQLITE_ROW {
            guard let idRaw=sqlite3_column_text(statement,0),let id=UUID(uuidString:String(cString:idRaw)),let raw=sqlite3_column_text(statement,1) else { throw CleanerError(.invalidInput,"保留扫描记录损坏，未恢复结果") }
            let run:ScanRun
            do { run=try Codec.decoder().decode(ScanRun.self,from:Data(String(cString:raw).utf8)) }
            catch { throw CleanerError(.invalidInput,"保留扫描记录无法解析，未恢复结果") }
            guard run.id==id else { throw CleanerError(.invalidInput,"扫描记录身份不一致，未恢复结果") }
            if [.completed,.partial,.cancelled,.failed].contains(run.state) {
                let timestamp=run.finishedAt ?? run.startedAt
                if let previous=latest {
                    let previousTimestamp=previous.finishedAt ?? previous.startedAt
                    if timestamp>previousTimestamp || (timestamp==previousTimestamp && run.id.uuidString>previous.id.uuidString) { latest=run }
                } else { latest=run }
            }
            status=sqlite3_step(statement)
        }
        guard status==SQLITE_DONE else { throw CleanerError(.invalidInput,"保留扫描查询未完成，未恢复结果") }
        return latest
    }
    private func assertIndexIdentity() throws {
        var current=stat(),parent=stat(),moved:Int32=1
        guard lstat(url.deletingLastPathComponent().path,&parent)==0,parent.st_mode & S_IFMT == S_IFDIR,parent.st_uid==getuid(),parent.st_dev==parentDevice,parent.st_ino==parentInode else { throw CleanerError(.identityChanged,"本应用索引父目录身份改变，拒绝维护") }
        guard lstat(url.path,&current)==0,current.st_mode & S_IFMT == S_IFREG,current.st_uid==getuid(),current.st_nlink==1,current.st_dev==indexDevice,current.st_ino==indexInode else { throw CleanerError(.identityChanged,"本应用索引身份改变，拒绝维护") }
        guard sqlite3_file_control(db,"main",SQLITE_FCNTL_HAS_MOVED,&moved)==SQLITE_OK,moved==0 else { throw CleanerError(.identityChanged,"SQLite连接与索引路径不一致，拒绝维护") }
    }
    /// Explicit app-index maintenance only. Caller must invalidate plans and supply every pending/recovery scan ID.
    /// Targets, receipts and staging are never opened or removed here.
    public func retireTerminalScans(protectedScanIDs: Set<UUID>) throws -> UInt64 {
        try assertIndexIdentity()
        let query=try sql("SELECT id,json FROM scans WHERE EXISTS(SELECT 1 FROM entry_nodes WHERE entry_nodes.scan=scans.sid)")
        var retired:[UUID]=[]
        var status=sqlite3_step(query)
        while status==SQLITE_ROW {
            guard let raw=sqlite3_column_text(query,1),let idText=sqlite3_column_text(query,0),let id=UUID(uuidString:String(cString:idText)) else { sqlite3_finalize(query);throw CleanerError(.invalidInput,"扫描历史损坏，拒绝维护") }
            let run:ScanRun
            do { run=try Codec.decoder().decode(ScanRun.self,from:Data(String(cString:raw).utf8)) }
            catch { sqlite3_finalize(query);throw CleanerError(.invalidInput,"扫描历史无法解析，拒绝维护") }
            if !protectedScanIDs.contains(id) && [.completed,.partial,.cancelled,.failed].contains(run.state) { retired.append(id) }
            status=sqlite3_step(query)
        }
        sqlite3_finalize(query)
        guard status==SQLITE_DONE else { throw CleanerError(.invalidInput,"扫描历史查询未完成") }
        let allocation=try size()
        let freePages=try sql("PRAGMA freelist_count")
        guard sqlite3_step(freePages)==SQLITE_ROW else { sqlite3_finalize(freePages);throw CleanerError(.invalidInput,"无法核验索引可复用页") }
        let reusable=sqlite3_column_int64(freePages,0)
        sqlite3_finalize(freePages)
        guard !retired.isEmpty || (allocation>=quotaBytes && reusable>0) else { return 0 }
        let volume=try url.deletingLastPathComponent().resourceValues(forKeys:[.volumeAvailableCapacityKey])
        guard let available=volume.volumeAvailableCapacity,available>=0,UInt64(available) >= allocation + 32*1024*1024 else { throw CleanerError(.quotaExceeded,"索引压缩所需临时空间不足，未执行维护") }
        try execute("BEGIN IMMEDIATE")
        do {
            for id in retired {
                let snapshot=try summary(scanID:id)
                let archived=ArchivedScanSummary(snapshot)
                try execute("UPDATE scans SET summary=? WHERE id=?",[try json(archived),id.uuidString])
                try execute("DELETE FROM scan_totals WHERE scan=?",[id.uuidString])
                try execute("DELETE FROM category_totals WHERE scan=?",[id.uuidString])
                try compact.execute("DELETE FROM inode_seen WHERE scan=?",[String(try compact.scan(id))])
                try execute("DELETE FROM entry_nodes WHERE scan=?",[String(try compact.scan(id))])
            }
            try assertIndexIdentity()
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK");compact.resetCaches();throw error }
        compact.resetCaches()
        try assertIndexIdentity()
        try execute("VACUUM")
        try assertIndexIdentity()
        return UInt64(retired.count)
    }
    public func create(_ run: ScanRun) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("INSERT INTO scans(id,json,sid) VALUES(?,?,(SELECT coalesce(max(sid),0)+1 FROM scans))",[run.id.uuidString,try json(run)])
            try execute("INSERT INTO scan_totals VALUES(?,0,0,0,0,0,0,0)",[run.id.uuidString])
            for category in StorageCategory.allCases { try execute("INSERT INTO category_totals VALUES(?,?,0,0,0)",[run.id.uuidString,category.rawValue]) }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK");compact.resetCaches();throw error }
    }
    public func update(_ run: ScanRun) throws { try execute("UPDATE scans SET json=? WHERE id=?", [try json(run), run.id.uuidString]) }
    private func size() throws -> UInt64 {
        let statement = try sql("SELECT (SELECT page_count FROM pragma_page_count)*(SELECT page_size FROM pragma_page_size)"); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw CleanerError(.quotaExceeded, "无法核验索引容量") }
        return UInt64(max(0, sqlite3_column_int64(statement, 0)))
    }
    private func requireAvailableReserve() throws {
        try assertIndexIdentity()
        var filesystem=statfs()
        guard statfs(url.deletingLastPathComponent().path,&filesystem)==0 else { throw CleanerError(.quotaExceeded,"无法确认索引所在文件系统余量，未提交本批结果") }
        let available=try IndexResourcePolicy.availableBytes(blocks:UInt64(filesystem.f_bavail),blockSize:UInt64(filesystem.f_bsize))
        var effectiveAvailable=available
        #if DEBUG
        if !reserveCeilingsForTesting.isEmpty { effectiveAvailable=min(available,reserveCeilingsForTesting.removeFirst()) }
        #endif
        guard effectiveAvailable>=minimumAvailableBytes else { throw CleanerError(.quotaExceeded,"磁盘余量低于索引保护下限\(minimumAvailableBytes)字节，未提交本批结果") }
    }
    public func insert(_ entries: [Entry]) throws {
        try compact.synchronizeExternalChanges()
        try requireAvailableReserve()
        guard try size() < quotaBytes else { throw CleanerError(.quotaExceeded, "索引达到容量上限，请缩小扫描范围") }
        try execute("BEGIN IMMEDIATE")
        do {
            var totals:[UUID:StoreScanCounter]=[:]
            var categoryDeltas:[UUID:[StorageCategory:StoreCategoryCounter]]=[:]
            for e in entries {
                if totals[e.scanID]==nil {
                    let current=try sql("SELECT logical,allocated,unknown,entry_count,large_count,preview_count,preview_bytes FROM scan_totals WHERE scan=?",values:[e.scanID.uuidString]);defer { sqlite3_finalize(current) }
                    guard sqlite3_step(current)==SQLITE_ROW else { throw CleanerError(.invalidInput,"批次引用缺失扫描统计") }
                    totals[e.scanID]=try StoreScanCounter(statement:current)
                }
                for bytes in [e.logicalBytes?.value, e.allocatedBytes?.value] { if let bytes, bytes > UInt64(Int64.max) { throw CleanerError(.invalidInput, "字节数溢出") } }
                let unknown = e.measureState == .measured ? 0 : 1
                let rid=try compact.insert(e)

                var logical: UInt64 = 0, allocated: UInt64 = 0
                var unique = false
                if let identity = e.identity, identity.kind != .directory {
                    if try compact.markInode(scan:compact.scan(e.scanID),device:identity.device.value,inode:identity.inode.value) { unique = true; logical = e.logicalBytes?.value ?? 0; allocated = e.allocatedBytes?.value ?? 0 }
                }
                let category=StorageClassifier.category(relativePath:e.relativePath,identity:e.identity,decision:e.decision)
                try execute("UPDATE entry_nodes SET category=?,counted_logical=?,counted_allocated=?,unique_leaf=?,modified=?,preview_cache=? WHERE rid=?",[String(StorageCategory.allCases.firstIndex(of:category)!),String(logical),String(allocated),unique ? "1":"0",e.identity?.mtimeNs ?? "0",Self.cacheCandidate(e) ? "1":"0",String(rid)])
                let preview=Self.cacheCandidate(e)
                let delta=StoreScanCounter(logical:Int64(logical),allocated:Int64(allocated),unknown:Int64(unknown),entryCount:1,largeCount:e.identity?.kind == .regular && (e.logicalBytes?.value ?? 0)>=536870912 ? 1:0,previewCount:preview ? 1:0,previewBytes:preview ? Int64(allocated):0)
                try totals[e.scanID]!.add(delta)
                var categoryDelta=categoryDeltas[e.scanID]?[category] ?? StoreCategoryCounter()
                try categoryDelta.add(StoreCategoryCounter(logical:Int64(logical),allocated:Int64(allocated),fileCount:unique ? 1:0))
                categoryDeltas[e.scanID,default:[:]][category]=categoryDelta
                if let parent = e.parentID {
                    // Increment all already-persisted ancestors; no recursive size double counting.
                    try execute("WITH RECURSIVE ancestors(rid,parent,scan) AS (SELECT rid,parent,scan FROM entry_nodes WHERE rid=? AND scan=? UNION SELECT e.rid,e.parent,e.scan FROM entry_nodes e JOIN ancestors a ON e.rid=a.parent AND e.scan=a.scan) UPDATE entry_nodes SET aggregate_logical=aggregate_logical+?,aggregate_allocated=aggregate_allocated+?,aggregate_unknown=aggregate_unknown+? WHERE rid IN (SELECT rid FROM ancestors) AND EXISTS(SELECT 1 FROM ancestors WHERE parent IS NULL)", [String(try compact.node(parent)),String(try compact.scan(e.scanID)),String(logical),String(allocated),String(unknown)])
                    guard sqlite3_changes(db)>0 else { throw CleanerError(.invalidInput,"祖先链未到达合法同扫描根，批次已拒绝") }
                }
            }
            for (scan,total) in totals {
                try execute("UPDATE scan_totals SET logical=?,allocated=?,unknown=?,entry_count=?,large_count=?,preview_count=?,preview_bytes=? WHERE scan=?",total.values+[scan.uuidString])
                for (category,delta) in categoryDeltas[scan] ?? [:] {
                    let current=try sql("SELECT logical,allocated,file_count FROM category_totals WHERE scan=? AND category=?",values:[scan.uuidString,category.rawValue]);defer { sqlite3_finalize(current) }
                    guard sqlite3_step(current)==SQLITE_ROW else { throw CleanerError(.invalidInput,"分类增量引用缺失") }
                    var updated=try StoreCategoryCounter(statement:current)
                    try updated.add(delta)
                    try execute("UPDATE category_totals SET logical=?,allocated=?,file_count=? WHERE scan=? AND category=?",updated.values+[scan.uuidString,category.rawValue])
                }
            }
            guard try size() <= quotaBytes else { throw CleanerError(.quotaExceeded, "索引达到容量上限，请缩小扫描范围") }
            try requireAvailableReserve()
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK");compact.resetCaches(); throw error }
    }
    private func readEntries(_ query: String, _ values: [String?], hydrate: Bool = true) throws -> [Entry] {
        try compact.synchronizeExternalChanges()
        let select=query.replacingOccurrences(of:"SELECT json,",with:"SELECT lmc_entry(rid,\(hydrate ? 1:0)),")
        let statement = try sql(select, values: values); defer { sqlite3_finalize(statement) }
        var result: [Entry] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let data = sqlite3_column_text(statement, 0) else { throw CleanerError(.invalidInput,"索引条目损坏") }
            let decoded=try Codec.decoder().decode(Entry.self,from:Data(String(cString:data).utf8))
            let e=decoded
            if e.identity?.kind == .directory {
                let gaps = sqlite3_column_int64(statement, 3)
                result.append(Entry(id:e.id,scanID:e.scanID,parentID:e.parentID,relativePath:e.relativePath,identity:e.identity,logicalBytes:UInt64(max(0,sqlite3_column_int64(statement,1))),allocatedBytes:UInt64(max(0,sqlite3_column_int64(statement,2))),measureState:e.measureState != .measured ? e.measureState : (gaps > 0 ? .partial : .measured),decision:e.decision))
            } else { result.append(e) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw CleanerError(.invalidInput,"索引读取未完成") }
        return result
    }
    public func page(scanID: UUID, offset: Int, limit: Int, parentID: UUID? = nil, search: String = "", candidatesOnly: Bool = false, largeOnly: Bool = false) throws -> [Entry] {
        guard offset >= 0, limit > 0, limit <= 1000 else { throw CleanerError(.invalidInput,"非法分页参数") }
        var query = "SELECT json,aggregate_logical,aggregate_allocated,aggregate_unknown FROM entry_nodes WHERE scan=?"
        var values: [String?] = [String(try compact.scan(scanID))]
        if let parentID { query += " AND parent=?"; values.append(String(try compact.node(parentID))) }
        if !search.isEmpty { query += " AND instr(lmc_path(rid),?)>0"; values.append(search) }
        if candidatesOnly { query += " AND candidate=1" }
        if largeOnly { query += " AND kind='regular' AND logical>=536870912" }
        query += " ORDER BY CASE WHEN kind='directory' THEN aggregate_allocated ELSE allocated END DESC,lmc_path(rid) LIMIT ? OFFSET ?"
        values += [String(limit),String(offset)]
        return try readEntries(query, values)
    }
    /// Visualization attribution only. Raw Entry sizes remain native stat metadata.
    /// Hardlink aliases contribute zero after their first encountered inode; this is not reclaimable space.
    public func mapWeights(scanID: UUID, parentID: UUID?, ids: Set<UUID>? = nil) throws -> [UUID:UInt64] {
        var query="SELECT id,CASE WHEN kind='directory' THEN aggregate_allocated ELSE counted_allocated END FROM entry_nodes WHERE scan=? AND parent="
        var values:[String?]=[String(try compact.scan(scanID))]
        if let parentID { query+="?";values.append(String(try compact.node(parentID))) }
        else { query+="(SELECT rid FROM entry_nodes WHERE scan=? AND parent IS NULL)";values.append(String(try compact.scan(scanID))) }
        if let ids {
            guard ids.count <= 1000 else { throw CleanerError(.invalidInput,"地图页项目超过限制") }
            if ids.isEmpty { return [:] }
            let ordered=ids.sorted { $0.uuidString < $1.uuidString }
            query += " AND rid IN (" + Array(repeating:"?",count:ordered.count).joined(separator:",") + ")"
            values += try ordered.map { String(try compact.node($0)) }
        }
        let statement=try sql(query,values:values);defer { sqlite3_finalize(statement) }
        var result:[UUID:UInt64]=[:]
        var status=sqlite3_step(statement)
        while status==SQLITE_ROW {
            guard sqlite3_column_bytes(statement,0)==16,let raw=sqlite3_column_blob(statement,0) else { throw CleanerError(.invalidInput,"地图项目ID损坏") };let id=try CompactIndexAdapter.uuid(Data(bytes:raw,count:16))
            result[id]=UInt64(max(0,sqlite3_column_int64(statement,1)))
            status=sqlite3_step(statement)
        }
        guard status==SQLITE_DONE else { throw CleanerError(.invalidInput,"地图计量查询未完成") }
        return result
    }
    public func children(scanID: UUID, parentID: UUID?, offset: Int = 0, limit: Int = 100, search: String = "", sort: StorageSort = .allocated, category: StorageCategory? = nil, largeOnly: Bool = false, candidatesOnly: Bool = false) throws -> [Entry] {
        guard offset >= 0,limit > 0,limit <= 1000 else { throw CleanerError(.invalidInput,"非法分页参数") }
        var query="SELECT json,aggregate_logical,aggregate_allocated,aggregate_unknown FROM entry_nodes WHERE scan=? AND parent="
        var values:[String?]=[String(try compact.scan(scanID))]
        if let parentID { query+="?";values.append(String(try compact.node(parentID))) }
        else { query+="(SELECT rid FROM entry_nodes WHERE scan=? AND parent IS NULL)";values.append(String(try compact.scan(scanID))) }
        if !search.isEmpty { query+=" AND instr(lmc_path(rid),?)>0";values.append(search) }
        if let category { query+=" AND category=?";values.append(String(StorageCategory.allCases.firstIndex(of:category)!)) }
        if largeOnly { query+=" AND kind='regular' AND logical>=536870912" }
        if candidatesOnly { query+=" AND preview_cache=1" }
        let order: String
        switch sort { case .allocated: order="CASE WHEN kind='directory' THEN aggregate_allocated ELSE allocated END";case .logical: order="CASE WHEN kind='directory' THEN aggregate_logical ELSE logical END";case .modified: order="modified" }
        query+=" ORDER BY \(order) DESC,path LIMIT ? OFFSET ?";values += [String(limit),String(offset)]
        return try readEntries(query,values)
    }
    public func catalog(scanID: UUID, offset: Int = 0, limit: Int = 100, search: String = "", sort: StorageSort = .allocated, category: StorageCategory? = nil, largeOnly: Bool = false, candidatesOnly: Bool = false, issuesOnly: Bool = false) throws -> [Entry] {
        guard offset >= 0,limit > 0,limit <= 1000 else { throw CleanerError(.invalidInput,"非法分页参数") }
        var query="SELECT json,aggregate_logical,aggregate_allocated,aggregate_unknown FROM entry_nodes WHERE scan=?"
        var values:[String?]=[String(try compact.scan(scanID))]
        let issue = issuesOnly ? try globalIssue(scanID:scanID) : nil
        let syntheticMatches: Bool
        if let issue {
            syntheticMatches = (search.isEmpty || issue.relativePath.contains(search) || issue.decision.reason.contains(search)) && category==nil && !largeOnly && !candidatesOnly
        } else { syntheticMatches = false }
        query += issuesOnly ? " AND unknown=1" : " AND kind!='directory'"
        if !search.isEmpty {
            let key=String(try compact.scan(scanID))
            if !search.contains("/") {
                query="WITH RECURSIVE matched(rid) AS (SELECT rid FROM entry_nodes WHERE scan=? AND kind='directory' AND instr(path,?)>0 UNION SELECT n.rid FROM entry_nodes n JOIN matched m ON n.parent=m.rid WHERE n.scan=? AND n.kind='directory') "+query
                values=[key,search,key]+values
                query+=" AND (instr(path,?)>0 OR parent IN (SELECT rid FROM matched))";values.append(search)
            } else {
                let split=search.lastIndex(of:"/")!
                let parentPart=String(search[..<split]),leafPart=String(search[search.index(after:split)...])
                let suffix=parentPart.isEmpty ? "parent IS NOT NULL":"substr(lmc_path(rid),-length(?))=?"
                query="WITH RECURSIVE matched(rid) AS (SELECT rid FROM entry_nodes WHERE scan=? AND kind='directory' AND instr(lmc_path(rid),?)>0 UNION SELECT n.rid FROM entry_nodes n JOIN matched m ON n.parent=m.rid WHERE n.scan=? AND n.kind='directory'), parent_match(rid) AS (SELECT rid FROM entry_nodes WHERE scan=? AND kind='directory' AND "+suffix+") "+query
                var prefix:[String?]=[key,search,key,key]
                if !parentPart.isEmpty { prefix += [parentPart,parentPart] }
                values=prefix+values
                query+=" AND (parent IN (SELECT rid FROM matched) OR (parent IN (SELECT rid FROM parent_match) AND substr(path,1,length(?))=?))";values += [leafPart,leafPart]
            }
        }
        if let category { query+=" AND category=?";values.append(String(StorageCategory.allCases.firstIndex(of:category)!)) }
        if largeOnly { query+=" AND kind='regular' AND logical>=536870912" }
        if candidatesOnly { query+=" AND preview_cache=1" }
        let order: String
        switch sort { case .allocated: order=issuesOnly ? "CASE WHEN kind='directory' THEN aggregate_allocated ELSE allocated END":"allocated";case .logical: order=issuesOnly ? "CASE WHEN kind='directory' THEN aggregate_logical ELSE logical END":"logical";case .modified: order="modified" }
        query+=" ORDER BY \(order) DESC,lmc_path(rid) LIMIT ? OFFSET ?";values += [String(limit),String(syntheticMatches ? max(0,offset-1) : offset)]
        var results=try readEntries(query,values)
        if offset==0,syntheticMatches,let issue {
            results.insert(issue,at:0);results=Array(results.prefix(limit))
        }
        return results
    }
    private func globalIssue(scanID:UUID) throws -> Entry? {
        guard let run=try run(id:scanID),let reason=run.stopReason else { return nil }
        return Entry(id:run.id,scanID:scanID,parentID:nil,relativePath:"[扫描未完整计量]",identity:nil,logicalBytes:nil,allocatedBytes:nil,measureState:.partial,decision:RuleDecision(disposition:.protect,reasonCodes:["scanStopped"],reason:reason))
    }
    public func dashboard(scanID: UUID) throws -> StorageDashboard {
        let scan=scanID.uuidString
        let grouped=try sql("SELECT category,allocated,logical,file_count FROM category_totals WHERE scan=?",values:[scan]);defer { sqlite3_finalize(grouped) }
        var categories:[CategorySummary]=[]
        var groupStatus=sqlite3_step(grouped)
        while groupStatus==SQLITE_ROW {
            guard let raw=sqlite3_column_text(grouped,0),let category=StorageCategory(rawValue:String(cString:raw)) else { throw CleanerError(.invalidInput,"分类索引损坏") }
            categories.append(CategorySummary(category:category,allocatedBytes:UInt64(max(0,sqlite3_column_int64(grouped,1))),logicalBytes:UInt64(max(0,sqlite3_column_int64(grouped,2))),fileCount:UInt64(max(0,sqlite3_column_int64(grouped,3)))))
            groupStatus=sqlite3_step(grouped)
        }
        guard groupStatus==SQLITE_DONE else { throw CleanerError(.invalidInput,"分类查询未完成") }
        let counts=try sql("SELECT large_count,preview_count,preview_bytes FROM scan_totals WHERE scan=?",values:[scan]);defer { sqlite3_finalize(counts) }
        let countStatus=sqlite3_step(counts)
        guard countStatus==SQLITE_ROW || countStatus==SQLITE_DONE else { throw CleanerError(.invalidInput,"无法读取看板计数") }
        let largeCount=countStatus==SQLITE_ROW ? sqlite3_column_int64(counts,0):0
        let previewCount=countStatus==SQLITE_ROW ? sqlite3_column_int64(counts,1):0
        let previewBytes=countStatus==SQLITE_ROW ? sqlite3_column_int64(counts,2):0
        let folders=try readEntries("SELECT json,aggregate_logical,aggregate_allocated,aggregate_unknown FROM entry_nodes WHERE scan=? AND kind='directory' AND parent=(SELECT rid FROM entry_nodes WHERE scan=? AND parent IS NULL) ORDER BY aggregate_allocated DESC,path LIMIT 20",[String(try compact.scan(scanID)),String(try compact.scan(scanID))],hydrate:false)
        var issues=try readEntries("SELECT json,aggregate_logical,aggregate_allocated,aggregate_unknown FROM entry_nodes WHERE scan=? AND unknown=1 ORDER BY issue_path LIMIT 25",[String(try compact.scan(scanID))],hydrate:false)
        if let issue=try globalIssue(scanID:scanID) { issues.insert(issue,at:0);issues=Array(issues.prefix(25)) }
        return StorageDashboard(summary:try summary(scanID:scanID),categories:categories.sorted { $0.allocatedBytes > $1.allocatedBytes },topFolders:folders,largeFileCount:UInt64(max(0,largeCount)),previewCandidateCount:UInt64(max(0,previewCount)),previewCandidateBytes:UInt64(max(0,previewBytes)),issues:issues)
    }
    public func entries(scanID: UUID, ids: Set<UUID>) throws -> [Entry] {
        var result: [Entry] = []
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) { result += try readEntries("SELECT json,aggregate_logical,aggregate_allocated,aggregate_unknown FROM entry_nodes WHERE scan=? AND rid=?", [String(try compact.scan(scanID)),String(try compact.node(id))]) }
        return result
    }
    public func summary(scanID: UUID) throws -> ScanSummary {
        let statement = try sql("SELECT logical,allocated,unknown,entry_count FROM scan_totals WHERE scan=?",values:[scanID.uuidString]); defer { sqlite3_finalize(statement) }
        let state=sqlite3_step(statement)
        let run=try run(id:scanID)
        let globalUnknown:UInt64 = run?.stopReason != nil || run?.state == .cancelled || run?.state == .failed ? 1 : 0
        if state==SQLITE_ROW {
            return ScanSummary(logical:UInt64(max(0,sqlite3_column_int64(statement,0))),allocated:UInt64(max(0,sqlite3_column_int64(statement,1))),unknown:max(globalUnknown,UInt64(max(0,sqlite3_column_int64(statement,2)))),count:UInt64(max(0,sqlite3_column_int64(statement,3))))
        }
        guard state==SQLITE_DONE else { throw CleanerError(.invalidInput,"扫描摘要查询失败") }
        let history=try sql("SELECT summary FROM scans WHERE id=?",values:[scanID.uuidString]);defer { sqlite3_finalize(history) }
        let historyStatus=sqlite3_step(history)
        if historyStatus==SQLITE_ROW,let raw=sqlite3_column_text(history,0) {
            return try Codec.decoder().decode(ArchivedScanSummary.self,from:Data(String(cString:raw).utf8)).summary
        }
        guard historyStatus==SQLITE_ROW || historyStatus==SQLITE_DONE else { throw CleanerError(.invalidInput,"历史摘要读取失败") }
        return ScanSummary(logical:0,allocated:0,unknown:globalUnknown,count:0)
    }

}

private final class SQLiteHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

private struct ArchivedScanSummary: Codable {
    let logical: Decimal64
    let allocated: Decimal64
    let unknown: Decimal64
    let count: Decimal64
    init(_ summary:ScanSummary) { logical=Decimal64(summary.knownLogicalBytes);allocated=Decimal64(summary.knownAllocatedBytes);unknown=Decimal64(summary.unknownCount);count=Decimal64(summary.entryCount) }
    var summary:ScanSummary { ScanSummary(logical:logical.value,allocated:allocated.value,unknown:unknown.value,count:count.value) }
}

private func checkedCounterAdd(_ a:Int64,_ b:Int64) throws -> Int64 {
    let result=a.addingReportingOverflow(b)
    guard a>=0,b>=0,!result.overflow else { throw CleanerError(.invalidInput,"增量统计溢出") }
    return result.partialValue
}
private func nonnegativeSQLiteInteger(_ statement:OpaquePointer?,_ column:Int32) throws -> Int64 {
    guard sqlite3_column_type(statement,column)==SQLITE_INTEGER else { throw CleanerError(.invalidInput,"统计整数类型损坏") }
    let value=sqlite3_column_int64(statement,column)
    guard value>=0 else { throw CleanerError(.invalidInput,"统计整数为负") }
    return value
}
private func writeNativeCounter(_ db:OpaquePointer,_ query:String,_ values:[String]) throws {
    var stmt:OpaquePointer?
    guard sqlite3_prepare_v2(db,query,-1,&stmt,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"迁移统计写入准备失败") }
    defer { sqlite3_finalize(stmt) }
    for (index,value) in values.enumerated() { sqlite3_bind_text(stmt,Int32(index+1),value,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
    guard sqlite3_step(stmt)==SQLITE_DONE else { throw CleanerError(.invalidInput,"迁移统计写入失败") }
}
private struct StoreScanCounter {
    var logical:Int64=0
    var allocated:Int64=0
    var unknown:Int64=0
    var entryCount:Int64=0
    var largeCount:Int64=0
    var previewCount:Int64=0
    var previewBytes:Int64=0
    init(logical:Int64=0,allocated:Int64=0,unknown:Int64=0,entryCount:Int64=0,largeCount:Int64=0,previewCount:Int64=0,previewBytes:Int64=0) { self.logical=logical;self.allocated=allocated;self.unknown=unknown;self.entryCount=entryCount;self.largeCount=largeCount;self.previewCount=previewCount;self.previewBytes=previewBytes }
    init(statement:OpaquePointer) throws { logical=try nonnegativeSQLiteInteger(statement,0);allocated=try nonnegativeSQLiteInteger(statement,1);unknown=try nonnegativeSQLiteInteger(statement,2);entryCount=try nonnegativeSQLiteInteger(statement,3);largeCount=try nonnegativeSQLiteInteger(statement,4);previewCount=try nonnegativeSQLiteInteger(statement,5);previewBytes=try nonnegativeSQLiteInteger(statement,6) }
    var values:[String] { [logical,allocated,unknown,entryCount,largeCount,previewCount,previewBytes].map(String.init) }
    mutating func add(_ delta:Self) throws { logical=try checkedCounterAdd(logical,delta.logical);allocated=try checkedCounterAdd(allocated,delta.allocated);unknown=try checkedCounterAdd(unknown,delta.unknown);entryCount=try checkedCounterAdd(entryCount,delta.entryCount);largeCount=try checkedCounterAdd(largeCount,delta.largeCount);previewCount=try checkedCounterAdd(previewCount,delta.previewCount);previewBytes=try checkedCounterAdd(previewBytes,delta.previewBytes) }
}
private struct StoreCategoryCounter {
    var logical:Int64=0
    var allocated:Int64=0
    var fileCount:Int64=0
    init(logical:Int64=0,allocated:Int64=0,fileCount:Int64=0) { self.logical=logical;self.allocated=allocated;self.fileCount=fileCount }
    init(statement:OpaquePointer) throws { logical=try nonnegativeSQLiteInteger(statement,0);allocated=try nonnegativeSQLiteInteger(statement,1);fileCount=try nonnegativeSQLiteInteger(statement,2) }
    var values:[String] { [logical,allocated,fileCount].map(String.init) }
    mutating func add(_ delta:Self) throws { logical=try checkedCounterAdd(logical,delta.logical);allocated=try checkedCounterAdd(allocated,delta.allocated);fileCount=try checkedCounterAdd(fileCount,delta.fileCount) }
}

private func supportedIndexVersion(_ db:OpaquePointer) throws -> Int32 {
    var stmt:OpaquePointer?
    guard sqlite3_prepare_v2(db,"PRAGMA user_version",-1,&stmt,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"索引版本读取失败") }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt)==SQLITE_ROW,sqlite3_column_type(stmt,0)==SQLITE_INTEGER else { throw CleanerError(.invalidInput,"索引版本类型无法核验") }
    let version=sqlite3_column_int64(stmt,0)
    guard sqlite3_step(stmt)==SQLITE_DONE else { throw CleanerError(.invalidInput,"索引版本读取未完成") }
    guard version>=0,version<=5 else { throw CleanerError(.invalidInput,"索引版本\(version)不受支持，请升级应用；未修改数据库") }
    if version==5 {
        var shape:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT n.rid,n.id,n.metadata,n.parent,n.scan,n.decision,s.sid,d.did,v.vid FROM entry_nodes n,scans s,decisions d,volumes v LIMIT 0",-1,&shape,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"紧凑schema5结构不完整，请升级或恢复旧索引；未修改数据库") }
        let status=sqlite3_step(shape);sqlite3_finalize(shape)
        guard status==SQLITE_DONE else { throw CleanerError(.invalidInput,"紧凑结构核验未完成") }
    }
    return Int32(version)
}
