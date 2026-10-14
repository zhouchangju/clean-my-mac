import Foundation
import CSQLite
import CleanerDomain

/// Owned exclusively by the store actor and its synchronous SQLite callbacks.
final class CompactIndexAdapter: @unchecked Sendable {
    let db:OpaquePointer
    private var decisions:[String:Int64]=[:]
    private var volumes:[String:Int64]=[:]
    private var scanKeys:[UUID:Int64]=[:]
    private var parents:[UUID:(rid:Int64,scan:Int64,path:String)]=[:]
    private var directoryPaths:[Int64:String]=[:]
    private var lastDataVersion:Int64?
    private let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
    init(_ db:OpaquePointer) { self.db=db }
    func resetCaches() { decisions.removeAll();volumes.removeAll();scanKeys.removeAll();parents.removeAll();directoryPaths.removeAll() }
    func synchronizeExternalChanges() throws {
        let statement=try prepare("PRAGMA data_version");defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement)==SQLITE_ROW else { throw CleanerError(.invalidInput,"无法核验索引外部代次") }
        let version=sqlite3_column_int64(statement,0)
        guard sqlite3_step(statement)==SQLITE_DONE else { throw CleanerError(.invalidInput,"索引代次读取未完成") }
        if let previous=lastDataVersion,previous != version { resetCaches() }
        lastDataVersion=version
    }
    static func uuidData(_ id:UUID)->Data { var bytes=id.uuid;return withUnsafeBytes(of:&bytes) { Data($0) } }
    static func uuid(_ data:Data)throws->UUID { guard data.count==16 else { throw CleanerError(.invalidInput,"索引UUID损坏") };return data.withUnsafeBytes { UUID(uuid:$0.loadUnaligned(as:uuid_t.self)) } }
    func prepare(_ query:String,_ values:[String?]=[],blobs:[Int:Data]=[:])throws->OpaquePointer {
        var stmt:OpaquePointer?;guard sqlite3_prepare_v2(db,query,-1,&stmt,nil)==SQLITE_OK,let stmt else { throw CleanerError(.invalidInput,"紧凑索引查询失败："+String(cString:sqlite3_errmsg(db))) }
        for (index,value) in values.enumerated() { if let value { sqlite3_bind_text(stmt,Int32(index+1),value,-1,transient) } else { sqlite3_bind_null(stmt,Int32(index+1)) } }
        for (index,data) in blobs { _=data.withUnsafeBytes { sqlite3_bind_blob(stmt,Int32(index+1),$0.baseAddress,Int32(data.count),transient) } }
        return stmt
    }
    func execute(_ query:String,_ values:[String?]=[],blobs:[Int:Data]=[:])throws {
        let stmt=try prepare(query,values,blobs:blobs);defer { sqlite3_finalize(stmt) };let status=sqlite3_step(stmt)
        guard status==SQLITE_DONE else { throw CleanerError(.quotaExceeded,"紧凑索引写入失败（SQLite \(status)：\(String(cString:sqlite3_errmsg(db)))）") }
    }
    func scan(_ id:UUID)throws->Int64 {
        if let key=scanKeys[id] { return key }
        let stmt=try prepare("SELECT sid FROM scans WHERE id=?",[id.uuidString]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW else { throw CleanerError(.invalidInput,"扫描引用缺失") }
        let key=sqlite3_column_int64(stmt,0);scanKeys[id]=key;return key
    }
    func node(_ id:UUID)throws->Int64 {
        if let known=parents[id] { return known.rid }
        let stmt=try prepare("SELECT rid FROM entry_nodes WHERE id=?",[nil],blobs:[0:Self.uuidData(id)]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW else { throw CleanerError(.invalidInput,"条目引用缺失") };return sqlite3_column_int64(stmt,0)
    }
    func decision(_ value:RuleDecision)throws->Int64 {
        let json=String(decoding:try Codec.encoder().encode(value),as:UTF8.self)
        if let id=decisions[json] { return id }
        try execute("INSERT OR IGNORE INTO decisions(json) VALUES(?)",[json])
        let stmt=try prepare("SELECT did FROM decisions WHERE json=?",[json]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW else { throw CleanerError(.invalidInput,"决策字典缺失") }
        let id=sqlite3_column_int64(stmt,0);if decisions.count<128 { decisions[json]=id };return id
    }
    func volume(_ value:String)throws->Int64 {
        if let id=volumes[value] { return id }
        try execute("INSERT OR IGNORE INTO volumes(value) VALUES(?)",[value])
        let stmt=try prepare("SELECT vid FROM volumes WHERE value=?",[value]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW else { throw CleanerError(.invalidInput,"卷字典缺失") }
        let id=sqlite3_column_int64(stmt,0);if volumes.count<64 { volumes[value]=id };return id
    }
    func volumeName(_ id:Int64)throws->String {
        let stmt=try prepare("SELECT value FROM volumes WHERE vid=?",[String(id)]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW,let raw=sqlite3_column_text(stmt,0) else { throw CleanerError(.invalidInput,"卷字典损坏") };return String(cString:raw)
    }
    private func blob(_ stmt:OpaquePointer,_ column:Int32)throws->Data {
        let count=Int(sqlite3_column_bytes(stmt,column));guard count>0,count<=65568,let bytes=sqlite3_column_blob(stmt,column) else { throw CleanerError(.invalidInput,"紧凑blob缺失") };return Data(bytes:bytes,count:count)
    }
    func path(_ rid:Int64)throws->String {
        if let value=directoryPaths[rid] { return value }
        let stmt=try prepare("SELECT parent,path,kind FROM entry_nodes WHERE rid=?",[String(rid)]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW,let raw=sqlite3_column_text(stmt,1) else { throw CleanerError(.invalidInput,"路径节点缺失") }
        let name=String(cString:raw)
        let parent=sqlite3_column_type(stmt,0)==SQLITE_NULL ? nil:sqlite3_column_int64(stmt,0)
        let result:String
        if let parent {
            let prefix=try pathBounded(parent,depth:1)
            result=prefix.isEmpty ? name:prefix+"/"+name
        } else { guard name.isEmpty else { throw CleanerError(.invalidInput,"索引根basename非空") };result="" }
        if let kind=sqlite3_column_text(stmt,2),String(cString:kind)=="directory" { if directoryPaths.count>=8192 { directoryPaths.removeAll(keepingCapacity:true) };directoryPaths[rid]=result }
        return result
    }
    private func pathBounded(_ rid:Int64,depth:Int)throws->String {
        guard depth<=128 else { throw CleanerError(.invalidInput,"路径链循环或过深") }
        if let cached=directoryPaths[rid] { return cached }
        let stmt=try prepare("SELECT parent,path,kind FROM entry_nodes WHERE rid=?",[String(rid)]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW,let raw=sqlite3_column_text(stmt,1),let kind=sqlite3_column_text(stmt,2),String(cString:kind)=="directory" else { throw CleanerError(.invalidInput,"父目录路径缺失") }
        let name=String(cString:raw)
        let result:String
        if sqlite3_column_type(stmt,0)==SQLITE_NULL { guard name.isEmpty else { throw CleanerError(.invalidInput,"路径根缺失") };result="" }
        else { let prefix=try pathBounded(sqlite3_column_int64(stmt,0),depth:depth+1);result=prefix.isEmpty ? name:prefix+"/"+name }
        if directoryPaths.count>=8192 { directoryPaths.removeAll(keepingCapacity:true) };directoryPaths[rid]=result;return result
    }
    private struct Ancestor { let rid:Int64;let parent:Int64?;let name:String;let identity:FileIdentity? }
    private func ancestors(_ rid:Int64,identities:Bool)throws->[Ancestor] {
        let stmt=try prepare("WITH RECURSIVE chain(rid,parent,path,metadata,scan,depth) AS (SELECT rid,parent,path,metadata,scan,0 FROM entry_nodes WHERE rid=? UNION ALL SELECT n.rid,n.parent,n.path,n.metadata,n.scan,c.depth+1 FROM entry_nodes n JOIN chain c ON n.rid=c.parent AND n.scan=c.scan WHERE c.depth<128) SELECT rid,parent,path,metadata FROM chain ORDER BY depth DESC",[String(rid)]);defer { sqlite3_finalize(stmt) }
        var result:[Ancestor]=[];var status=sqlite3_step(stmt)
        while status==SQLITE_ROW {
            guard let raw=sqlite3_column_text(stmt,2) else { throw CleanerError(.invalidInput,"basename缺失") }
            let fi=identities ? try CompactMetadataCodec.decode(blob(stmt,3),volume:volumeName).0:nil
            result.append(Ancestor(rid:sqlite3_column_int64(stmt,0),parent:sqlite3_column_type(stmt,1)==SQLITE_NULL ? nil:sqlite3_column_int64(stmt,1),name:String(cString:raw),identity:fi));status=sqlite3_step(stmt)
        }
        guard status==SQLITE_DONE,!result.isEmpty,result.first?.parent==nil,result.first?.name=="",result.count<=129 else { throw CleanerError(.invalidInput,"祖先链缺失、循环或越界") };return result
    }
    func entry(_ rid:Int64,hydrate:Bool)throws->Entry {
        let stmt=try prepare("SELECT n.id,s.id,p.id,n.metadata,d.json,n.logical,n.allocated,n.parent FROM entry_nodes n JOIN scans s ON s.sid=n.scan LEFT JOIN entry_nodes p ON p.rid=n.parent JOIN decisions d ON d.did=n.decision WHERE n.rid=?",[String(rid)]);defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt)==SQLITE_ROW,let scanText=sqlite3_column_text(stmt,1),let sid=UUID(uuidString:String(cString:scanText)),let decisionText=sqlite3_column_text(stmt,4) else { throw CleanerError(.invalidInput,"条目关系损坏") }
        let id=try Self.uuid(blob(stmt,0)),parent=sqlite3_column_type(stmt,2)==SQLITE_NULL ? nil:try Self.uuid(blob(stmt,2))
        let meta=try CompactMetadataCodec.decode(blob(stmt,3),volume:volumeName)
        let chain=try ancestors(rid,identities:hydrate)
        let path=chain.map(\.name).filter { !$0.isEmpty }.joined(separator:"/")
        var identity=meta.0
        if hydrate,let i=identity {
            var prefix="";var identities:[AncestorIdentity]=[]
            for ancestor in chain.dropLast() {
                if !ancestor.name.isEmpty { prefix=prefix.isEmpty ? ancestor.name:prefix+"/"+ancestor.name }
                guard let fi=ancestor.identity,fi.kind == .directory else { throw CleanerError(.invalidInput,"祖先目录身份缺失") }
                identities.append(AncestorIdentity(relativePath:prefix,device:fi.device.value,inode:fi.inode.value))
            }
            identity=FileIdentity(volumeID:i.volumeID,device:i.device.value,inode:i.inode.value,kind:i.kind,size:i.size.value,mtimeNs:i.mtimeNs,ctimeNs:i.ctimeNs,linkCount:i.linkCount.value,ownerUID:i.ownerUID.value,parentChain:identities)
        }
        let logical=sqlite3_column_type(stmt,5)==SQLITE_NULL ? nil:UInt64(exactly:sqlite3_column_int64(stmt,5)),allocated=sqlite3_column_type(stmt,6)==SQLITE_NULL ? nil:UInt64(exactly:sqlite3_column_int64(stmt,6))
        return Entry(id:id,scanID:sid,parentID:parent,relativePath:path,identity:identity,logicalBytes:logical,allocatedBytes:allocated,measureState:meta.1,decision:try Codec.decoder().decode(RuleDecision.self,from:Data(String(cString:decisionText).utf8)))
    }
    @discardableResult func insert(_ e:Entry,typed:[Int64]?=nil)throws->Int64 {
        let sid=try scan(e.scanID),parent=try e.parentID.map(node)
        let expectedParent:String
        if let id=e.parentID,let known=parents[id] { expectedParent=known.path;guard known.scan==sid else { throw CleanerError(.scopeEscape,"父目录跨扫描") } }
        else { expectedParent=try parent.map(path) ?? "" }
        let name=e.relativePath.split(separator:"/",omittingEmptySubsequences:false).last.map(String.init) ?? ""
        let expected=parent == nil ? "":expectedParent.isEmpty ? name:expectedParent+"/"+name
        guard expected.utf8.elementsEqual(e.relativePath.utf8),parent != nil || e.relativePath.isEmpty,parent==nil || !name.isEmpty,!name.contains("\0"),name != ".",name != ".." else { throw CleanerError(.scopeEscape,"basename/parent与原始路径不符") }
        if let parent,e.parentID.flatMap({ parents[$0] })==nil {
            let check=try prepare("SELECT scan,kind FROM entry_nodes WHERE rid=?",[String(parent)]);defer { sqlite3_finalize(check) }
            guard sqlite3_step(check)==SQLITE_ROW,sqlite3_column_int64(check,0)==sid,let kind=sqlite3_column_text(check,1),String(cString:kind)=="directory" else { throw CleanerError(.scopeEscape,"条目父目录跨扫描或不是目录") }
        }
        let did=try decision(e.decision),vid=try e.identity.map { try volume($0.volumeID) } ?? 0
        let metadata=try CompactMetadataCodec.encode(identity:e.identity,state:e.measureState,volume:vid)
        var values:[String?]=[nil,String(sid),parent.map(String.init),name,nil,String(did),e.identity?.kind.rawValue,e.logicalBytes.map { String($0.value) },e.allocatedBytes.map { String($0.value) }]
        values += [String(e.measureState == .measured ? 0:1),String(e.decision.disposition == .candidate || !e.decision.ruleIDs.isEmpty ? 1:0),"6"]
        values += Array(repeating:"0",count:8)
        values.append(e.measureState == .measured ? nil:e.relativePath)
        try execute("INSERT INTO entry_nodes(id,scan,parent,path,metadata,decision,kind,logical,allocated,unknown,candidate,category,counted_logical,counted_allocated,unique_leaf,modified,preview_cache,aggregate_logical,aggregate_allocated,aggregate_unknown,issue_path) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",values,blobs:[0:Self.uuidData(e.id),4:metadata])
        let rid=sqlite3_last_insert_rowid(db)
        if let typed {
            try execute("UPDATE entry_nodes SET category=?,counted_logical=?,counted_allocated=?,unique_leaf=?,modified=?,preview_cache=?,aggregate_logical=?,aggregate_allocated=?,aggregate_unknown=? WHERE rid=?",typed.map(String.init)+[String(rid)])
        }
        if e.identity?.kind == .directory {
            if parents.count>=4096 { parents.removeAll(keepingCapacity:true) }
            parents[e.id]=(rid,sid,e.relativePath);if directoryPaths.count>=8192 { directoryPaths.removeAll(keepingCapacity:true) };directoryPaths[rid]=e.relativePath
        }
        return rid
    }
    static let schema="""
    ALTER TABLE scans ADD COLUMN sid INTEGER;
    UPDATE scans SET sid=rowid;
    CREATE UNIQUE INDEX scan_sid ON scans(sid);
    CREATE TABLE entry_nodes(rid INTEGER PRIMARY KEY,id BLOB NOT NULL UNIQUE CHECK(length(id)=16),scan INTEGER NOT NULL,parent INTEGER,path TEXT NOT NULL,metadata BLOB NOT NULL CHECK(length(metadata)<=65568),decision INTEGER NOT NULL,kind TEXT,logical INTEGER,allocated INTEGER,unknown INTEGER NOT NULL,candidate INTEGER NOT NULL,category INTEGER NOT NULL DEFAULT 6,counted_logical INTEGER NOT NULL DEFAULT 0,counted_allocated INTEGER NOT NULL DEFAULT 0,unique_leaf INTEGER NOT NULL DEFAULT 0,modified INTEGER NOT NULL DEFAULT 0,preview_cache INTEGER NOT NULL DEFAULT 0,aggregate_logical INTEGER NOT NULL DEFAULT 0,aggregate_allocated INTEGER NOT NULL DEFAULT 0,aggregate_unknown INTEGER NOT NULL DEFAULT 0,issue_path TEXT);
    CREATE TABLE decisions(did INTEGER PRIMARY KEY,json TEXT NOT NULL UNIQUE);
    CREATE TABLE volumes(vid INTEGER PRIMARY KEY,value TEXT NOT NULL UNIQUE);
    CREATE TABLE inode_seen(scan INTEGER NOT NULL,device BLOB NOT NULL,inode BLOB NOT NULL,PRIMARY KEY(scan,device,inode)) WITHOUT ROWID;
    CREATE INDEX node_parent ON entry_nodes(scan,parent);
    CREATE INDEX node_allocated ON entry_nodes(scan,allocated DESC);
    CREATE INDEX node_logical ON entry_nodes(scan,logical DESC);
    CREATE INDEX node_modified ON entry_nodes(scan,modified);
    CREATE INDEX node_issues ON entry_nodes(scan,unknown,issue_path) WHERE unknown=1;
    CREATE INDEX node_topfolders ON entry_nodes(scan,parent,kind,aggregate_allocated DESC,path) WHERE kind='directory';
    """
    func migrateLegacy()throws {
        guard sqlite3_exec(db,Self.schema,nil,nil,nil)==SQLITE_OK else { throw CleanerError(.invalidInput,"紧凑结构创建失败") }
        let rows=try prepare("SELECT json,category,counted_logical,counted_allocated,unique_leaf,modified,preview_cache,aggregate_logical,aggregate_allocated,aggregate_unknown FROM entries ORDER BY rowid")
        var status=sqlite3_step(rows),count:Int64=0
        do {
            while status==SQLITE_ROW {
                guard let raw=sqlite3_column_text(rows,0),let cat=sqlite3_column_text(rows,1),let category=StorageCategory(rawValue:String(cString:cat)),let catIndex=StorageCategory.allCases.firstIndex(of:category) else { throw CleanerError(.invalidInput,"旧条目损坏") }
                let e=try Codec.decoder().decode(Entry.self,from:Data(String(cString:raw).utf8))
                var typed=[Int64(catIndex)]
                for i:Int32 in 2...9 {
                    guard sqlite3_column_type(rows,i)==SQLITE_INTEGER else { throw CleanerError(.invalidInput,"旧typed字段损坏") }
                    let value=sqlite3_column_int64(rows,i)
                    guard i==5 || value>=0 else { throw CleanerError(.invalidInput,"旧计量为负") }
                    guard (i != 4 && i != 6) || value<=1 else { throw CleanerError(.invalidInput,"旧Boolean损坏") }
                    typed.append(value)
                }
                let rid=try insert(e,typed:typed)
                let roundtrip=try entry(rid,hydrate:true)
                let legacyIdentity=try restoredLegacyIdentity(e)
                guard roundtrip.id==e.id,roundtrip.scanID==e.scanID,roundtrip.parentID==e.parentID,roundtrip.relativePath.utf8.elementsEqual(e.relativePath.utf8),roundtrip.identity==legacyIdentity,roundtrip.logicalBytes==e.logicalBytes,roundtrip.allocatedBytes==e.allocatedBytes,roundtrip.measureState==e.measureState,roundtrip.decision==e.decision else { throw CleanerError(.invalidInput,"紧凑迁移逐字段对照失败") }
                count+=1;status=sqlite3_step(rows)
            }
        } catch { sqlite3_finalize(rows);throw error }
        sqlite3_finalize(rows);guard status==SQLITE_DONE else { throw CleanerError(.invalidInput,"紧凑迁移未完成") }
        let seen=try prepare("SELECT scan,device,inode FROM measured");status=sqlite3_step(seen)
        do {
            while status==SQLITE_ROW {
                guard let s=sqlite3_column_text(seen,0),let sid=UUID(uuidString:String(cString:s)),let d=sqlite3_column_text(seen,1),let device=UInt64(String(cString:d)),let i=sqlite3_column_text(seen,2),let inode=UInt64(String(cString:i)) else { throw CleanerError(.invalidInput,"旧inode去重索引损坏") }
                try markInode(scan:scan(sid),device:device,inode:inode)
                status=sqlite3_step(seen)
            }
        } catch { sqlite3_finalize(seen);throw error }
        sqlite3_finalize(seen);guard status==SQLITE_DONE else { throw CleanerError(.invalidInput,"inode迁移未完成") }
        let actual=try prepare("SELECT count(*) FROM entry_nodes")
        let matches=sqlite3_step(actual)==SQLITE_ROW && sqlite3_column_int64(actual,0)==count
        let complete=sqlite3_step(actual)==SQLITE_DONE;sqlite3_finalize(actual)
        guard matches,complete else { throw CleanerError(.invalidInput,"迁移条数对照失败") }
        try execute("DROP TABLE entries");try execute("DROP TABLE measured")
    }
    private func restoredLegacyIdentity(_ e:Entry)throws->FileIdentity? {
        guard let fi=e.identity else { return nil }
        guard fi.parentChain.isEmpty,let parent=e.parentID else { return fi }
        let stmt=try prepare("WITH RECURSIVE chain(json,parent,depth,scan) AS (SELECT json,parent,0,scan FROM entries WHERE id=? UNION ALL SELECT e.json,e.parent,c.depth+1,e.scan FROM entries e JOIN chain c ON e.id=c.parent AND e.scan=c.scan WHERE c.depth<128) SELECT json FROM chain ORDER BY depth DESC",[parent.uuidString]);defer { sqlite3_finalize(stmt) }
        var chain:[AncestorIdentity]=[];var status=sqlite3_step(stmt)
        while status==SQLITE_ROW {
            guard let raw=sqlite3_column_text(stmt,0) else { throw CleanerError(.invalidInput,"旧祖先缺失") }
            let ancestor=try Codec.decoder().decode(Entry.self,from:Data(String(cString:raw).utf8))
            guard let identity=ancestor.identity,identity.kind == .directory else { throw CleanerError(.invalidInput,"旧祖先身份损坏") }
            if chain.isEmpty { guard ancestor.parentID==nil,ancestor.relativePath.isEmpty else { throw CleanerError(.invalidInput,"旧祖先链循环或缺根") } }
            chain.append(AncestorIdentity(relativePath:ancestor.relativePath,device:identity.device.value,inode:identity.inode.value));status=sqlite3_step(stmt)
        }
        guard status==SQLITE_DONE,!chain.isEmpty,chain.count<=128 else { throw CleanerError(.invalidInput,"旧祖先读取未完成") }
        return FileIdentity(volumeID:fi.volumeID,device:fi.device.value,inode:fi.inode.value,kind:fi.kind,size:fi.size.value,mtimeNs:fi.mtimeNs,ctimeNs:fi.ctimeNs,linkCount:fi.linkCount.value,ownerUID:fi.ownerUID.value,parentChain:chain)
    }
    @discardableResult func markInode(scan:Int64,device:UInt64,inode:UInt64)throws->Bool {
        var d=device.bigEndian,i=inode.bigEndian
        let dd=withUnsafeBytes(of:&d) { Data($0) },ii=withUnsafeBytes(of:&i) { Data($0) }
        try execute("INSERT OR IGNORE INTO inode_seen VALUES(?,?,?)",[String(scan),nil,nil],blobs:[1:dd,2:ii]);return sqlite3_changes(db)==1
    }
    func installFunctions()throws {
        let pointer=Unmanaged.passRetained(self).toOpaque()
        let result=sqlite3_create_function_v2(db,"lmc_entry",2,SQLITE_UTF8,pointer,{ ctx,argc,argv in
            guard let ctx,argc==2,let argv,let user=sqlite3_user_data(ctx) else { return }
            let adapter=Unmanaged<CompactIndexAdapter>.fromOpaque(user).takeUnretainedValue()
            do { let e=try adapter.entry(sqlite3_value_int64(argv[0]),hydrate:sqlite3_value_int(argv[1])==1);let json=String(decoding:try Codec.encoder().encode(e),as:UTF8.self);sqlite3_result_text(ctx,json,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
            catch { sqlite3_result_error(ctx,String(describing:error),-1) }
        },nil,nil,{ pointer in if let pointer { Unmanaged<CompactIndexAdapter>.fromOpaque(pointer).release() } })
        guard result==SQLITE_OK else { throw CleanerError(.invalidInput,"紧凑读取函数安装失败") }
        let second=Unmanaged.passRetained(self).toOpaque()
        guard sqlite3_create_function_v2(db,"lmc_path",1,SQLITE_UTF8,second,{ ctx,argc,argv in
            guard let ctx,argc==1,let argv,let user=sqlite3_user_data(ctx) else { return }
            let adapter=Unmanaged<CompactIndexAdapter>.fromOpaque(user).takeUnretainedValue()
            do { sqlite3_result_text(ctx,try adapter.path(sqlite3_value_int64(argv[0])),-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
            catch { sqlite3_result_error(ctx,String(describing:error),-1) }
        },nil,nil,{ pointer in if let pointer { Unmanaged<CompactIndexAdapter>.fromOpaque(pointer).release() } })==SQLITE_OK else { throw CleanerError(.invalidInput,"路径读取函数安装失败") }
    }
}
