import Foundation
import Compression
import CleanerDomain

/// Schema 5 metadata: exact integer/string fields, bounded decode, checksum and optional system LZFSE.
struct CompactMetadataCodec {
    private static let states:[MeasureState]=[.measured,.partial,.permissionDenied,.cancelled,.unsupported,.unknown]
    private static let kinds:[FileKind]=[.regular,.directory,.symlink,.other]
    static func encode(identity:FileIdentity?,state:MeasureState,volume:Int64) throws -> Data {
        var writer=Writer()
        writer.uint(UInt64(states.firstIndex(of:state)!))
        writer.uint(identity == nil ? 0:1)
        if let i=identity {
            writer.uint(UInt64(kinds.firstIndex(of:i.kind)!));writer.uint(UInt64(volume))
            for n in [i.device.value,i.inode.value,i.size.value,i.linkCount.value,i.ownerUID.value] { writer.uint(n) }
            writer.time(i.mtimeNs);writer.time(i.ctimeNs)
        }
        let raw=writer.data
        guard raw.count<=64*1024 else { throw bad("metadata too large") }
        let compressed=raw.count>=128 ? try (raw as NSData).compressed(using:.lzfse) as Data : raw
        let useCompression=compressed.count<raw.count
        var frame=Writer();frame.data.append(0xC5);frame.data.append(useCompression ? 1:0);frame.uint(UInt64(raw.count))
        var crc=checksum(raw).littleEndian
        withUnsafeBytes(of:&crc) { frame.data.append(contentsOf:$0) }
        frame.data.append(useCompression ? compressed:raw)
        return frame.data
    }
    static func decode(_ frame:Data,volume:(Int64)throws->String) throws -> (FileIdentity?,MeasureState) {
        guard frame.count<=65568 else { throw bad("frame bounds") }
        var reader=Reader(data:frame)
        guard try reader.byte()==0xC5 else { throw bad("metadata magic") }
        let codec=try reader.byte(),length=try reader.uint()
        guard length<=64*1024,codec<=1 else { throw bad("metadata bounds") }
        let crcBytes=try reader.bytes(4)
        let crc=crcBytes.withUnsafeBytes { UInt32(littleEndian:$0.loadUnaligned(as:UInt32.self)) }
        let encoded=try reader.bytes(frame.count-reader.offset)
        let raw:Data
        if codec==1 {
            // The system decoder may allocate its encoded output length; our own frame limits and postcheck bound accepted data.
            guard length>0,!encoded.isEmpty,encoded.count<=64*1024 else { throw bad("compressed bounds") }
            var output=Data(count:Int(length))
            let decoded=output.withUnsafeMutableBytes { destination in encoded.withUnsafeBytes { source in { ()->Int in
                guard let dest=destination.bindMemory(to:UInt8.self).baseAddress,let src=source.bindMemory(to:UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dest,Int(length),src,encoded.count,nil,COMPRESSION_LZFSE)
            }() } }
            guard decoded==Int(length) else { throw bad("LZFSE decode") };raw=output
        } else { raw=encoded }
        guard raw.count==Int(length),checksum(raw)==crc else { throw bad("metadata checksum") }
        var value=Reader(data:raw)
        let s=try value.uint(),present=try value.uint()
        guard s<states.count,present<=1 else { throw bad("metadata enums") }
        var identity:FileIdentity?
        if present==1 {
            let kind=try value.uint(),v=try value.uint()
            guard kind<kinds.count,v<=UInt64(Int64.max) else { throw bad("metadata identity") }
            let device=try value.uint(),inode=try value.uint(),size=try value.uint(),links=try value.uint(),uid=try value.uint()
            identity=FileIdentity(volumeID:try volume(Int64(v)),device:device,inode:inode,kind:kinds[Int(kind)],size:size,mtimeNs:try value.time(),ctimeNs:try value.time(),linkCount:links,ownerUID:uid,parentChain:[])
        }
        guard value.offset==raw.count else { throw bad("metadata trailing bytes") }
        return (identity,states[Int(s)])
    }
    private static func bad(_ detail:String)->CleanerError { CleanerError(.invalidInput,"紧凑索引损坏："+detail) }
    private static let crcTable:[UInt32]=(0..<256).map { index in var c=UInt32(index);for _ in 0..<8 { c=(c>>1) ^ (c&1==1 ? 0xEDB88320:0) };return c }
    private static func checksum(_ data:Data)->UInt32 { var c:UInt32=0xFFFFFFFF;for byte in data { c=(c>>8)^crcTable[Int((c^UInt32(byte))&255)] };return ~c }
    private struct Writer {
        var data=Data()
        mutating func uint(_ number:UInt64) { var n=number;while n>=128 { data.append(UInt8(n&127)|128);n >>= 7 };data.append(UInt8(n)) }
        mutating func string(_ value:String) { let bytes=Data(value.utf8);uint(UInt64(bytes.count));data.append(bytes) }
        mutating func time(_ value:String) {
            if let n=Int64(value),String(n)==value { data.append(0);uint((UInt64(bitPattern:n)&<<1)^UInt64(bitPattern:n>>63)) }
            else { data.append(1);string(value) }
        }
    }
    private struct Reader {
        let data:Data
        var offset=0
        mutating func byte()throws->UInt8 { guard offset<data.count else { throw bad("truncated") };defer { offset+=1 };return data[offset] }
        mutating func uint()throws->UInt64 { var result:UInt64=0;for shift in stride(from:0,through:63,by:7) { let b=try byte();if shift==63 && b>1 { throw bad("UInt64 overflow") };result |= UInt64(b&127)<<shift;if b&128==0 { return result } };throw bad("varint") }
        mutating func bytes(_ count:Int)throws->Data { guard count>=0,count<=data.count-offset else { throw bad("length") };defer { offset+=count };return data.subdata(in:offset..<(offset+count)) }
        mutating func time()throws->String { let tag=try byte();if tag==0 { let n=try uint();return String(Int64(bitPattern:(n>>1)^(0 &- (n&1)))) };guard tag==1 else { throw bad("time tag") };let count=try uint();guard count<=64*1024,let string=String(data:try bytes(Int(count)),encoding:.utf8) else { throw bad("UTF8") };return string }
    }
}
