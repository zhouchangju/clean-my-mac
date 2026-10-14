import Foundation
import CleanerDomain

/// Metadata-only capacity corpus. It does not create or read the represented files.
public struct SyntheticStorageCorpus: Sequence, Sendable {
    public enum Shape:String,Sendable { case typical, longRandom }
    public let scope:ScanScope
    public let scanID:UUID
    public let count:Int
    public let shape:Shape
    public init(scope:ScanScope,scanID:UUID,count:Int,shape:Shape = .typical) { self.scope=scope;self.scanID=scanID;self.count=count;self.shape=shape }
    public func makeIterator()->Iterator { Iterator(corpus:self) }
    public struct Iterator:IteratorProtocol {
        let corpus:SyntheticStorageCorpus
        var ordinal=0
        var parent:UUID?
        var prefix=""
        var chain:[AncestorIdentity]=[]
        var groupParent:UUID?
        var groupPath=""
        var groupChain:[AncestorIdentity]=[]
        let prefixes=["Users","sample","Library","Application Support","Metadata Only","Generated Assets","stable-long-segment"]
        mutating public func next()->Entry? {
            guard ordinal<corpus.count else { return nil }
            let n=ordinal;ordinal+=1
            let id=UUID()
            let isPrefix=n<=prefixes.count
            let directory=isPrefix || (n-prefixes.count-1)%6==0
            let relative:String
            let parentID:UUID?
            let ancestors:[AncestorIdentity]
            if n==0 { relative="";parentID=nil;ancestors=[] }
            else if isPrefix { relative=prefix.isEmpty ? prefixes[n-1]:prefix+"/"+prefixes[n-1];parentID=parent;ancestors=chain }
            else if directory { relative=prefix+"/g"+String((n-prefixes.count-1)/6);parentID=parent;ancestors=chain }
            else {
                let name:String
                if corpus.shape == .longRandom {
                    name=(0..<6).map { part in UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(part==5 ? 20:32) }.joined()+".dat"
                } else { name="file-"+String(n)+[".js",".txt",".png",".bin",".swift",".dat"][n%6] }
                relative=groupPath+"/"+name;parentID=groupParent;ancestors=groupChain
            }
            let size:UInt64=directory ? 128:UInt64((n*7919)%100_000_000)
            let allocated:UInt64=directory ? 0:((size+4095)/4096)*4096
            let fi=FileIdentity(volumeID:corpus.scope.rootIdentity.volumeID,device:corpus.scope.rootIdentity.device.value,inode:UInt64(8_000_000+n),kind:directory ? .directory:.regular,size:size,mtimeNs:String(Int64(1_700_000_000_000_000_000)+Int64(n)*1_000_000_000),ctimeNs:String(Int64(1_700_000_000_000_000_000)+Int64(n)*1_000_000_000+27),linkCount:1,ownerUID:501,parentChain:ancestors)
            let decision=RuleDecision(ruleIDs:[],category:["空间占用","开发文件","下载内容","应用与支持文件","文档与资料","其他文件"][n%6],disposition:.review,reasonCodes:["metadataOnly"],reason:"仅元数据容量实验，不是实际文件扫描",owner:"实验",rebuildCost:"未知")
            if isPrefix {
                parent=id;prefix=relative;chain=ancestors+[AncestorIdentity(relativePath:relative,device:fi.device.value,inode:fi.inode.value)]
            } else if directory {
                groupParent=id;groupPath=relative;groupChain=chain+[AncestorIdentity(relativePath:relative,device:fi.device.value,inode:fi.inode.value)]
            }
            return Entry(id:id,scanID:corpus.scanID,parentID:parentID,relativePath:relative,identity:fi,logicalBytes:directory ? nil:size,allocatedBytes:directory ? nil:allocated,measureState:.measured,decision:decision)
        }
    }
}
